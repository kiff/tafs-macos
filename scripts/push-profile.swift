// The Developer ID provisioning profile with push for a `PUSH=1` release (docs/release.md), fetched from App Store
// Connect with the key notarization already uses, and checked before it's embedded:
//   swift scripts/push-profile.swift <signing certificate SHA-1> <output .provisionprofile>
// with ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (the .p8) in the environment. Of the account's active Developer ID
// profiles, it keeps the one for this app whose certificates include the one the app is signed with, and whose
// entitlements give `aps-environment` production for `R54YWFRK4B.bot.tafs.macos`. Anything else stops the run. It prints
// only the profile's name and expiry, never a key or a token.
import CryptoKit
import Foundation

let team = "R54YWFRK4B"
let appID = "\(team).bot.tafs.macos"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("::error::\(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 3 else { fail("usage: push-profile.swift <certificate SHA-1> <output>") }
let certificateSHA1 = args[1].lowercased().filter(\.isHexDigit)
let output = URL(fileURLWithPath: args[2])
let env = ProcessInfo.processInfo.environment
guard let keyID = env["ASC_KEY_ID"], let issuer = env["ASC_ISSUER_ID"], let keyPath = env["ASC_KEY_PATH"],
      let pem = try? String(contentsOfFile: keyPath, encoding: .utf8) else { fail("ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH are needed") }
guard certificateSHA1.count == 40 else { fail("the signing certificate's SHA-1 is 40 hex digits") }

// App Store Connect's token: ES256 over the header and claims, valid for ten minutes.
func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
let now = Int(Date().timeIntervalSince1970)
let header = try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": keyID, "typ": "JWT"], options: [.sortedKeys])
let claims = try JSONSerialization.data(withJSONObject: ["iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"],
                                        options: [.sortedKeys])
let signingInput = base64URL(header) + "." + base64URL(claims)
guard let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else { fail("the App Store Connect key isn't a P-256 .p8") }
let token = signingInput + "." + base64URL(try key.signature(for: Data(signingInput.utf8)).rawRepresentation)

// The account's active Developer ID profiles for macOS apps.
var request = URLRequest(url: URL(string: "https://api.appstoreconnect.apple.com/v1/profiles?filter[profileType]=MAC_APP_DIRECT&filter[profileState]=ACTIVE&limit=200")!)
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
let done = DispatchSemaphore(value: 0)
var answer: (Data?, URLResponse?, Error?)
URLSession.shared.dataTask(with: request) { answer = ($0, $1, $2); done.signal() }.resume()
done.wait()
guard let body = answer.0, (answer.1 as? HTTPURLResponse)?.statusCode == 200 else {
    fail("App Store Connect didn't list the profiles (\((answer.1 as? HTTPURLResponse)?.statusCode ?? 0))")
}
struct Page: Decodable {
    struct Profile: Decodable {
        struct Attributes: Decodable { let name: String; let profileContent: String; let expirationDate: String? }
        let attributes: Attributes
    }
    let data: [Profile]
}
guard let page = try? JSONDecoder().decode(Page.self, from: body) else { fail("App Store Connect's list didn't read") }

/// A profile's signed plist, as `security cms -D` reads it.
func plist(_ profile: Data) -> [String: Any]? {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    guard (try? profile.write(to: file)) != nil else { return nil }
    let security = Process()
    security.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    security.arguments = ["cms", "-D", "-i", file.path]
    let out = Pipe()
    security.standardOutput = out
    security.standardError = FileHandle.nullDevice
    guard (try? security.run()) != nil else { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    security.waitUntilExit()
    return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
}

let matching: [(name: String, expires: String, content: Data)] = page.data.compactMap { profile in
    guard let content = Data(base64Encoded: profile.attributes.profileContent), let info = plist(content),
          let entitlements = info["Entitlements"] as? [String: Any],
          entitlements["com.apple.application-identifier"] as? String == appID,
          entitlements["com.apple.developer.aps-environment"] as? String == "production",
          let certificates = info["DeveloperCertificates"] as? [Data],
          certificates.contains(where: { Insecure.SHA1.hash(data: $0).map { String(format: "%02x", $0) }.joined() == certificateSHA1 })
    else { return nil }
    return (profile.attributes.name, profile.attributes.expirationDate ?? "?", content)
}
guard matching.count == 1, let chosen = matching.first else {
    fail("\(matching.count) active Developer ID profiles give push to \(appID) with the signing certificate: exactly one is needed")
}
do { try chosen.content.write(to: output) } catch { fail("the profile couldn't be written") }
print("push profile: \(chosen.name), until \(chosen.expires)")

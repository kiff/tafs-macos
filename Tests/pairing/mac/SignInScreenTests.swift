import AppKit
import Combine
import CryptoKit
import Foundation
import SwiftUI

private let sessionAnswer = #"{"access_token":"tok","token_type":"Bearer","expires_in":60,"tenant":"t1","subject":"u1","device_id":"dev_1"}"#
private let pending = (400, #"{"error":"authorization_pending"}"#)
private let expired = (400, #"{"error":"expired_token"}"#)

/// The device key, counting what it signs: the only key showing and renewing the phone's code
/// may use. It asks for nothing; a key that asked for Touch ID or a password would be another one.
private final class CountingKey: SigningKey {
    let key = SoftwareKey(key: .init())
    private(set) var signed: [Data] = []
    var publicKeyDER: Data { key.publicKeyDER }
    var keyStore: String { key.keyStore }
    func sign(_ message: Data) throws -> Data {
        signed.append(message)
        return try key.sign(message)
    }
}

@MainActor
private func model(_ answers: [(Int, String)], key: SigningKey, store: MemoryStore = MemoryStore()) -> (SignInModel, CannedTransport) {
    let transport = CannedTransport(answers)
    let model = SignInModel(client: KIFFClient(transport: transport), key: key, approval: .passkey, sessions: SessionStore(store: store),
                            deviceName: "tafs on this Mac", sleep: { _ in }, open: { _ in }, now: { Date(timeIntervalSince1970: 1_794_679_200) },
                            enclave: false, onboarding: false)
    return (model, transport)
}

private func wordsIn(_ language: String) throws -> Words {
    try Words(language: language, folder: URL(fileURLWithPath: ".shared/app/strings"))
}

let pairingSignInScreenTests: [Test] = [
    Test("the welcome has Try it with sample data under Continue, opening the sample: no key, no stream, its own transport", awaiting: { @MainActor in
        let (model, _) = model([], key: CountingKey())
        var opened = 0
        let with = SignInView(model: model, trySample: { opened += 1 }).environment(\.words, try wordsIn("en"))
        let without = SignInView(model: model).environment(\.words, try wordsIn("en"))
        guard let a = Snapshot.bitmap(of: with, size: CGSize(width: 1280, height: 800)),
              let b = Snapshot.bitmap(of: without, size: CGSize(width: 1280, height: 800)) else { throw Failure(description: "no bitmap") }
        try expect(Snapshot.png(a) != Snapshot.png(b), "the sample's button is drawn when given")
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: "build/screenshots"), withIntermediateDirectories: true)
        try Snapshot.png(a)?.write(to: URL(fileURLWithPath: "build/screenshots/welcome-try-sample.png"))
        try expectEqual(opened, 0)
        let app = try String(contentsOf: URL(fileURLWithPath: "Sources/App/entry/TafsApp.swift"), encoding: .utf8)
        try expect(app.contains("SignInView(model: signIn, trySample: { sample = SampleTransport(words: words, load: Self.sampleWords) })"), "the welcome opens the sample, its own transport")
        try expect(app.contains("route: .phoneOrPasskey, signedOut: { sample = nil }, inSample: true,"), "no key, no stream; leaving clears it")
        try expect(app.contains("playNextSample: { transport.playNext() })"), "its next round, on the window's one transport")
        let account = try String(contentsOf: URL(fileURLWithPath: "Sources/App/account/AccountView.swift"), encoding: .utf8)
        try expect(account.contains(#"action(words("settings.clear_sample"), color: Theme.no) { signOut() }"#), "Clear the sample")
    }),
    Test("the QR is shown as the window opens, signed by the device key alone, with no prompt", awaiting: { @MainActor in
        let key = CountingKey()
        let (model, transport) = model([pending, (200, sessionAnswer)], key: key)
        var codes: [SignInModel.Code] = [], sheets = 0
        let watching = model.$step.sink { if case .pairing(let code) = $0 { codes.append(code) } }
        let sheet = model.$pinSheet.sink { if $0 != nil { sheets += 1 } }
        await model.showPhoneCode()
        watching.cancel(); sheet.cancel()
        try expectEqual(codes.count, 1)
        let payload = try JSONDecoder().decode(PairingPayload.self, from: Data(codes[0].text.utf8))
        // One signature, the claim's proof over the code's nonce, and no PIN sheet.
        try expectEqual(key.signed, [Data(KIFFMessage.pairClaim(nonce: payload.nonce, keyHash: Signing.sha256Hex(key.publicKeyDER)).utf8)])
        try expectEqual(sheets, 0)
        try expectEqual(transport.sent.count, 2)
        try expectEqual(model.session?.deviceID, "dev_1")
        try expectEqual(model.justConnected, true)
    }),
    Test("a code that runs out is renewed silently: a new nonce, signed by the device key alone, with no prompt", awaiting: { @MainActor in
        let key = CountingKey()
        let (model, _) = model([expired, pending, (200, sessionAnswer)], key: key)
        var codes: [SignInModel.Code] = [], sheets = 0
        let watching = model.$step.sink { if case .pairing(let code) = $0 { codes.append(code) } }
        let sheet = model.$pinSheet.sink { if $0 != nil { sheets += 1 } }
        await model.showPhoneCode()
        try expectEqual(model.step, .codeExpired)
        // What the window does when the step changes: the plan renews the code by itself.
        await model.showPhoneCode()
        watching.cancel(); sheet.cancel()
        try expectEqual(codes.count, 2)
        let nonces = try codes.map { try JSONDecoder().decode(PairingPayload.self, from: Data($0.text.utf8)).nonce }
        try expect(nonces[0] != nonces[1], "a new nonce")
        try expectEqual(key.signed, nonces.map { Data(KIFFMessage.pairClaim(nonce: $0, keyHash: Signing.sha256Hex(key.publicKeyDER)).utf8) })
        try expectEqual(sheets, 0)
        try expectEqual(model.session?.deviceID, "dev_1")
    }),
    Test("showing the code asks for nothing: the pairing's code never asks for Touch ID or a password") {
        // The device key is made with no access control, and nothing on the sign-in path asks the person.
        for file in ["Keys.swift", "Signing.swift", "SignInModel.swift", "SignInView.swift", "SignInArt.swift", "ConnectedView.swift"] {
            let text = try String(contentsOf: URL(fileURLWithPath: "Sources/App/pairing/\(file)"), encoding: .utf8)
            for asking in ["LocalAuthentication", "LAContext", "evaluatePolicy", "SecAccessControl", "biometry"] {
                try expect(text.range(of: asking) == nil, "\(file) never names \(asking)")
            }
        }
    },
    Test("nothing starts by itself on a still picture, while signed in, or after a failure", awaiting: { @MainActor in
        let (still, stillSent) = model([], key: CountingKey())
        still.show(.welcome)
        await still.showPhoneCode()
        try expectEqual(stillSent.sent.count, 0)

        let store = MemoryStore()
        try SessionStore(store: store).save(Session(accessToken: "old", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_view"))
        let (signedIn, signedInSent) = model([], key: CountingKey(), store: store)
        await signedIn.showPhoneCode()
        try expectEqual(signedInSent.sent.count, 0)
        try expectEqual(signedIn.justConnected, false)

        let (failed, failedSent) = model([(403, #"{"error":"invalid_proof"}"#)], key: CountingKey())
        await failed.showPhoneCode()
        try expectEqual(failed.step, .failed(why: "invalidProof", pairing: true))
        await failed.showPhoneCode()
        try expectEqual(failedSent.sent.count, 1)
    }),
    Test("the window shows the QR on load, readable as the code's exact text, beside KIFF's half", awaiting: { @MainActor in
        let (model, _) = model([], key: CountingKey())
        let code = try sampleCode()
        model.show(.pairing(code))
        let view = SignInView(model: model).environment(\.words, try wordsIn("en"))
        guard let bitmap = Snapshot.settled(of: view, size: CGSize(width: 1280, height: 800), until: { qrText($0) == code.text }) else {
            throw Failure(description: "no bitmap")
        }
        try expectEqual(qrText(bitmap), code.text)
        // Two halves: the window's background on the left, the raised one on the right.
        try expect(near(bitmap, x: 8, y: 8, Palette.background.light), "the left half on the background")
        try expect(near(bitmap, x: 1272, y: 8, Palette.raised.light), "the right half on raised")
    }),
    Test("the code's panel shows the check code before this Mac's name, in English and French", awaiting: { @MainActor in
        for language in ["en", "fr"] {
            let words = try wordsIn(language)
            let lines = SignInPlan.codeLines(eyebrow: words("sign_in.your_code"), check: "K7Q2MX", name: words("pair.device_name", ["device": words("device.mac")]),
                                             waiting: words("sign_in.pair_waiting"))
            guard let code = lines.firstIndex(of: .code("K7Q2MX")), let name = lines.firstIndex(where: { if case .name = $0 { return true }; return false }) else {
                throw Failure(description: "no code or name in \(language)")
            }
            try expect(code < name, "the code before the name in \(language)")
        }
    }),
    Test("the screenshots: the two halves, the browser's code, a Mac adding itself, and connected, in English and French", awaiting: { @MainActor in
        try signInScreenshots()
    }),
]

/// The QR code a camera would read off the drawn window, if any.
private func qrText(_ bitmap: NSBitmapImageRep) -> String? {
    let image = NSImage(size: bitmap.size)
    image.addRepresentation(bitmap)
    return QRCode.read(image)
}

/// Whether the point is drawn in the colour, within a runner's rounding, as stored or as sRGB.
private func near(_ bitmap: NSBitmapImageRep, x: Int, y: Int, _ wanted: UInt32) -> Bool {
    Snapshot.hexes(bitmap, x: x, y: y).contains { got in
        [16, 8, 0].allSatisfy { abs(Int((got >> $0) & 0xFF) - Int((wanted >> $0) & 0xFF)) <= 6 }
    }
}

private func sampleCode() throws -> SignInModel.Code {
    let payload = PairingPayload(pub: String(repeating: "A", count: 122), approvalPub: nil, name: "tafs on this Mac", kind: .passkey,
                                 nonce: String(repeating: "n", count: 43), exp: "2026-11-14T18:05:00Z")
    return SignInModel.Code(text: try payload.text(), check: "K7Q2MX")
}

/// The sign-in window, drawn for the pull request in English and French.
@MainActor
func signInScreenshots() throws {
    Mascot.file = URL(fileURLWithPath: ".shared/ios/Shared/Mascot.xcassets/Mascot.imageset/mascot.png")
    let folder = URL(fileURLWithPath: "build/screenshots")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let start = DeviceStart(deviceCode: "dc", userCode: "ABCD-EFGH", verificationURI: "", verificationURIComplete: "", expiresIn: 600, interval: 5)
    let store = MemoryStore()
    try SessionStore(store: store).save(Session(accessToken: "old", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_view"))
    let shots: [(String, SignInModel.Step, MemoryStore)] = [("", .pairing(try sampleCode()), MemoryStore()), ("-browser", .browser(start), MemoryStore()),
                                                            ("-adding", .pairing(try sampleCode()), store)]
    func write<V: View>(_ view: V, _ name: String) throws {
        guard let bitmap = Snapshot.settled(of: view, size: CGSize(width: 1280, height: 800), tries: 6, until: { _ in false }),
              let png = Snapshot.png(bitmap) else {
            throw Failure(description: "no PNG for \(name)")
        }
        try png.write(to: folder.appendingPathComponent("\(name).png"))
    }
    for language in ["en", "fr"] {
        let words = try wordsIn(language)
        for (name, step, store) in shots {
            let (shown, _) = model([], key: CountingKey(), store: store)
            shown.show(step)
            try write(SignInView(model: shown).environment(\.words, words), "sign-in\(name)-\(language)")
        }
        try write(ConnectedView {}.environment(\.words, words), "sign-in-connected-\(language)")
    }
}

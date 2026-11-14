import Foundation

/// A device signed in as this person on the account (Account, Devices), as KIFF lists it.
struct Device: Decodable, Identifiable, Equatable {
    let id: String
    /// KIFF's name for it in the app's language, else the name it gave when it signed in.
    let name: String?
    let platform: String?
    /// Its key's fingerprint, as KIFF shows it: "3f2a 91c0 7b1e 0d44".
    let keyFingerprint: String?
    /// When it last reached KIFF; nil before its first use.
    let lastUsed: Date?
    let thisDevice: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, displayName = "display_name", platform, keyFingerprint = "key_fingerprint"
        case lastUsedAt = "last_used_at", lastSeenAt = "last_seen_at", thisDevice = "this_device"
    }

    init(id: String, name: String?, platform: String? = nil, keyFingerprint: String? = nil, lastUsed: Date? = nil, thisDevice: Bool = false) {
        self.id = id; self.name = name; self.platform = platform
        self.keyFingerprint = keyFingerprint; self.lastUsed = lastUsed; self.thisDevice = thisDevice
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .displayName) ?? c.decodeIfPresent(String.self, forKey: .name)
        platform = try c.decodeIfPresent(String.self, forKey: .platform)
        keyFingerprint = try c.decodeIfPresent(String.self, forKey: .keyFingerprint)
        lastUsed = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt) ?? c.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        thisDevice = try c.decodeIfPresent(Bool.self, forKey: .thisDevice) ?? false
    }
}

/// KIFF's routes for a signed-in Mac. Every request carries the session; one that KIFF wants
/// signed also carries the device key's signature over the exact bytes sent.
struct AccountClient {
    let transport: Transport
    let session: Session
    /// The language the app shows, so KIFF's own lines come in it.
    var language = "en"
    /// Makes the `KIFF-Device-Signature` header for a request, with the device key.
    var sign: ((HTTPRequest) throws -> String)?

    /// The devices signed in as this person on the account.
    func devices() async throws -> [Device] {
        struct Answer: Decodable { let devices: [Device] }
        let answer: Answer = try read(try await send("GET", "/v1/me/devices"))
        return answer.devices
    }

    /// Signs a device out of the account: it no longer approves, and its session is over.
    func removeDevice(_ id: String) async throws {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        _ = try await send("DELETE", "/v1/me/devices/\(id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id)")
    }

    /// Ends this Mac's session at KIFF.
    func signOut() async throws {
        _ = try await send("POST", "/v1/auth/device/logout", body: Data("{}".utf8))
    }

    /// Sends one request with the session, signed when `signed`, and answers its body.
    /// A refusal throws KIFF's code; `KIFFError.endsSession` says the session is over.
    func send(_ method: String, _ path: String, body: Data = Data(), signed: Bool = false) async throws -> Data {
        var request = HTTPRequest(method: method, path: path, headers: [
            "Authorization": "Bearer \(session.accessToken)", "Accept": "application/json",
            "Accept-Language": language, "User-Agent": "tafs-macos",
        ], body: body)
        if !body.isEmpty { request.headers["Content-Type"] = "application/json" }
        if signed {
            guard let sign else { throw KIFFError.refused(status: 0, code: "no_device_key") }
            request.headers["KIFF-Device-Signature"] = try sign(request)
        }
        let (status, answer) = try await transport.send(request)
        guard (200..<300).contains(status) else { throw KIFFError(status: status, body: answer) }
        return answer
    }

    private func read<Answer: Decodable>(_ body: Data) throws -> Answer {
        guard let answer = try? Self.decoder.decode(Answer.self, from: body) else { throw KIFFError.unreadable }
        return answer
    }

    /// KIFF's times: RFC 3339, with or without fractions of a second.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            let precise = ISO8601DateFormatter()
            precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = precise.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a time"))
        }
        return decoder
    }()
}

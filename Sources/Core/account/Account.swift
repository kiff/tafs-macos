import Foundation

/// A device signed in as this person on the account (Account, Devices), as KIFF lists it.
struct Device: Decodable, Identifiable, Equatable {
    let id: String
    /// KIFF's name for it in the app's language, else the name it gave when it signed in.
    let name: String?
    let platform: String?
    /// When it last reached KIFF; nil before its first use.
    let lastUsed: Date?
    let thisDevice: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, displayName = "display_name", platform
        case lastUsedAt = "last_used_at", lastSeenAt = "last_seen_at", thisDevice = "this_device"
    }

    init(id: String, name: String?, platform: String? = nil, lastUsed: Date? = nil, thisDevice: Bool = false) {
        self.id = id; self.name = name; self.platform = platform
        self.lastUsed = lastUsed; self.thisDevice = thisDevice
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .displayName) ?? c.decodeIfPresent(String.self, forKey: .name)
        platform = try c.decodeIfPresent(String.self, forKey: .platform)
        lastUsed = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt) ?? c.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        thisDevice = try c.decodeIfPresent(Bool.self, forKey: .thisDevice) ?? false
    }
}

/// Who is signed in, and how this session approves (`GET /v1/me`).
struct Me: Decodable, Equatable {
    /// The person's email, when KIFF says it.
    let email: String?
    /// The account's name, else its slug.
    let account: String?
    /// The account's id (its slug), as the iPad's `Account.slug`.
    let slug: String?
    /// How this session approves, in KIFF's word: `view`, `key`, `passkey`. Nil from a KIFF
    /// that doesn't say: the app then claims nothing about it.
    let approvalMode: String?
    /// What this person may do on the account, as KIFF says ("cards.manage", …); nil from a
    /// KIFF that doesn't say.
    let capabilities: [String]?
    /// The account's time zone, as KIFF says it ("Europe/Paris"), as the iPad's `Account.timeZone`.
    let timeZone: String?

    enum CodingKeys: String, CodingKey { case email, name = "tenant_display_name", slug = "tenant_slug", approvalMode = "approval_mode", capabilities, timeZone = "time_zone" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String? {
            guard let value = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return value
        }
        email = text(.email)
        account = text(.name) ?? text(.slug)
        slug = text(.slug)
        approvalMode = text(.approvalMode)
        capabilities = try c.decodeIfPresent([String].self, forKey: .capabilities)
        timeZone = try c.decodeIfPresent(String.self, forKey: .timeZone)
    }

    /// Whether this person manages the account's Cards (KIFF's `cards.manage`), as the iPad's
    /// `managesCards`: halting every taf is theirs. A KIFF that doesn't say leaves it to KIFF.
    var managesCards: Bool { capabilities.map { $0.contains("cards.manage") } ?? true }

    /// Whether this person manages the account's billing (KIFF's `billing.manage`), as the iPad's
    /// `managesBilling` (AppModel.swift:1089-1091): they answer members' requests; anyone else
    /// asks an admin. A KIFF that doesn't say lists no capabilities, and may.
    var managesBilling: Bool { capabilities.map { $0.contains("billing.manage") } ?? true }

    /// The KIFF account page's "Account id": the slug, only when the name isn't it, as the
    /// iPad's `AccountView` (SignInView.swift:443-445).
    var accountID: String? {
        guard let slug, slug != account else { return nil }
        return slug
    }

    /// Whether this person may delete the account (KIFF's `account.delete`), as the iPad's
    /// `mayDeleteAccount`: it's offered only then. A KIFF that doesn't say lists no
    /// capabilities, and may.
    var mayDeleteAccount: Bool { capabilities.map { $0.contains("account.delete") } ?? true }

    /// The session reads everything and approves nothing here: exactly when KIFF says `view`.
    var viewOnly: Bool { approvalMode == "view" }

    /// The "Signed in as" row: the email, unless it is the account's own name, as on the iPad.
    var signedInAs: String? {
        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else { return nil }
        if let account, email.caseInsensitiveCompare(account.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame { return nil }
        return email
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
    /// Signs one of KIFF's messages with the device key: the signature in standard base64.
    var signMessage: ((String) throws -> String)?
    /// Where the session's device key is kept (`SigningKey.keyStore`): `enclave` for the Secure
    /// Enclave, `software` otherwise; nil when not known. Only an `enclave` key ends a connection
    /// here, after Touch ID (`ConnectionEnding`); anything else goes to the phone.
    var keyStore: String?

    /// Who is signed in, and how this session approves.
    func me() async throws -> Me { try read(try await send("GET", "/v1/me")) }

    /// The devices signed in as this person on the account.
    func devices() async throws -> [Device] {
        struct Answer: Decodable { let devices: [Device] }
        let answer: Answer = try read(try await send("GET", "/v1/me/devices"))
        return answer.devices
    }

    /// What this person may do with each of the account's agents, by KIFF agent, as the iPad's
    /// `KIFFClient.myAccess`.
    func myAccess() async throws -> [String: Access] {
        struct Answer: Decodable { let agents: [String: Access] }
        let answer: Answer = try read(try await send("GET", "/v1/me/access"))
        return answer.agents
    }

    /// Signs a device out of the account: it no longer approves, and its session is over.
    /// Revokes a Card in KIFF, as the iPad's `revoke(cardID:)` (KIFFClient.swift:1175-1177): a plain session call,
    /// no signature, since it only takes authority away. KIFF refuses it for a view-only session.
    func revoke(cardID: String) async throws {
        _ = try await send("POST", "/v1/me/mandates/\(CloudClient.escaped(cardID))/revoke", body: Data("{}".utf8))
    }

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

    func read<Answer: Decodable>(_ body: Data) throws -> Answer {
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

/// What a person may do with a taf, as KIFF answers it: use it, see everyone's work with it,
/// change it (halt it, its Card, its versions).
/// Decoded as the iPad's `KIFFClient.Access` (KIFFClient.swift:1417-1422): each flag is a
/// required Bool and `groups` an optional list, so a flag missing or mistyped fails the read.
struct Access: Decodable, Equatable {
    var use = false
    var oversee = false
    var manage = false
    var groups: [String]? = nil

    /// Whether this person manages the taf, as the iPad's `manages`: without KIFF's answer for
    /// it (not read yet, or failed), nothing is shown.
    static func manages(_ access: Access?) -> Bool { access?.manage ?? false }
}

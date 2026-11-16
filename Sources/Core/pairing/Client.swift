import Foundation

/// One request to KIFF, as it goes on the wire. The body's bytes are the ones a signature covers.
struct HTTPRequest: Equatable {
    var method: String
    /// The path and query, relative to the API's base.
    var path: String
    var headers: [String: String] = [:]
    var body = Data()
}

/// What carries a request to KIFF: the network in the app, canned answers in tests.
protocol Transport {
    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data)
    /// The same, with the answer's `ETag`, for a read asked again with `If-None-Match`.
    func exchange(_ request: HTTPRequest) async throws -> (status: Int, body: Data, etag: String?)
}

extension Transport {
    /// A transport that doesn't read headers answers no `ETag`.
    func exchange(_ request: HTTPRequest) async throws -> (status: Int, body: Data, etag: String?) {
        let (status, body) = try await send(request)
        return (status, body, nil)
    }
}

/// Why KIFF didn't do what was asked, by the code it answered.
enum KIFFError: Error, Equatable {
    /// The person hasn't approved yet: ask again after the interval.
    case authorizationPending
    /// Asked too often: wait longer between asks.
    case slowDown
    /// The code's time passed, or it was already used: start again.
    case expired
    /// A pairing's claim wasn't signed by the key the phone approved.
    case invalidProof
    /// Any other refusal, with KIFF's own code for it.
    case refused(status: Int, code: String)
    /// An answer that isn't what the contract says.
    case unreadable

    /// Whether KIFF no longer knows this session: signed out, or the device was removed.
    var endsSession: Bool {
        if case .refused(status: 401, code: _) = self { return true }
        return false
    }

    init(status: Int, body: Data) {
        struct Refusal: Decodable { let error: String? }
        let code = (try? JSONDecoder().decode(Refusal.self, from: body))?.error ?? ""
        switch (status, code) {
        case (400, "authorization_pending"): self = .authorizationPending
        case (400, "slow_down"): self = .slowDown
        case (400, "expired_token"): self = .expired
        case (403, "invalid_proof"): self = .invalidProof
        default: self = .refused(status: status, code: code)
        }
    }
}

/// What a new sign-in shows the person: the code to check, and where they approve it.
struct DeviceStart: Decodable, Equatable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let verificationURIComplete: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code", userCode = "user_code", verificationURI = "verification_uri"
        case verificationURIComplete = "verification_uri_complete", expiresIn = "expires_in", interval
    }
}

/// A session, handed over once. Its token is kept in the Keychain and never written elsewhere.
struct Session: Codable, Equatable {
    let accessToken: String
    let expiresIn: Int
    let tenant: String
    let subject: String
    /// This Mac's id in the Devices list, when KIFF says it (a pairing's claim does).
    let deviceID: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", expiresIn = "expires_in", tenant, subject, deviceID = "device_id"
    }
}

/// How this Mac approves, said when it signs in: with its own approval key, or with none.
enum ApprovalMeans: Equatable {
    /// An approval key in the Secure Enclave, behind Touch ID: its public half, SPKI DER.
    case key(Data)
    /// No approval key: an approval is signed by a passkey or on the phone.
    case passkey
}

/// KIFF's sign-in and pairing routes for a computer (`docs/desktop-client.md`, §1.1 and §5.4).
struct KIFFClient {
    let transport: Transport

    /// Starts a sign-in as a new device. `publicKey` is the device key (SPKI DER), and
    /// `keyStore` says where its private half is.
    func startSignIn(publicKey: Data, keyStore: String, name: String, approval: ApprovalMeans) async throws -> DeviceStart {
        var body = ["public_key": publicKey.base64EncodedString(), "device_name": name, "platform": "macos", "kind": "other"]
        // A device key outside hardware never approves: it says so, and sends no approval key.
        if keyStore == "software" {
            body["key_store"] = "software"
            body["approval"] = "passkey"
        } else if case .key(let der) = approval {
            body["approval_public_key"] = der.base64EncodedString()
        } else {
            body["approval"] = "passkey"
        }
        return try await post("/v1/auth/device/start", body)
    }

    /// One ask for the sign-in's session. Throws `.authorizationPending` until the person approves.
    func token(deviceCode: String) async throws -> Session {
        try await post("/v1/auth/device/token", ["device_code": deviceCode])
    }

    /// One ask for a pairing's session, with the proof that this Mac holds the device key.
    /// `publicKey` is as the QR code wrote it (base64url). With `credentialProof`, the claim proves
    /// the QR's credential was made for this pairing (`credential_proof`, as Windows'
    /// `PairingClaim.BodyAsync`).
    func claimPairing(nonce: String, publicKey: String, proof: String, credentialProof: CredentialProof? = nil) async throws -> Session {
        struct Claim: Encodable {
            let nonce: String, pub: String, proof: String
            let credentialProof: [String: String]?
            enum CodingKeys: String, CodingKey { case nonce, pub, proof, credentialProof = "credential_proof" }
        }
        return try await post("/v1/pair/claim", Claim(nonce: nonce, pub: publicKey, proof: proof, credentialProof: credentialProof?.fields))
    }

    private func post<Answer: Decodable, Fields: Encodable>(_ path: String, _ fields: Fields) async throws -> Answer {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let request = HTTPRequest(method: "POST", path: path, headers: ["Content-Type": "application/json"],
                                  body: try encoder.encode(fields))
        let (status, body) = try await transport.send(request)
        guard (200..<300).contains(status) else { throw KIFFError(status: status, body: body) }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: body) else { throw KIFFError.unreadable }
        return answer
    }
}

/// Asks again and again until KIFF hands over the session, as the contract paces it.
enum Waiting {
    /// The longest a sign-in or a pairing is waited for, whatever the server says.
    static let longest: TimeInterval = 10 * 60

    /// Runs `ask` every `interval` seconds until it answers. "Not yet" asks again; "slow down"
    /// adds 5 seconds to the interval for good (RFC 8628); anything else ends the wait. Past
    /// `expiresIn` seconds of waiting it ends as expired without asking again.
    static func until<Answer>(interval: TimeInterval, expiresIn: TimeInterval,
                              sleep: (TimeInterval) async throws -> Void,
                              ask: () async throws -> Answer) async throws -> Answer {
        var interval = interval
        var waited: TimeInterval = 0
        let limit = min(expiresIn, longest)
        while true {
            guard waited + interval <= limit else { throw KIFFError.expired }
            try await sleep(interval)
            waited += interval
            do {
                return try await ask()
            } catch KIFFError.authorizationPending {
                continue
            } catch KIFFError.slowDown {
                interval += 5
            }
        }
    }
}

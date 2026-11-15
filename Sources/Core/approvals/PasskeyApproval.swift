import Foundation

/// Approving on a Mac with no approval key of its own: the person's passkey, a USB security key,
/// signs the exact request, sent as `KIFF-Passkey-Assertion` (the public spec's
/// `docs/secure-connection.md`: the request's message, its digest as the challenge, and one
/// approval for a pair). This is the message, the `clientDataJSON` this app builds, the checks
/// made before sending, and the header, as Windows' `PasskeyApprover`. The authenticator itself is
/// behind `PasskeyAuthenticator`.
///
/// **Off** (`Features.macPasskeyApprovals`) until the public spec names the macOS 12 security-key
/// route: switched off, nothing is asked of the authenticator.
///
/// Core builds on Linux, so hashing is passed in (`sha256`): the app gives CryptoKit's.
enum Features {
    /// Passkey approvals on macOS 12. Off: `PasskeyApprover` refuses before the security key is
    /// asked, as Windows' `Features.WindowsPasskeyApprovals` was until KIFF took its passkey.
    static let macPasskeyApprovals = false
}

enum Passkeys {
    /// The relying party: KIFF.
    static let rpID = "kiff.dev"
    /// The origin written in `clientDataJSON`. Over raw CTAP2 this app writes it, as Windows does.
    static let origin = "https://kiff.dev"
    /// The header a passkey's approval goes in.
    static let headerName = "KIFF-Passkey-Assertion"
}

/// authenticatorData's fixed head: rpIdHash (32), flags (1), signCount (4, big-endian).
struct AuthenticatorData: Equatable {
    let rpIDHash: Data
    let flags: UInt8
    let signCount: UInt32

    var userPresent: Bool { flags & 0x01 != 0 }
    var userVerified: Bool { flags & 0x04 != 0 }
    var backupEligible: Bool { flags & 0x08 != 0 }
    var backedUp: Bool { flags & 0x10 != 0 }
    var hasCredentialData: Bool { flags & 0x40 != 0 }

    init(_ data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= 37 else { throw PasskeyRefusal.unreadable }
        rpIDHash = Data(bytes[0..<32])
        flags = bytes[32]
        signCount = bytes[33..<37].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }
}

/// Why a passkey's answer isn't sent: each is refused here, before anything leaves this Mac,
/// because KIFF would refuse it too.
enum PasskeyRefusal: Error, Equatable {
    /// The authenticator answered for another relying party than kiff.dev.
    case notKIFF
    /// No user presence, or no user verification (the key's PIN wasn't checked).
    case notVerified
    /// A synced passkey (backup eligible, or backed up), which the public spec doesn't take for a
    /// computer's approval. A USB security key reports neither: it goes with the computer it was
    /// paired with, and signing that computer out removes it; plugged in elsewhere, its PIN is
    /// still asked.
    case canLeave
    /// Passkey approvals are switched off (`Features.macPasskeyApprovals`): nothing was asked.
    case off
    /// The authenticator answered with another credential than the one asked for.
    case otherCredential
    /// The authenticator data, or a new credential, couldn't be read.
    case unreadable
    /// A new credential that isn't ES256 on P-256, the only key KIFF takes.
    case notES256
}

/// What the authenticator returns for one assertion.
struct PasskeyAssertion: Equatable {
    let authenticatorData: Data
    /// The ECDSA signature, DER, over `authenticatorData ‖ clientDataHash`.
    let signatureDER: Data
    /// The credential the authenticator used, when it says (CTAP2 does); nil takes the one asked for.
    var credentialID: Data? = nil
}

/// What the authenticator returns for a new credential.
struct PasskeyMade: Equatable {
    let authenticatorData: Data
    /// The attestation object as returned, for KIFF's creation proof (`credential_proof`).
    let attestationObject: Data
}

/// The security key, over libfido2 in the app (the next change); a fake in tests. It's given the
/// hash of the `clientDataJSON` this app built, never the JSON, as CTAP2 takes it. The PIN, when
/// given, is used once and its buffer cleared by the caller.
protocol PasskeyAuthenticator {
    func getAssertion(clientDataHash: Data, credentialID: Data, pin: [UInt8]?) async throws -> PasskeyAssertion
    func makeCredential(clientDataHash: Data, userID: Data, userName: String, pin: [UInt8]?) async throws -> PasskeyMade
}

/// Approves one exact request, or two together, with this Mac's registered passkey, as Windows'
/// `PasskeyApprover`. The challenge is base64url(sha256(message)), so the assertion is bound to
/// that message, as an approval key's signature would be. KIFF verifies; this side refuses early
/// what KIFF would refuse anyway, whatever the authenticator says.
struct PasskeyApprover {
    let authenticator: PasskeyAuthenticator
    /// The account's security key this Mac approves with, registered through its pairing.
    let credentialID: Data
    let sha256: (Data) -> Data
    /// Whether passkey approvals are on; off, nothing is asked of the authenticator.
    var enabled = Features.macPasskeyApprovals

    /// The challenge: base64url of the message's SHA-256.
    static func challenge(_ message: Data, sha256: (Data) -> Data) -> String { Encoding.base64URL(sha256(message)) }

    /// The exact `clientDataJSON` bytes this app builds and the authenticator's hash covers, in
    /// Windows' order: `{"type":"webauthn.get","challenge":…,"origin":"https://kiff.dev","crossOrigin":false}`.
    static func clientDataJSON(_ message: Data, sha256: (Data) -> Data) -> Data {
        // A base64url challenge needs no escaping; the order is fixed, as the bytes are hashed.
        Data(#"{"type":"webauthn.get","challenge":"\#(challenge(message, sha256: sha256))","origin":"\#(Passkeys.origin)","crossOrigin":false}"#.utf8)
    }

    /// Why KIFF would refuse an assertion with this authenticator data, or nil: another relying
    /// party, no presence or no verification, or a synced passkey (backup eligible or backed up).
    static func refusal(_ data: AuthenticatorData, sha256: (Data) -> Data) -> PasskeyRefusal? {
        if data.rpIDHash != sha256(Data(Passkeys.rpID.utf8)) { return .notKIFF }
        if !data.userPresent || !data.userVerified { return .notVerified }
        if data.backupEligible || data.backedUp { return .canLeave }
        return nil
    }

    /// One fresh assertion over `message`, as the header's `t=…,a=…`. Only this file's two shapes
    /// reach it: one request (`approve`) and the pair (`RequestsTogether.approve`), each with the
    /// `signedAt` that went into its message. Switched off, it refuses before the key is asked.
    fileprivate func sign(_ message: Data, signedAt: String, pin: [UInt8]?) async throws -> String {
        guard enabled else { throw PasskeyRefusal.off }
        let clientData = Self.clientDataJSON(message, sha256: sha256)
        let assertion = try await authenticator.getAssertion(clientDataHash: sha256(clientData), credentialID: credentialID, pin: pin)
        if let used = assertion.credentialID, used != credentialID { throw PasskeyRefusal.otherCredential }
        if let refusal = Self.refusal(try AuthenticatorData(assertion.authenticatorData), sha256: sha256) { throw refusal }
        // KIFF reads the fields by name; written in Windows' order.
        let fields = [
            ("credential_id", credentialID), ("client_data_json", clientData),
            ("authenticator_data", assertion.authenticatorData), ("signature", assertion.signatureDER),
        ].map { #""\#($0.0)":"\#(Encoding.base64URL($0.1))""# }
        let json = Data(("{" + fields.joined(separator: ",") + "}").utf8)
        return "t=\(signedAt),a=\(Encoding.base64URL(json))"
    }

    /// Approves one request: its `kiff.request.v1`, at a signing time never used twice.
    func approve(tenant: String, method: String, path: String, body: Data, signedAt: String = SigningTime.next(),
                 pin: [UInt8]? = nil) async throws -> String {
        let message = KIFFMessage.request(tenant: tenant, method: method, path: path,
                                          bodyHash: Encoding.hex(sha256(body)), signedAt: signedAt)
        return try await sign(Data(message.utf8), signedAt: signedAt, pin: pin)
    }
}

/// Two requests under one approval (`kiff.requests.v1`), as the iPad's and Windows'
/// `RequestsTogether`: both built in full with one `signed_at`, approved once over the two request
/// messages' hashes. Each service rebuilds its own request's message, takes the other's hash as
/// given (`with`), and checks the one assertion.
enum RequestsTogether {
    static let scheme = "kiff.requests.v1"

    /// One request to send in the pair: its method, path (with any query) and exact body.
    struct Request: Equatable {
        let method: String
        let path: String
        let body: Data
    }

    /// A request message's hash, as both services write it: lowercase hex SHA-256.
    static func hash(_ message: Data, sha256: (Data) -> Data) -> String { Encoding.hex(sha256(message)) }

    /// What is approved: the scheme, the account, the one `signed_at`, and the two hashes in
    /// sorted order, a line each.
    static func message(tenant: String, signedAt: String, _ one: String, _ other: String) -> Data {
        let hashes = one <= other ? [one, other] : [other, one]
        return Data(([scheme, tenant, signedAt] + hashes).joined(separator: "\n").utf8)
    }

    /// The pair approved by this Mac's passkey: one assertion, its challenge over the pair's
    /// message, in each request's `KIFF-Passkey-Assertion: t=…,a=…,with=sha256:<the other's hash>`.
    static func approve(_ approver: PasskeyApprover, tenant: String, _ first: Request, _ second: Request,
                        signedAt: String = SigningTime.next(), pin: [UInt8]? = nil) async throws -> (first: String, second: String) {
        func own(_ request: Request) -> String {
            let message = KIFFMessage.request(tenant: tenant, method: request.method, path: request.path,
                                              bodyHash: Encoding.hex(approver.sha256(request.body)), signedAt: signedAt)
            return hash(Data(message.utf8), sha256: approver.sha256)
        }
        let (a, b) = (own(first), own(second))
        let assertion = try await approver.sign(message(tenant: tenant, signedAt: signedAt, a, b), signedAt: signedAt, pin: pin)
        return ("\(assertion),with=sha256:\(b)", "\(assertion),with=sha256:\(a)")
    }
}

/// A new credential, as KIFF registers it through pairing: its id and its P-256 public key, SPKI DER.
struct NewPasskey: Equatable {
    let credentialID: Data
    let publicKeyDER: Data
}

/// Reads a newly made credential's authenticator data (attested credential data, then the COSE
/// key), as Windows' `PasskeyRegistration`, and refuses what could never approve for this Mac:
/// another relying party, no verification, a synced passkey, or anything but ES256 on P-256. `isOnCurve` checks the point (CryptoKit in the app): a point off the curve is refused.
enum PasskeyRegistration {
    static func read(_ authenticatorData: Data, sha256: (Data) -> Data,
                     isOnCurve: (_ x: Data, _ y: Data) -> Bool) throws -> NewPasskey {
        let head = try AuthenticatorData(authenticatorData)
        if let refusal = PasskeyApprover.refusal(head, sha256: sha256) { throw refusal }
        guard head.hasCredentialData else { throw PasskeyRefusal.unreadable }
        // From 37: the AAGUID (16), the credential id's length (2, big-endian), the id, the COSE key.
        let bytes = [UInt8](authenticatorData)
        let start = 37
        guard bytes.count >= start + 18 else { throw PasskeyRefusal.unreadable }
        let idLength = Int(bytes[start + 16]) << 8 | Int(bytes[start + 17])
        let idStart = start + 18
        guard idLength > 0, bytes.count >= idStart + idLength else { throw PasskeyRefusal.unreadable }
        let id = Data(bytes[idStart..<(idStart + idLength)])
        let (x, y) = try coseKey(Array(bytes[(idStart + idLength)...]))
        guard isOnCurve(x, y) else { throw PasskeyRefusal.notES256 }
        return NewPasskey(credentialID: id, publicKeyDER: spki(x: x, y: y))
    }

    /// The challenge a pairing's passkey is made with (the public spec's pairing), as Windows'
    /// `PairingClaim.PasskeyChallenge`: base64url(sha256 of `kiff.passkey.pair.v1`, the nonce and
    /// the device key's base64url, a line each), the nonce and key as the QR writes them.
    static func pairingChallenge(nonce: String, deviceKeyDER: Data, sha256: (Data) -> Data) -> String {
        let message = ["kiff.passkey.pair.v1", nonce, Encoding.base64URL(deviceKeyDER)].joined(separator: "\n")
        return Encoding.base64URL(sha256(Data(message.utf8)))
    }

    /// An uncompressed P-256 point as SubjectPublicKeyInfo DER: the fixed header for
    /// id-ecPublicKey with prime256v1, then 04 ‖ x ‖ y.
    static func spki(x: Data, y: Data) -> Data {
        let header: [UInt8] = [0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
                               0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00, 0x04]
        return Data(header) + x + y
    }

    /// An ES256 COSE_Key: kty 2 (EC2), alg -7, crv 1 (P-256), x and y of 32 bytes. Anything else
    /// is refused: KIFF takes ES256 only, and a key named twice is refused. Just enough CBOR for
    /// that: a map, small integers and byte strings.
    static func coseKey(_ cbor: [UInt8]) throws -> (Data, Data) {
        var reader = CBORReader(cbor)
        let entries = try reader.head(major: 5)
        var kty: Int64?, alg: Int64?, crv: Int64?
        var x: Data?, y: Data?
        var seen: Set<Int64> = []
        for _ in 0..<entries {
            let label = try reader.integer()
            guard seen.insert(label).inserted else { throw PasskeyRefusal.notES256 }
            switch label {
            case 1: kty = try reader.integer()
            case 3: alg = try reader.integer()
            case -1: crv = try reader.integer()
            case -2: x = try reader.bytes()
            case -3: y = try reader.bytes()
            default: throw PasskeyRefusal.notES256
            }
        }
        guard kty == 2, alg == -7, crv == 1, let x, x.count == 32, let y, y.count == 32 else { throw PasskeyRefusal.notES256 }
        return (x, y)
    }

    private struct CBORReader {
        private var rest: ArraySlice<UInt8>
        init(_ bytes: [UInt8]) { rest = bytes[...] }

        mutating func integer() throws -> Int64 {
            guard let first = rest.first else { throw PasskeyRefusal.unreadable }
            switch first >> 5 {
            case 0: return Int64(try head(major: 0))
            case 1: return -1 - Int64(try head(major: 1))
            default: throw PasskeyRefusal.notES256
            }
        }

        mutating func bytes() throws -> Data { Data(try take(Int(try head(major: 2)))) }

        mutating func head(major: UInt8) throws -> UInt64 {
            guard let first = rest.first, first >> 5 == major else { throw PasskeyRefusal.unreadable }
            rest = rest.dropFirst()
            switch first & 31 {
            case let info where info < 24: return UInt64(info)
            case 24: return UInt64(try take(1)[0])
            case 25: return try take(2).reduce(0) { $0 << 8 | UInt64($1) }
            case 26: return try take(4).reduce(0) { $0 << 8 | UInt64($1) }
            default: throw PasskeyRefusal.unreadable
            }
        }

        private mutating func take(_ n: Int) throws -> [UInt8] {
            guard n >= 0, rest.count >= n else { throw PasskeyRefusal.unreadable }
            defer { rest = rest.dropFirst(n) }
            return Array(rest.prefix(n))
        }
    }
}

import Foundation

/// The messages a computer signs for KIFF, and how they are written on the wire: fields
/// joined by a line feed with no trailing one, lowercase hex, RFC 3339 times
/// (KIFF's `docs/desktop-client.md`, §2 and §5).
enum KIFFMessage {
    /// What a signed request's signature covers: `kiff.request.v1`, or `kiff.request.v2` with
    /// the approval window's id as a last line.
    static func request(tenant: String, method: String, path: String, bodyHash: String,
                        signedAt: String, window: String? = nil) -> String {
        var fields = [window == nil ? "kiff.request.v1" : "kiff.request.v2", tenant, method, path, bodyHash, signedAt]
        if let window { fields.append(window) }
        return fields.joined(separator: "\n")
    }

    /// The `KIFF-Device-Signature` header's value, for a signature in standard base64.
    static func header(signedAt: String, signature: String, window: String? = nil) -> String {
        guard let window else { return "t=\(signedAt),v1=\(signature)" }
        return "t=\(signedAt),v2=\(signature),w=\(window)"
    }

    /// What a computer signs with its device key to claim a pairing: proof it holds the key.
    static func pairClaim(nonce: String, keyHash: String) -> String {
        ["kiff.pair.claim.v1", nonce, keyHash].joined(separator: "\n")
    }

    /// A time as KIFF reads it: RFC 3339, in UTC, to the second.
    static func time(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

/// What the pairing QR code holds (`kiff.pair.v1`): this computer's public keys and name,
/// for a phone that can already approve to sign. No secret is in it.
struct PairingPayload: Codable, Equatable {
    enum Kind: String, Codable {
        /// The approval key is in the Secure Enclave, behind Touch ID.
        case enclave
        /// No approval key: this computer approves with a passkey or on the phone.
        case passkey
    }

    var v = "kiff.pair.v1"
    /// The device key: base64url of its SPKI DER.
    let pub: String
    /// The approval key, the same way; nil for `passkey`.
    let approvalPub: String?
    let name: String
    var platform = "macos"
    let kind: Kind
    /// `software` when the device key isn't in hardware (only with `passkey`), absent otherwise.
    /// The phone's signature covers it, so KIFF never lets that key approve.
    var keyStore: String?
    /// This Mac's security key, which the pairing registers for it (only with `passkey`, never with
    /// a software device key): its credential id and public key, base64url, the key as SPKI DER.
    var credential: Credential?
    /// Base64url of 32 random bytes. The computer keeps it to claim the pairing.
    let nonce: String
    /// When the code stops working, at most 5 minutes ahead.
    let exp: String

    enum CodingKeys: String, CodingKey { case v, pub, approvalPub = "approval_pub", name, platform, kind, keyStore = "key_store", credential, nonce, exp }

    /// A credential as the QR names it (`{id, public_key}`), as Windows' `ToQrJson` and the phones'
    /// `PairingRequest.Credential` read it.
    struct Credential: Codable, Equatable {
        let id: String
        let publicKey: String
        enum CodingKeys: String, CodingKey { case id, publicKey = "public_key" }
    }

    /// The payload for a Mac's keys. A device key outside hardware is said so, and such a
    /// Mac has no approval key and no credential in the code, whatever was passed (it pairs as
    /// view). A credential goes only with `passkey`: never beside an approval key, as Windows'
    /// `PairingOffer.Create` and §5.1.
    init(deviceKey: Data, keyStore: String, approvalKey: Data?, name: String, nonce: String, exp: String,
         credential: Credential? = nil) {
        let software = keyStore == "software"
        let approval = software ? nil : approvalKey
        self.init(pub: Encoding.base64URL(deviceKey), approvalPub: approval.map(Encoding.base64URL), name: name,
                  kind: approval == nil ? .passkey : .enclave, keyStore: software ? "software" : nil,
                  credential: software || approval != nil ? nil : credential, nonce: nonce, exp: exp)
    }

    init(pub: String, approvalPub: String?, name: String, kind: Kind, keyStore: String? = nil, credential: Credential? = nil,
         nonce: String, exp: String) {
        self.pub = pub; self.approvalPub = approvalPub; self.name = name
        self.kind = kind; self.keyStore = keyStore; self.credential = credential; self.nonce = nonce; self.exp = exp
    }

    /// The key the check code covers after the device key (§5.2): the approval key, or in its
    /// place the credential's, so the code covers the key the phone registers; nil with neither.
    var checkedKeyDER: Data? {
        (approvalPub ?? credential?.publicKey).flatMap(Encoding.fromBase64URL)
    }

    /// How long a code is shown before a new one takes its place.
    static let lifetime: TimeInterval = 5 * 60

    /// The QR code's text: the payload as JSON, keys sorted, slashes as they are.
    func text() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

/// The encodings the messages and the QR code use.
enum Encoding {
    static func hex(_ bytes: Data) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

    /// Base64url without padding, as the QR code and the pairing routes write a key.
    static func base64URL(_ bytes: Data) -> String {
        bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func fromBase64URL(_ text: String) -> Data? {
        var standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while standard.count % 4 != 0 { standard += "=" }
        return Data(base64Encoded: standard)
    }

    /// Base32 with RFC 4648's alphabet and no padding: the check code is its first 6 characters.
    static func base32(_ bytes: Data) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var out = ""
        var buffer = 0
        var bits = 0
        for byte in bytes {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                out.append(alphabet[(buffer >> (bits - 5)) & 31])
                bits -= 5
            }
            buffer &= (1 << bits) - 1
        }
        if bits > 0 { out.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return out
    }

    /// A key's fingerprint as KIFF shows it, from the hex of its hash: the first 8 bytes in
    /// four groups ("3f2a 91c0 7b1e 0d44").
    static func fingerprint(hashHex: String) -> String {
        let head = Array(hashHex.prefix(16))
        return stride(from: 0, to: head.count, by: 4).map { String(head[$0..<min($0 + 4, head.count)]) }.joined(separator: " ")
    }
}

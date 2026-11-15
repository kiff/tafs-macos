import CryptoKit
import Foundation

/// The hashes and signatures KIFF checks, made from the messages in `KIFFMessage`.
enum Signing {
    static func sha256Hex(_ bytes: Data) -> String { Encoding.hex(Data(SHA256.hash(data: bytes))) }

    /// A key's fingerprint as KIFF and the Devices list show it.
    static func fingerprint(_ der: Data) -> String { Encoding.fingerprint(hashHex: sha256Hex(der)) }

    /// The 6 characters this Mac and the phone both show before the phone approves a pairing,
    /// so a page showing its own QR code can't have its key enrolled in this Mac's place.
    static func checkCode(deviceKey: Data, approvalKey: Data?) -> String {
        let hash = Data(SHA256.hash(data: deviceKey + (approvalKey ?? Data())))
        return String(Encoding.base32(hash).prefix(6))
    }

    /// The `KIFF-Device-Signature` header for a request, signed over the exact bytes sent.
    /// `path` is the request's path and query as sent. With `window`, the signature is the
    /// kind KIFF takes inside that approval window. Signed now, its time is `SigningTime.next()`,
    /// as the iPad's `send` (KIFFClient.swift:1625): milliseconds, never the same twice in this
    /// app, since KIFF refuses a signature it has seen. `at` signs at a given second (tests).
    static func header(key: SigningKey, tenant: String, method: String, path: String, body: Data,
                       at date: Date? = nil, window: String? = nil) throws -> String {
        let signedAt = date.map(KIFFMessage.time) ?? SigningTime.next()
        let message = KIFFMessage.request(tenant: tenant, method: method, path: path, bodyHash: sha256Hex(body),
                                          signedAt: signedAt, window: window)
        let signature = try key.sign(Data(message.utf8)).base64EncodedString()
        return KIFFMessage.header(signedAt: signedAt, signature: signature, window: window)
    }

    /// The proof a pairing's claim carries: the device key's signature over the nonce and its own hash.
    static func claimProof(key: SigningKey, nonce: String) throws -> String {
        let message = KIFFMessage.pairClaim(nonce: nonce, keyHash: sha256Hex(key.publicKeyDER))
        return try key.sign(Data(message.utf8)).base64EncodedString()
    }

    /// Whether `signature` (base64 DER) is `publicKeyDER`'s over `message`.
    static func verifies(_ signature: String, over message: String, publicKeyDER: Data) -> Bool {
        guard let der = Data(base64Encoded: signature),
              let parsed = try? P256.Signing.ECDSASignature(derRepresentation: der),
              let key = try? P256.Signing.PublicKey(derRepresentation: publicKeyDER) else { return false }
        return key.isValidSignature(parsed, for: Data(message.utf8))
    }

    /// A pairing's nonce: base64url of 32 random bytes, from the system's secure generator.
    static func nonce() -> String {
        Encoding.base64URL(Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }))
    }
}

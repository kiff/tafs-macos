import CryptoKit
import Foundation

/// What Core's passkey code is given on a Mac: CryptoKit's SHA-256, and its check that a point is
/// on P-256 (a public key it can't make is refused).
enum PasskeyCrypto {
    static func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }

    /// Whether x ‖ y is a point on P-256: CryptoKit makes no key from one that isn't.
    static func isOnCurve(_ x: Data, _ y: Data) -> Bool {
        (try? P256.Signing.PublicKey(rawRepresentation: x + y)) != nil
    }
}

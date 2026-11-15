import CryptoKit
import Foundation

/// What Core's passkey code is given on a Mac: CryptoKit's SHA-256, and the check that a point is
/// on P-256.
enum PasskeyCrypto {
    static func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }

    /// Whether x ‖ y is a point on P-256, by the curve's equation (`P256Curve`). CryptoKit's key
    /// init isn't a check: on macOS it takes a point that isn't on the curve.
    static func isOnCurve(_ x: Data, _ y: Data) -> Bool { P256Curve.contains(x, y) }
}

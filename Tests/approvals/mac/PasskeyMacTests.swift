import CryptoKit
import Foundation

/// A security key's stand-in with a real P-256 key: it signs authData ‖ clientDataHash as an
/// authenticator does, so KIFF's signature check, as the public spec describes it, can be run here.
private final class P256Key: PasskeyAuthenticator {
    let key = P256.Signing.PrivateKey()

    func getAssertion(clientDataHash: Data, credentialID: Data, pin: SecurityKeyPIN?) async throws -> PasskeyAssertion {
        let authData = PasskeyCrypto.sha256(Data("kiff.dev".utf8)) + Data([0x05, 0, 0, 0, 1])
        return PasskeyAssertion(authenticatorData: authData, signatureDER: try key.signature(for: authData + clientDataHash).derRepresentation)
    }

    func makeCredential(clientDataHash: Data, userID: Data, userName: String, pin: SecurityKeyPIN?) async throws -> PasskeyMade {
        PasskeyMade(authenticatorData: Data(), attestationObject: Data())
    }
}

let approvalsPasskeyMacTests: [Test] = [
    Test("an approval's signature verifies as KIFF verifies it: over authData ‖ sha256(clientDataJSON), with the registered key", awaiting: {
        let device = P256Key()
        let credential = Data("this-computer-credential".utf8)
        let approver = PasskeyApprover(authenticator: device, credentialID: credential, sha256: PasskeyCrypto.sha256, enabled: true)
        let header = try await approver.approve(tenant: "t1", method: "POST", path: "/v1/cards", body: Data(#"{"card":"c1"}"#.utf8))
        guard let comma = header.range(of: ",a="), let a = Encoding.fromBase64URL(String(header[comma.upperBound...])),
              let fields = try JSONSerialization.jsonObject(with: a) as? [String: String],
              let client = fields["client_data_json"].flatMap(Encoding.fromBase64URL),
              let authData = fields["authenticator_data"].flatMap(Encoding.fromBase64URL),
              let signature = fields["signature"].flatMap(Encoding.fromBase64URL) else { throw Failure(description: "no a=") }
        let verified = try device.key.publicKey.isValidSignature(P256.Signing.ECDSASignature(derRepresentation: signature),
                                                                  for: authData + PasskeyCrypto.sha256(client))
        try expect(verified, "KIFF's signature check")
    }),
    Test("a new credential's key reads as the same SPKI CryptoKit writes, and a point off P-256 is refused") {
        let key = P256.Signing.PrivateKey().publicKey
        let raw = key.rawRepresentation
        let (x, y) = (raw.prefix(32), raw.suffix(32))
        try expectEqual(PasskeyRegistration.spki(x: Data(x), y: Data(y)), key.derRepresentation)
        try expect(PasskeyCrypto.isOnCurve(Data(x), Data(y)), "on the curve")
        var off = Data(y)
        off[31] ^= 0x01
        try expect(!PasskeyCrypto.isOnCurve(Data(x), off), "off the curve")
    },
]

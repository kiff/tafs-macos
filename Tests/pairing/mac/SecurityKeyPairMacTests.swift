import CryptoKit
import Foundation

/// A security key's stand-in with a real P-256 key: its new credential's authenticator data holds
/// that key, so what the QR names can be checked against CryptoKit's own.
private final class NewP256Key: PasskeyAuthenticator {
    let key = P256.Signing.PrivateKey()
    let id = Data("the-key-that-goes-with-this-mac".utf8)

    func getAssertion(clientDataHash: Data, credentialID: Data, pin: SecurityKeyPIN?) async throws -> PasskeyAssertion {
        throw Failure(description: "a pairing asks for no assertion")
    }

    func makeCredential(clientDataHash: Data, userID: Data, userName: String, pin: SecurityKeyPIN?) async throws -> PasskeyMade {
        pin?.release()
        let raw = key.publicKey.rawRepresentation
        var cose = Data([0xa5, 0x01, 0x02, 0x03, 0x26, 0x20, 0x01, 0x21, 0x58, 32])
        cose += raw.prefix(32)
        cose += Data([0x22, 0x58, 32])
        cose += raw.suffix(32)
        let authData = PasskeyCrypto.sha256(Data("kiff.dev".utf8)) + Data([0x45, 0, 0, 0, 0]) + Data(repeating: 0, count: 16)
            + Data([0, UInt8(id.count)]) + id + cose
        return PasskeyMade(authenticatorData: authData, attestationObject: Data())
    }
}

let pairingSecurityKeyMacTests: [Test] = [
    Test("a security key's credential goes into the QR as CryptoKit's SPKI, and the check code covers it", awaiting: {
        let device = P256.Signing.PrivateKey().publicKey.derRepresentation
        let key = NewP256Key()
        var typed = Array("2468".utf8)
        let made = try await SecurityKeyPairing.make(challenge: "CH", deviceKeyDER: device, name: "A Mac", authenticator: key,
                                                     pin: try SecurityKeyPIN(utf8: &typed), sha256: PasskeyCrypto.sha256,
                                                     isOnCurve: PasskeyCrypto.isOnCurve, enabled: true)
        try expectEqual(made.passkey.publicKeyDER, key.key.publicKey.derRepresentation)
        try expectEqual(made.passkey.credentialID, key.id)
        let payload = PairingPayload(deviceKey: device, keyStore: "enclave", approvalKey: nil, name: "A Mac", nonce: "N", exp: "E",
                                     credential: made.credential)
        try expectEqual(Signing.checkCode(deviceKey: device, approvalKey: payload.checkedKeyDER),
                        Signing.checkCode(deviceKey: device, approvalKey: key.key.publicKey.derRepresentation))
    }),
    Test("signing this Mac out forgets the security key that goes with it", awaiting: { @MainActor in
        let store = MemoryStore()
        let model = SignInModel(client: KIFFClient(transport: CannedTransport([])), key: try DeviceKey.load(from: store, enclave: false),
                                approval: .passkey, sessions: SessionStore(store: store), deviceName: "A Mac", sleep: { _ in }, open: { _ in })
        try SecurityKeyStore(store: store).save(Data("the-key".utf8))
        try expectEqual(SecurityKeyStore(store: store).load(), Data("the-key".utf8))
        model.signedOut()
        try expectEqual(SecurityKeyStore(store: store).load(), nil)
    }),
]

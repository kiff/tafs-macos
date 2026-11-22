import AppKit
import Combine
import CryptoKit
import Foundation
import SwiftUI

/// The pairing screen with this Mac's security key: the PIN sheet asks, the QR names the key's
/// credential, the claim proves it, and its id is kept only once the pairing is claimed.

private let paired = #"{"access_token":"tok","token_type":"Bearer","expires_in":60,"tenant":"t1","subject":"u1","device_id":"dev_1","approval_mode":"passkey"}"#
/// A claim KIFF answers as view: no security key is kept, whatever the QR named.
private let pairedView = #"{"access_token":"tok","token_type":"Bearer","expires_in":60,"tenant":"t1","subject":"u1","device_id":"dev_1","approval_mode":"view"}"#
private let pending = (400, #"{"error":"authorization_pending"}"#)

/// A device key whose private half is in hardware, as a Secure Enclave Mac's: only such a Mac's
/// pairing names a security key (a software device key pairs as view, with none).
private struct HardwareKey: SigningKey {
    let key = P256.Signing.PrivateKey()
    var publicKeyDER: Data { key.publicKey.derRepresentation }
    var keyStore: String { "enclave" }
    func sign(_ message: Data) throws -> Data { try key.signature(for: message).derRepresentation }
}

/// The security key's stand-in, with a real P-256 key in its new credential.
private final class PairingKey: PasskeyAuthenticator {
    let key = P256.Signing.PrivateKey()
    let id = Data("the-key-that-goes-with-this-mac".utf8)
    var asked: [Data] = []

    func getAssertion(clientDataHash: Data, credentialID: Data, pin: SecurityKeyPIN?) async throws -> PasskeyAssertion {
        throw Failure(description: "a pairing asks for no assertion")
    }

    func makeCredential(clientDataHash: Data, userID: Data, userName: String, pin: SecurityKeyPIN?) async throws -> PasskeyMade {
        asked.append(clientDataHash)
        pin?.release()
        let raw = key.publicKey.rawRepresentation
        var cose = Data([0xa5, 0x01, 0x02, 0x03, 0x26, 0x20, 0x01, 0x21, 0x58, 32])
        cose += raw.prefix(32)
        cose += Data([0x22, 0x58, 32])
        cose += raw.suffix(32)
        let authData = PasskeyCrypto.sha256(Data("kiff.dev".utf8)) + Data([0x45, 0, 0, 0, 0]) + Data(repeating: 0, count: 16)
            + Data([0, UInt8(id.count)]) + id + cose
        // The key's own attestation, which this app never sends.
        return PasskeyMade(authenticatorData: authData, attestationObject: Data([0xa1]))
    }
}

/// A key that answers only with `failure`: none plugged in, then a wrong PIN.
private final class FailingKey: PasskeyAuthenticator {
    var failure: Error = SecurityKeyFailure.noKey
    func getAssertion(clientDataHash: Data, credentialID: Data, pin: SecurityKeyPIN?) async throws -> PasskeyAssertion { throw failure }
    func makeCredential(clientDataHash: Data, userID: Data, userName: String, pin: SecurityKeyPIN?) async throws -> PasskeyMade {
        pin?.release()
        throw failure
    }
}

/// A store that refuses the security key's id once told to (after the pairing's writable check),
/// to see the screen and the store stay as one.
private final class RefusingKeyStore: SecretStore {
    struct Refused: Error {}
    let inner = MemoryStore()
    var refuseKey = false
    func load(_ account: String) -> Data? { inner.load(account) }
    func save(_ secret: Data, for account: String) throws {
        if refuseKey && account == SecurityKeyStore.account { throw Refused() }
        inner.save(secret, for: account)
    }
    func delete(_ account: String) { inner.delete(account) }
}

private let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])

@MainActor
private func model(_ answers: [(Int, String)], store: MemoryStore, key: PairingKey, enabled: Bool = true) -> (SignInModel, CannedTransport, HardwareKey) {
    let transport = CannedTransport(answers)
    let device = HardwareKey()
    let model = SignInModel(client: KIFFClient(transport: transport), key: device, approval: .passkey, sessions: SessionStore(store: store),
                            deviceName: "A Mac", sleep: { _ in }, open: { _ in }, now: { Date(timeIntervalSince1970: 1_794_679_200) },
                            securityKey: PairingSecurityKey(words: words, authenticator: key, readTries: { 8 }, enabled: enabled, proving: true), onboarding: false)
    return (model, transport, device)
}

/// The PIN sheet once the pairing has put it up.
@MainActor
private func sheet(_ model: SignInModel) async throws -> PINSheetModel {
    for _ in 0..<300 {
        if let sheet = model.pinSheet { return sheet }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw Failure(description: "no PIN sheet")
}

private func claim(_ transport: CannedTransport) throws -> [String: Any] {
    guard let request = transport.sent.last(where: { $0.path == "/v1/pair/claim" }),
          let body = try JSONSerialization.jsonObject(with: request.body) as? [String: Any] else { throw Failure(description: "no claim") }
    return body
}

let pairingKeyScreenTests: [Test] = [
    Test("pairing with the security key: the PIN sheet asks, the QR names its credential, the claim proves it, and it's kept once claimed", awaiting: { @MainActor in
        let store = MemoryStore()
        let key = PairingKey()
        let (model, transport, device) = model([pending, (200, paired)], store: store, key: key)
        var shown: SignInModel.Code?
        var keptWhileWaiting: Data??
        let watching = model.$step.sink {
            if case .pairing(let code) = $0 { shown = code; keptWhileWaiting = SecurityKeyStore(store: store).load() }
        }
        let pairing = Task { await model.pair() }
        let pin = try await sheet(model)
        // The pairing's sheet adds the key: its own title, lead, action and close.
        try expectEqual(pin.purpose, .addKey)
        let field = NSSecureTextField()
        pin.reader.field = field
        field.stringValue = "2468"
        await pin.approve()
        await pairing.value
        watching.cancel()
        try expectEqual(key.asked.count, 1)
        try expectEqual(model.pinSheet == nil, true)
        guard let shown else { throw Failure(description: "no code was shown") }
        let payload = try JSONDecoder().decode(PairingPayload.self, from: Data(shown.text.utf8))
        try expectEqual(payload.kind, .passkey)
        try expectEqual(payload.credential, PairingPayload.Credential(id: Encoding.base64URL(key.id),
                                                                      publicKey: Encoding.base64URL(key.key.publicKey.derRepresentation)))
        try expectEqual(shown.check, Signing.checkCode(deviceKey: device.publicKeyDER, approvalKey: key.key.publicKey.derRepresentation))
        // Not kept while the phone hasn't approved.
        try expectEqual(keptWhileWaiting, .some(nil))
        let sent = try claim(transport)
        guard let proof = sent["credential_proof"] as? [String: String],
              let clientData = proof["client_data_json"].flatMap(Encoding.fromBase64URL),
              let attestation = proof["attestation_object"].flatMap(Encoding.fromBase64URL) else { throw Failure(description: "no credential_proof") }
        let challenge = PasskeyRegistration.pairingChallenge(nonce: payload.nonce, deviceKeyDER: device.publicKeyDER, sha256: PasskeyCrypto.sha256)
        try expectEqual(clientData, SecurityKeyPairing.clientDataJSON(challenge: challenge))
        try expectEqual(key.asked[0], PasskeyCrypto.sha256(clientData))
        try expect(attestation.range(of: Data("none".utf8)) != nil, "fmt none")
        try expectEqual(attestation.first, 0xa3)
        try expectEqual(model.session?.deviceID, "dev_1")
        try expectEqual(SecurityKeyStore(store: store).load(), key.id)
        model.signedOut()
        try expectEqual(SecurityKeyStore(store: store).load(), nil)
    }),
    Test("KIFF answers the claim as view: the session is taken, but no security key is kept, whatever the QR named (kiff/cloud#96)", awaiting: { @MainActor in
        let store = MemoryStore()
        let key = PairingKey()
        let (model, _, _) = model([(200, pairedView)], store: store, key: key)
        let pairing = Task { await model.pair() }
        let pin = try await sheet(model)
        let field = NSSecureTextField()
        pin.reader.field = field
        field.stringValue = "2468"
        await pin.approve()
        await pairing.value
        try expectEqual(key.asked.count, 1)
        try expectEqual(model.session?.approvalMode, "view")
        try expectEqual(SecurityKeyStore(store: store).load(), nil)
    }),
    Test("a wrong PIN or no key says why in the sheet, which stays open; Pair without a key (as closing it) pairs without the key and keeps nothing", awaiting: { @MainActor in
        let store = MemoryStore()
        try SecurityKeyStore(store: store).save(Data("an-earlier-key".utf8))
        let missing = FailingKey()
        let transport = CannedTransport([(200, paired)])
        let model = SignInModel(client: KIFFClient(transport: transport), key: HardwareKey(), approval: .passkey, sessions: SessionStore(store: store),
                                deviceName: "A Mac", sleep: { _ in }, open: { _ in },
                                securityKey: PairingSecurityKey(words: words, authenticator: missing, readTries: { 8 }, enabled: true, proving: true), onboarding: false)
        let pairing = Task { await model.pair() }
        let pin = try await sheet(model)
        let field = NSSecureTextField()
        pin.reader.field = field
        field.stringValue = "2468"
        await pin.approve()
        try expectEqual(pin.message, words("approval.security_key.no_key"))
        missing.failure = SecurityKeyFailure.wrongPIN(triesLeft: 2)
        field.stringValue = "1111"
        await pin.approve()
        try expectEqual(pin.message, "Wrong PIN. 2 tries left before the key locks.")
        try expectEqual(model.pinSheet === pin, true)
        pin.cancel()
        await pairing.value
        let sent = try claim(transport)
        try expect(sent["credential_proof"] == nil, "no proof without a credential")
        try expectEqual(model.session?.deviceID, "dev_1")
        // The earlier key went with another device key: a pairing that names none forgets it.
        try expectEqual(SecurityKeyStore(store: store).load(), nil)
    }),
    Test("passkey approvals off: no PIN sheet, no credential in the QR, as today", awaiting: { @MainActor in
        let store = MemoryStore()
        let key = PairingKey()
        let (model, transport, _) = model([(200, paired)], store: store, key: key, enabled: false)
        var sheets = 0
        let watching = model.$pinSheet.sink { if $0 != nil { sheets += 1 } }
        var shown: SignInModel.Code?
        let steps = model.$step.sink { if case .pairing(let code) = $0 { shown = code } }
        await model.pair()
        watching.cancel(); steps.cancel()
        try expectEqual(sheets, 0)
        try expectEqual(key.asked.count, 0)
        guard let shown else { throw Failure(description: "no code was shown") }
        let payload = try JSONDecoder().decode(PairingPayload.self, from: Data(shown.text.utf8))
        try expectEqual(payload.credential, nil)
        try expect(try claim(transport)["credential_proof"] == nil, "no proof")
        try expectEqual(SecurityKeyStore(store: store).load(), nil)
    }),
    Test("a pairing cancelled while the PIN sheet is up closes it, and nothing is asked or claimed", awaiting: { @MainActor in
        let store = MemoryStore()
        let key = PairingKey()
        let (model, transport, _) = model([(200, paired)], store: store, key: key)
        let pairing = Task { await model.pair() }
        _ = try await sheet(model)
        model.cancel()
        await pairing.value
        try expectEqual(model.pinSheet == nil, true)
        try expectEqual(key.asked.count, 0)
        try expectEqual(transport.sent.count, 0)
        try expectEqual(model.step, .welcome)
        try expectEqual(model.session, nil)
    }),
    Test("a second ask closes the PIN sheet already up: both asks resume, the first as cancelled", awaiting: { @MainActor in
        let key = PairingKey()
        let (model, _, _) = model([], store: MemoryStore(), key: key)
        let security = PairingSecurityKey(words: words, authenticator: key, readTries: { 8 }, enabled: true, proving: true)
        let first = Task { try await model.askKey(security) { _ in throw Failure(description: "the first sheet is never answered") } }
        let firstSheet = try await sheet(model)
        let second = Task { try await model.askKey(security) { _ in throw Failure(description: "the second sheet is never answered") } }
        for _ in 0..<300 where model.pinSheet == nil || model.pinSheet === firstSheet {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        do { _ = try await first.value; throw Failure(description: "the first ask answered") } catch is CancellationError {}
        try expect(model.pinSheet != nil && model.pinSheet !== firstSheet, "the second sheet is up")
        model.pinSheet?.cancel()
        do { _ = try await second.value; throw Failure(description: "the second ask answered") } catch is CancellationError {}
        try expectEqual(model.pinSheet == nil, true)
        try expectEqual(key.asked.count, 0)
    }),
    Test("a store that refuses the key's id after the claim: the new session stands on screen and in the store, with no key kept", awaiting: { @MainActor in
        let store = RefusingKeyStore()
        try SecurityKeyStore(store: store).save(Data("an-earlier-key".utf8))
        let key = PairingKey()
        let transport = CannedTransport([(200, paired)])
        let model = SignInModel(client: KIFFClient(transport: transport), key: HardwareKey(), approval: .passkey, sessions: SessionStore(store: store),
                                deviceName: "A Mac", sleep: { _ in }, open: { _ in },
                                securityKey: PairingSecurityKey(words: words, authenticator: key, readTries: { 8 }, enabled: true, proving: true), onboarding: false)
        let pairing = Task { await model.pair() }
        let pin = try await sheet(model)
        store.refuseKey = true
        let field = NSSecureTextField()
        pin.reader.field = field
        field.stringValue = "2468"
        await pin.approve()
        await pairing.value
        try expectEqual(model.step, .welcome)
        try expectEqual(model.session?.deviceID, "dev_1")
        try expectEqual(SessionStore(store: store).load(), model.session)
        try expectEqual(SecurityKeyStore(store: store).load(), nil)
    }),
    Test("the screenshots: the PIN sheet over the pairing, and the QR naming the key", awaiting: { @MainActor in
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr"] {
            let local = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: [language])
            let sheet = PINSheetModel(words: local, purpose: .addKey, attempt: { _ in }, readTries: { 8 }, done: { _ in })
            await sheet.appeared()
            let view = PINSheet(model: sheet).environment(\.words, local)
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 440, height: 300)), let png = Snapshot.png(bitmap) else {
                throw Failure(description: "no PNG for the PIN sheet in \(language)")
            }
            try png.write(to: folder.appendingPathComponent("pairing-pin-sheet-\(language).png"))
        }
        let device = HardwareKey(), key = P256.Signing.PrivateKey()
        let payload = PairingPayload(deviceKey: device.publicKeyDER, keyStore: "enclave", approvalKey: nil, name: "A Mac", nonce: String(repeating: "n", count: 43),
                                     exp: "2026-11-16T03:05:00Z",
                                     credential: .init(id: Encoding.base64URL(Data("the-key".utf8)), publicKey: Encoding.base64URL(key.publicKey.derRepresentation)))
        let store = MemoryStore()
        let model = SignInModel(client: KIFFClient(transport: CannedTransport([])), key: device, approval: .passkey,
                                sessions: SessionStore(store: store), deviceName: "A Mac", open: { _ in }, onboarding: false)
        model.show(.pairing(.init(text: try payload.text(), check: Signing.checkCode(deviceKey: device.publicKeyDER, approvalKey: payload.checkedKeyDER))))
        let view = SignInView(model: model).environment(\.words, words)
        guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 1280, height: 800)), let png = Snapshot.png(bitmap) else {
            throw Failure(description: "no PNG for the pairing")
        }
        try png.write(to: folder.appendingPathComponent("pairing-key-en.png"))
    }),
]

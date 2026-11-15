import Combine
import Foundation
import Security

private let firstSession = #"{"access_token":"tok","token_type":"Bearer","expires_in":60,"tenant":"t1","subject":"u1","device_id":"dev_1"}"#
private let secondSession = #"{"access_token":"tok2","token_type":"Bearer","expires_in":60,"tenant":"t1","subject":"u1","device_id":"dev_2"}"#

/// A store whose Keychain refuses to write over one item, as it does an item an earlier
/// unsigned build kept.
private final class RefusingStore: SecretStore {
    let kept = MemoryStore()
    let refused: String
    init(refusing account: String) { refused = account }
    func load(_ account: String) -> Data? { kept.load(account) }
    func save(_ secret: Data, for account: String) throws {
        if account == refused { throw KeychainStore.Refused(status: errSecDuplicateItem) }
        kept.save(secret, for: account)
    }
    func delete(_ account: String) { kept.delete(account) }
}

@MainActor
private func pairing(_ store: SecretStore, key: SigningKey, answers: [(Int, String)]) -> (SignInModel, CannedTransport) {
    let transport = CannedTransport(answers)
    let model = SignInModel(client: KIFFClient(transport: transport), key: key, approval: .passkey, sessions: SessionStore(store: store),
                            deviceName: "A Mac", sleep: { _ in }, open: { _ in }, enclave: false)
    return (model, transport)
}

let pairingKeychainTests: [Test] = [
    Test("the Keychain writes over an item that is there already, even one kept another way") {
        let store = KeychainStore(service: "bot.tafs.macos.tests")
        let account = "test-\(UUID().uuidString)"
        defer { store.delete(account) }
        // An item kept with none of this build's attributes, as an earlier build could have.
        let earlier: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: store.service,
                                        kSecAttrAccount: account, kSecValueData: Data([1])]
        try expectEqual(SecItemAdd(earlier as CFDictionary, nil), errSecSuccess)
        try store.save(Data([2]), for: account)
        try expectEqual(store.load(account), Data([2]))
        // Where this Keychain reports how an item may be read, the replaced one is at full strength.
        let asked: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: store.service, kSecAttrAccount: account,
                                      kSecReturnAttributes: true, kSecMatchLimit: kSecMatchLimitOne]
        var found: CFTypeRef?
        try expectEqual(SecItemCopyMatching(asked as CFDictionary, &found), errSecSuccess)
        if let accessible = (found as? [String: Any])?[kSecAttrAccessible as String] as? String {
            try expectEqual(accessible, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        }
    },
    Test("a pair, then a re-pair at the next launch, keep their sessions and keys in the Keychain", awaiting: { @MainActor in
        let store = KeychainStore(service: "bot.tafs.macos.tests.\(UUID().uuidString)")
        defer { for account in [DeviceKey.account, DeviceKey.nextAccount, SessionStore.account] { store.delete(account) } }
        let key = try DeviceKey.load(from: store, enclave: false)
        let (first, _) = pairing(store, key: key, answers: [(200, firstSession)])
        await first.pair()
        try expectEqual(first.step, .welcome)
        try expectEqual(SessionStore(store: store).load()?.accessToken, "tok")

        let (again, _) = pairing(store, key: try DeviceKey.load(from: store, enclave: false), answers: [(200, secondSession)])
        try expectEqual(again.session?.accessToken, "tok")
        await again.pair()
        try expectEqual(again.step, .welcome)
        try expectEqual(again.session?.accessToken, "tok2")
        try expectEqual(SessionStore(store: store).load()?.accessToken, "tok2")
        try expect(again.key.publicKeyDER != key.publicKeyDER, "the re-pair has a new device key")
        try expectEqual(try DeviceKey.load(from: store, enclave: false).publicKeyDER, again.key.publicKeyDER)
        try expectEqual(store.load(DeviceKey.nextAccount), nil)
    }),
    Test("a Keychain that won't be written stops the pairing before its code is shown, in a number and no type", awaiting: { @MainActor in
        let viewOnly = Session(accessToken: "old", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_view")
        for account in [SessionStore.account, DeviceKey.account] {
            for signedIn in [false, true] {
                let store = RefusingStore(refusing: account)
                let key = try DeviceKey.load(from: store.kept, enclave: false)
                if signedIn { try SessionStore(store: store.kept).save(viewOnly) }
                let (model, transport) = pairing(store, key: key, answers: [(200, firstSession)])
                var shown = false
                let watching = model.$step.sink { if case .pairing = $0 { shown = true } }
                await model.pair()
                watching.cancel()
                try expect(!shown, "no code is shown for \(account)")
                try expectEqual(transport.sent.count, 0)
                try expectEqual(model.step, .failed(why: String(errSecDuplicateItem), pairing: true))
                try expectEqual(model.session, signedIn ? viewOnly : nil)
                try expectEqual(model.key.publicKeyDER, key.publicKeyDER)
            }
        }
    }),
]

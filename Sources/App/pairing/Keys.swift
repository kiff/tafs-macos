import CryptoKit
import Foundation
import Security

/// A P-256 key of this Mac. Its private half never leaves where it is kept.
protocol SigningKey {
    /// The public half, as SPKI DER.
    var publicKeyDER: Data { get }
    /// Where the private half is: KIFF refuses every approval from a `software` key.
    var keyStore: String { get }
    /// An ECDSA signature over the message's SHA-256, as ASN.1 DER.
    func sign(_ message: Data) throws -> Data
}

/// Where a key's handle or bytes are kept between launches.
protocol SecretStore {
    func load(_ account: String) -> Data?
    func save(_ secret: Data, for account: String) throws
    func delete(_ account: String)
}

/// The **device key**: it signs this Mac's ordinary requests with no prompt, and never an
/// approval. On a Mac with a Secure Enclave the key is made and kept there, and the store
/// holds only its handle. On a Mac without one it is a key in the login Keychain, which KIFF
/// knows as `software` and refuses on every route that grants authority.
enum DeviceKey {
    static let account = "tafs.device-key"

    /// Where a new device key waits while a signed-in Mac pairs: it becomes the device key
    /// only once its pairing is claimed.
    static let nextAccount = "tafs.device-key.next"

    /// A new device key for a pairing, kept apart from the one in use.
    static func makeNext(in store: SecretStore, enclave: Bool = SecureEnclave.isAvailable) throws -> SigningKey {
        store.delete(nextAccount)
        return try load(from: store, enclave: enclave, account: nextAccount)
    }

    /// The pairing was claimed: the new key takes the device key's place, and the old one is gone.
    static func promoteNext(in store: SecretStore) throws {
        guard let next = store.load(nextAccount) else { return }
        try store.save(next, for: account)
        store.delete(nextAccount)
    }

    /// The pairing didn't happen: the new key is forgotten, and the one in use stays.
    static func discardNext(in store: SecretStore) { store.delete(nextAccount) }

    static func load(from store: SecretStore, enclave: Bool = SecureEnclave.isAvailable) throws -> SigningKey {
        try load(from: store, enclave: enclave, account: account)
    }

    private static func load(from store: SecretStore, enclave: Bool, account: String) throws -> SigningKey {
        if enclave {
            if let handle = store.load(account), let key = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: handle) {
                return EnclaveKey(key: key)
            }
            let key = try SecureEnclave.P256.Signing.PrivateKey()
            try store.save(key.dataRepresentation, for: account)
            return EnclaveKey(key: key)
        }
        if let bytes = store.load(account), let key = try? P256.Signing.PrivateKey(rawRepresentation: bytes) {
            return SoftwareKey(key: key)
        }
        let key = P256.Signing.PrivateKey()
        try store.save(key.rawRepresentation, for: account)
        return SoftwareKey(key: key)
    }
}

struct EnclaveKey: SigningKey {
    let key: SecureEnclave.P256.Signing.PrivateKey
    var publicKeyDER: Data { key.publicKey.derRepresentation }
    var keyStore: String { "enclave" }
    func sign(_ message: Data) throws -> Data { try key.signature(for: message).derRepresentation }
}

struct SoftwareKey: SigningKey {
    let key: P256.Signing.PrivateKey
    var publicKeyDER: Data { key.publicKey.derRepresentation }
    var keyStore: String { "software" }
    func sign(_ message: Data) throws -> Data { try key.signature(for: message).derRepresentation }
}

/// The login Keychain, for this Mac only: an item is never synced, and is readable only
/// while the Mac is unlocked.
struct KeychainStore: SecretStore {
    var service = "bot.tafs.macos"

    /// The Keychain said no. It carries the Keychain's status number only, never the item.
    struct Refused: Error, Equatable { let status: OSStatus }

    private func query(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    func load(_ account: String) -> Data? {
        var found: CFTypeRef?
        var q = query(account)
        q[kSecReturnData] = true
        q[kSecMatchLimit] = kSecMatchLimitOne
        guard SecItemCopyMatching(q as CFDictionary, &found) == errSecSuccess else { return nil }
        return found as? Data
    }

    /// Keeps the secret, replacing this app's own item when there is one: a re-pair writes
    /// over the session and key an earlier pairing kept.
    func save(_ secret: Data, for account: String) throws {
        let added = add(secret, for: account)
        if added == errSecSuccess { return }
        guard added == errSecDuplicateItem else { throw Refused(status: added) }
        // The update keeps the item at the strength an add gives it, whatever kept it first.
        let attributes: [CFString: Any] = [kSecValueData: secret, kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let updated = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        // An item this build may not change, such as one an earlier unsigned build kept, is
        // made anew if it may at least be deleted. A refused delete is the number that ended it.
        let deleted = SecItemDelete(query(account) as CFDictionary)
        guard deleted == errSecSuccess || deleted == errSecItemNotFound else { throw Refused(status: deleted) }
        let again = add(secret, for: account)
        guard again == errSecSuccess else { throw Refused(status: again) }
    }

    private func add(_ secret: Data, for account: String) -> OSStatus {
        var q = query(account)
        q[kSecValueData] = secret
        q[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        q[kSecAttrSynchronizable] = false
        return SecItemAdd(q as CFDictionary, nil)
    }

    func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

extension SecretStore {
    /// Fails now if any of these can't be written over. A pairing checks before it shows its
    /// code: a refusal found after the phone approved would leave a device at KIFF that this
    /// Mac can't keep.
    func checkWritable(_ accounts: [String]) throws {
        for account in accounts {
            if let kept = load(account) {
                try save(kept, for: account)
            } else {
                try save(Data(), for: account)
                delete(account)
            }
        }
    }
}

/// A store that forgets when the app quits: for tests.
final class MemoryStore: SecretStore {
    private var secrets: [String: Data] = [:]
    func load(_ account: String) -> Data? { secrets[account] }
    func save(_ secret: Data, for account: String) { secrets[account] = secret }
    func delete(_ account: String) { secrets[account] = nil }
}

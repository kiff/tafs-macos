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

    static func load(from store: SecretStore, enclave: Bool = SecureEnclave.isAvailable) throws -> SigningKey {
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

    struct Refused: Error { let status: OSStatus }

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

    func save(_ secret: Data, for account: String) throws {
        delete(account)
        var q = query(account)
        q[kSecValueData] = secret
        q[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        q[kSecAttrSynchronizable] = false
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw Refused(status: status) }
    }

    func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

/// A store that forgets when the app quits: for tests.
final class MemoryStore: SecretStore {
    private var secrets: [String: Data] = [:]
    func load(_ account: String) -> Data? { secrets[account] }
    func save(_ secret: Data, for account: String) { secrets[account] = secret }
    func delete(_ account: String) { secrets[account] = nil }
}

import Foundation

/// The security key that goes with this Mac: only its credential id, kept in the Keychain beside
/// the session and nowhere else. The key's public half is KIFF's, and its PIN is never kept. It's
/// saved once a pairing that named it is claimed (the pairing screen, still to come), and forgotten when this Mac signs out,
/// as signing a computer out in Devices removes its key (kiff/tafs `docs/computer-passkeys.md`).
struct SecurityKeyStore {
    static let account = "tafs.security-key"
    let store: SecretStore

    func load() -> Data? { store.load(Self.account) }

    func save(_ credentialID: Data) throws { try store.save(credentialID, for: Self.account) }

    func forget() { store.delete(Self.account) }
}

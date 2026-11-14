import Foundation

/// This Mac's session, kept in the Keychain between launches and nowhere else.
struct SessionStore {
    static let account = "tafs.session"
    let store: SecretStore

    func load() -> Session? {
        store.load(Self.account).flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
    }

    func save(_ session: Session) throws {
        try store.save(try JSONEncoder().encode(session), for: Self.account)
    }

    /// Forgets the session: at sign-out, and when KIFF says it is over.
    func forget() { store.delete(Self.account) }
}

extension AccountClient {
    /// The client for a signed-in Mac: over the network, signing with its device key.
    init(session: Session, key: SigningKey, language: String, transport: Transport = NetworkTransport()) {
        self.init(transport: transport, session: session, language: language) { request in
            try Signing.header(key: key, tenant: session.tenant, method: request.method, path: request.path, body: request.body)
        }
    }
}

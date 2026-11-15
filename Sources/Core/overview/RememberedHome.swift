import Foundation

/// The tafs last shown for this account, so the next launch shows them in its first frame, as
/// the iPad's remembered list (`RememberedList`, `rememberList`, `showRememberedList`,
/// AppModel.swift:2021-2053): kept with its account, and shown only for that account. It
/// keeps Home's answer as tafs cloud sent it (the tafs' names, states, colours, Cards and
/// lines); never a chat, a key or a session. It is replaced by each list read, and forgotten at
/// sign-out (AppModel.swift:868, 1322).
enum RememberedHome {
    static let key = "tafs.list"

    private struct Kept: Codable {
        let tenant: String
        let home: Data
    }

    /// Keeps Home's answer for this account.
    static func remember(_ home: Data, tenant: String, in defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(Kept(tenant: tenant, home: home)) else { return }
        defaults.set(data, forKey: key)
    }

    /// The list last read for this account; nil for another account's, or one that doesn't read.
    static func shown(tenant: String, in defaults: UserDefaults) -> Home.Page? {
        guard let data = defaults.data(forKey: key),
              let kept = try? JSONDecoder().decode(Kept.self, from: data),
              kept.tenant == tenant else { return nil }
        return try? AccountClient.decoder.decode(Home.Page.self, from: kept.home)
    }

    /// An earlier session's tafs never show in this one.
    static func forget(in defaults: UserDefaults) {
        defaults.removeObject(forKey: key)
    }
}

extension CloudClient {
    /// Home, with its answer as sent, to keep for the next launch's first frame.
    func homeRead() async throws -> (page: Home.Page, body: Data) {
        let request = HTTPRequest(method: "GET", path: "/v1/home", headers: [
            "Authorization": "Bearer \(session.accessToken)", "Accept": "application/json",
            "Accept-Language": language, "User-Agent": "tafs-macos",
        ])
        let (status, body) = try await transport.send(request)
        guard (200..<300).contains(status) else { throw KIFFError(status: status, body: body) }
        guard let page = try? AccountClient.decoder.decode(Home.Page.self, from: body) else { throw KIFFError.unreadable }
        return (page, body)
    }
}

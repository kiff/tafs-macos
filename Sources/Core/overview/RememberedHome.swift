import Foundation

/// The tafs last shown for this account, so the next launch shows them in its first frame, as
/// the iPad's remembered list (`RememberedList`, `rememberList`, `showRememberedList`,
/// AppModel.swift:2022-2054): kept with its account, and shown only for that account. It keeps
/// the tafs alone, as tafs cloud sent them in Home's answer (their names, states, colours, Cards
/// and lines): never the rest of Home, a chat, a key or a session. It is replaced by each list
/// read, and forgotten with each session kept or ended (AppModel.swift:868, 1323).
enum RememberedHome {
    static let key = "tafs.list"

    private struct Kept: Codable {
        let tenant: String
        let home: Data
    }

    /// Keeps the tafs in Home's answer for this account; an answer without them keeps nothing.
    static func remember(_ home: Data, tenant: String, in defaults: UserDefaults) {
        guard let root = try? JSONSerialization.jsonObject(with: home) as? [String: Any],
              let tafs = root["tafs"] as? [Any],
              let only = try? JSONSerialization.data(withJSONObject: ["tafs": tafs]),
              let data = try? JSONEncoder().encode(Kept(tenant: tenant, home: only)) else { return }
        defaults.set(data, forKey: key)
    }

    /// The tafs last read for this account, alone on their page; nil for another account's, or
    /// a list that doesn't read.
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
        let body = try await read("/v1/home")
        return (try decoded(body), body)
    }
}

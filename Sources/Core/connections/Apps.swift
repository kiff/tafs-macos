import Foundation

/// The catalog of apps a taf can use (`GET /v1/connect/apps`), each row with what both
/// phones draw it from. tafs cloud words each row's second line; the app writes none.
enum Apps {
    struct App: Decodable, Identifiable, Equatable {
        /// The catalog entry: what tells one row from another.
        let entry: String
        /// What the row reads as, the app's name for people ("Qonto", "Gmail").
        let name: String
        /// What this entry of the app is, under its name; nil for most.
        let subtitle: String?
        /// `available`, `connected`, `needs_reconnect` or `needs_setup`.
        let state: String
        /// The row's second line in the person's language: how it connects, its status, and
        /// which tafs use it ("Sign in · Connected · Used by Refunds").
        let line: String?
        /// For `needs_setup`: the line shown in place of Connect.
        let words: String?
        /// For the account's own connections: "Company" or "Yours", as sent.
        let whose: String?

        var id: String { entry }

        enum CodingKeys: String, CodingKey { case entry, name, title, subtitle, state, line, words, whose }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            entry = try c.decode(String.self, forKey: .entry)
            state = try c.decode(String.self, forKey: .state)
            func text(_ key: CodingKeys) -> String? {
                guard let value = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil,
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return value
            }
            // An older tafs cloud sends only the title: a row always has something to read as.
            guard let shown = text(.name) ?? text(.title) else {
                throw DecodingError.dataCorruptedError(forKey: .name, in: c, debugDescription: "a row with no name")
            }
            name = shown
            subtitle = text(.subtitle)
            line = text(.line)
            words = text(.words)
            whose = text(.whose)
        }

        /// One of the account's own connections: connected, or to sign in again.
        var isYours: Bool { state == "connected" || state == "needs_reconnect" }
        /// Its sign-in is no longer taken: it needs the person.
        var needsReconnect: Bool { state == "needs_reconnect" }
    }

    struct Page: Decodable, Equatable {
        let apps: [App]
        let nextCursor: String?
        /// The catalog read stopped with pages left: an app that isn't listed isn't absent.
        let partial: Bool

        enum CodingKeys: String, CodingKey { case apps, nextCursor = "next_cursor", partial }
        private struct Lenient: Decodable {
            let app: App?
            init(from decoder: Decoder) throws { app = try? App(from: decoder) }
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // The list must be there; a row this app can't read is left out, never the page.
            apps = try c.decode([Lenient].self, forKey: .apps).compactMap(\.app)
            nextCursor = (try? c.decodeIfPresent(String.self, forKey: .nextCursor)) ?? nil
            partial = ((try? c.decodeIfPresent(Bool.self, forKey: .partial)) ?? nil) ?? false
        }
    }

    /// The longest search sent.
    static let longestSearch = 100
}

extension CloudClient {
    /// One page of the catalog, searched by `q`; `cursor` continues the same search.
    func apps(_ q: String = "", cursor: String? = nil) async throws -> Apps.Page {
        var query = ["q=\(Self.query(String(q.prefix(Apps.longestSearch))))"]
        if let cursor { query.append("cursor=\(Self.query(cursor))") }
        return try await get("/v1/connect/apps?" + query.joined(separator: "&"))
    }
}

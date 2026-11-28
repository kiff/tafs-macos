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
        /// How it connects: `sign_in` or `key`.
        let method: String?
        /// An older tafs cloud's word for how it connects, read only when `method` is absent.
        let how: String?
        /// For the account's own connections: "Company" or "Yours", as sent.
        let whose: String?
        /// The tafs that use one of the account's own connections, by name, as sent.
        let usedBy: [String]
        /// Who uses one of the account's own, in tafs cloud's words, alone ("Used by Rae", "Not used by any taf"): the
        /// row's grey line under its status. "" when only a taf this person can't see uses it (nothing is said of use);
        /// nil when tafs cloud doesn't know, or is older than it, and then the row says it from `usedBy` and `line`.
        let usedByWords: String?
        /// The app's own icon on tafs cloud, when it has one: only a `/v1/logos/<32 hex>` path
        /// is kept, so no other address is ever fetched for a row.
        let logo: String?
        /// The connection tafs cloud named for this app, when it names one: its page lists it too.
        let grant: String?
        /// The tafs that need this app, by tafs cloud's id and name (`needed_by`), as the iPad's
        /// `neededBy`: nil when tafs cloud doesn't say, or sent a list this app can't read.
        let neededBy: [Named]?
        /// The live connections of this app made for a taf that doesn't use it (`misplaced`).
        let misplaced: [Misplaced]
        /// A browser connection's way (`cloud`, `chrome`) and its words; nil for any other app.
        let way: String?
        let wayWords: BrowserWays.WayWords?
        /// A `chrome` connection's paired Chrome, by the name planque keeps.
        let chromeName: String?
        /// A `cloud` connection's saved sign-ins, each with its health; none for any other app.
        let sites: [BrowserWays.Site]

        var id: String { entry }

        enum CodingKeys: String, CodingKey {
            case entry, name, title, subtitle, state, line, words, whose, method, how, logo, grant, usedBy = "used_by", usedByWords = "used_by_words", neededBy = "needed_by", misplaced
            case way, wayWords = "way_words", chromeName = "chrome_name", sites
        }
        private struct User: Decodable { let name: String? }
        private struct LenientUser: Decodable {
            let name: String?
            init(from decoder: Decoder) throws { name = (try? User(from: decoder))?.name }
        }
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
            method = text(.method)
            how = text(.how)
            logo = text(.logo).flatMap { Apps.logoPath($0) }
            // A user that doesn't read is left out, never the row.
            let users = ((try? c.decodeIfPresent([LenientUser].self, forKey: .usedBy)) ?? nil) ?? []
            usedBy = users.compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            // Kept as sent, "" included: empty says something here ("nothing to say"), unlike absent.
            usedByWords = ((try? c.decodeIfPresent(String.self, forKey: .usedByWords)) ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines)
            grant = text(.grant)
            // A list it can't read is none sent, as the iPad's: never a guess from half a list.
            neededBy = ((try? c.decodeIfPresent([Named].self, forKey: .neededBy)) ?? nil)?.filter { !$0.taf.isEmpty }
            misplaced = ((try? c.decodeIfPresent([Misplaced].self, forKey: .misplaced)) ?? nil) ?? []
            let sentWay = text(.way)
            way = sentWay == "cloud" || sentWay == "chrome" ? sentWay : nil
            wayWords = way == nil ? nil : (try? c.decodeIfPresent(BrowserWays.WayWords.self, forKey: .wayWords)) ?? nil
            chromeName = way == "chrome" ? text(.chromeName).flatMap(BrowserWays.shown) : nil
            // A site that doesn't read is left out, never the row; a `chrome` connection keeps no sign-in, so it has none.
            struct LenientSite: Decodable { let site: BrowserWays.Site?; init(from decoder: Decoder) throws { site = try? BrowserWays.Site(from: decoder) } }
            sites = way == "cloud" ? ((((try? c.decodeIfPresent([LenientSite].self, forKey: .sites)) ?? nil) ?? []).compactMap(\.site)) : []
        }

        /// The grey line under the status: tafs cloud's `used_by_words` when sent (nothing when it's ""), else nil, and the
        /// row says who uses it from `usedBy` as before.
        var usageWords: String? { usedByWords.flatMap { $0.isEmpty ? nil : $0 } }

        /// The shared key for how it connects, by the iPad's rule: a key when tafs cloud says
        /// `key` (an older one, in `how`), else Sign in.
        var howKey: String { (method ?? how) == "key" ? "connect.how.key" : "connect.how.sign_in" }

        /// One of the account's own connections: connected, to sign in again, or signed in with no taf using it yet
        /// (planque's `signed_in`: a sign-in Coach made whose actions are still to choose). Every sign-in the account
        /// holds is under Yours, so the owner can always end it.
        var isYours: Bool { state == "connected" || state == "needs_reconnect" || isSignedIn }
        /// Signed in, with its actions still to choose and no taf using it: it opens its connections, where
        /// Remove unfinished connection ends it. tafs cloud's line says so ("Sign in · Signed in · Not used by any taf").
        var isSignedIn: Bool { state == "signed_in" }
        /// Its row opens its connections from anywhere on it: connected, or a sign-in still to finish.
        var opensConnections: Bool { isConnected || isSignedIn }
        /// Its sign-in is no longer taken: it needs the person.
        var needsReconnect: Bool { state == "needs_reconnect" }
        /// Connected, with nothing to do: the row ends with a green check.
        var isConnected: Bool { state == "connected" }
        /// Not set up for anyone to connect yet: tafs cloud's words say so, and there is no Connect.
        var needsSetup: Bool { state == "needs_setup" }

        /// The icon's address on tafs cloud, when it sent one.
        var logoURL: URL? { logo.flatMap { URL(string: CloudClient.base + $0) } }
    }

    /// A taf as tafs cloud names it beside an app (`needed_by`, a removed taf's connection's
    /// `used_by`): its id at tafs cloud and its name, as the iPad's `UsedBy`.
    struct Named: Decodable, Equatable {
        let taf: String
        let name: String
        init(taf: String, name: String) { self.taf = taf; self.name = name }
        enum CodingKeys: String, CodingKey { case taf, name }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            taf = try c.decodeIfPresent(String.self, forKey: .taf) ?? ""
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        }
    }

    /// A live connection of an app made for a taf that doesn't use it, as the iPad's `Misplaced`.
    struct Misplaced: Decodable, Equatable {
        let grant: String
        let taf: String
        let name: String
        enum CodingKeys: String, CodingKey { case grant, taf, name }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            grant = try c.decode(String.self, forKey: .grant)
            taf = try c.decodeIfPresent(String.self, forKey: .taf) ?? ""
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        }
    }

    /// A taf removed since, by its KIFF agent (`removed_tafs`), as the iPad's `RemovedTaf`: a
    /// connection whose agent is one is a removed taf's. `grants` only with this Mac's signed
    /// read of its connections, and only when tafs cloud could read them: nil, nothing is cleared.
    struct RemovedTaf: Decodable, Equatable {
        /// A removed taf's live connection, with the live tafs whose Cards still use it.
        struct Grant: Decodable, Equatable {
            let grant: String
            let usedBy: [Named]
            enum CodingKeys: String, CodingKey { case grant, usedBy = "used_by" }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                grant = try c.decode(String.self, forKey: .grant)
                usedBy = try c.decodeIfPresent([Named].self, forKey: .usedBy) ?? []
            }
        }
        let agent: String
        let grants: [Grant]?
    }

    struct Page: Decodable, Equatable {
        let apps: [App]
        let nextCursor: String?
        /// The catalog read stopped with pages left: an app that isn't listed isn't absent.
        let partial: Bool
        /// Coach can connect an app that isn't listed, from its own docs, with a key: the
        /// screen then ends with "Not listed? Ask Coach", as on the iPad.
        let byKey: Bool
        /// The tafs removed since (`removed_tafs`); none from a tafs cloud without it, or one that
        /// sent a list this app can't read.
        let removedTafs: [RemovedTaf]
        /// The two ways a taf uses websites, for the account, with or without a browser connection; none from a tafs cloud
        /// before them.
        let ways: [BrowserWays.Way]

        enum CodingKeys: String, CodingKey { case apps, nextCursor = "next_cursor", partial, byKey = "by_key", removedTafs = "removed_tafs", ways }
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
            byKey = ((try? c.decodeIfPresent(Bool.self, forKey: .byKey)) ?? nil) ?? false
            removedTafs = ((try? c.decodeIfPresent([RemovedTaf].self, forKey: .removedTafs)) ?? nil) ?? []
            ways = BrowserWays.ways(c)
        }
    }

    /// The longest search sent.
    static let longestSearch = 100

    /// A logo's path as the iPad keeps it: `/v1/logos/` and 32 lowercase hex digits, else nil.
    static func logoPath(_ path: String) -> String? {
        let prefix = "/v1/logos/"
        guard path.hasPrefix(prefix) else { return nil }
        let key = path.utf8.dropFirst(prefix.utf8.count)
        guard key.count == 32, key.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }) else { return nil }
        return path
    }

    /// Whom a Discover row's button connects for, as the iPad's `ConnectRow.ConnectFor`.
    enum ConnectFor: Equatable {
        /// The taf the list was opened from.
        case taf(String)
        /// The person picks the taf.
        case ask
        /// No taf needs it: Coach sets one up.
        case askCoach
        /// No taf can have it.
        case noTaf
    }

    /// The iPad's `ConnectRow.connectFor` (`ConnectAppsView.swift:345-367`): only a taf the person
    /// named, among those that need the app when tafs cloud says (`needed`). With `needed_by`,
    /// none, or a taf opened from that doesn't need it, is Ask Coach. Without it, every taf
    /// they manage. `connectable` is tafs cloud's ids.
    static func connectFor(openedFrom taf: String?, connectable: [String], needed: Bool = false) -> ConnectFor {
        guard needed else {
            if let taf { return .taf(taf) }
            return connectable.isEmpty ? .noTaf : .ask
        }
        if let taf { return connectable.contains(taf) ? .taf(taf) : .askCoach }
        return connectable.isEmpty ? .askCoach : .ask
    }

    /// The tafs an app can be connected for, as the iPad's `connectableTafs(_:needed:cloudID:)`
    /// (`AppModel.swift:2809-2812`): of the tafs on tafs cloud this person manages, the ones tafs
    /// cloud says need it, in its order; without `needed_by`, every one.
    static func connectable(_ tafs: [Home.Taf], needed: [Named]?) -> [Home.Taf] {
        guard let needed else { return tafs }
        return needed.compactMap { n in tafs.first { $0.tafID == n.taf } }
    }

    /// Whom a row's Connect is for, as the iPad's `route(_:)` (`ConnectAppsView.swift:281-285`), from
    /// Connect apps itself (not opened from a taf). `.noTaf` turns the button off, and "Make one
    /// first" says why.
    static func route(_ app: App, connectable: [Home.Taf]) -> ConnectFor {
        connectFor(openedFrom: nil, connectable: Self.connectable(connectable, needed: app.neededBy).compactMap(\.tafID),
                   needed: app.neededBy != nil)
    }

    /// "Make one first" shows over Discover only, where connecting needs a taf, as the iPad's
    /// `ConnectRow.saysMakeATaf` (`ConnectAppsView.swift:410-412`): there are apps to connect, the
    /// list wasn't opened from a taf, and no taf can have them. Never over Yours.
    static func saysMakeATaf(discover: [App], forTaf: Bool, connectable: [Home.Taf]) -> Bool {
        !discover.isEmpty && !forTaf && connectable.isEmpty
    }

    /// The words of a row's button, as the iPad's `trailing` (`ConnectAppsView.swift:195-220`):
    /// "Ask Coach" where no taf needs the app, else Sign in again or Connect. Here every one of
    /// them opens Coach, where an app is connected on this Mac.
    static func buttonKey(_ app: App, connectable: [Home.Taf]) -> String {
        if route(app, connectable: connectable) == .askCoach { return "coach.ask" }
        return app.needsReconnect ? "connect.sign_in_again" : "connect.apps.connect"
    }
}

extension CloudClient {
    /// One page of the catalog, searched by `q`; `cursor` continues the same search. `proof` is
    /// this Mac's signed read of its connections (`Planque-Device-Signature`), as the iPad's
    /// `connectApps(_:proof:)`: with it, tafs cloud says which removed taf's connections there are.
    func apps(_ q: String = "", cursor: String? = nil, proof: String? = nil) async throws -> Apps.Page {
        var query = ["q=\(Self.query(String(q.prefix(Apps.longestSearch))))"]
        if let cursor { query.append("cursor=\(Self.query(cursor))") }
        return try await get("/v1/connect/apps?" + query.joined(separator: "&"), headers: proof.map { ["Planque-Device-Signature": $0] } ?? [:])
    }
}

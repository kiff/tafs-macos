import Foundation

/// How a taf uses websites (tafs docs/api.md, "How a taf uses websites: the two ways, and sign-in health"): the cloud
/// browser or the owner's Chrome, and each saved sign-in's health. Every word is tafs cloud's; the app works out nothing,
/// not which way, not "soon", not when a run waits.
enum BrowserWays {
    /// One of the two ways, as Connect apps lists them for the account, with or without a browser connection.
    struct Way: Decodable, Equatable, Identifiable {
        /// `cloud` or `chrome`.
        let way: String
        let words: Words
        var id: String { way }

        struct Words: Decodable, Equatable {
            let title: String
            let line: String
            /// Two short lines about what this way holds.
            let facts: [String]
            /// The way's state on this account ("2 sign-ins saved", "Paired with Office Mac"); nil with nothing to say.
            let status: String?

            enum CodingKeys: String, CodingKey { case title, line, facts, status }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                guard let title = BrowserWays.text(c, .title), let line = BrowserWays.text(c, .line) else {
                    throw DecodingError.dataCorruptedError(forKey: .title, in: c, debugDescription: "a way with no words")
                }
                self.title = title
                self.line = line
                facts = (((try? c.decodeIfPresent([String].self, forKey: .facts)) ?? nil) ?? []).compactMap(BrowserWays.shown)
                status = BrowserWays.text(c, .status)
            }
        }
    }

    /// A browser connection's way, in tafs cloud's words (`way`, `way_words`).
    struct WayWords: Decodable, Equatable {
        let title: String
        let line: String
        enum CodingKeys: String, CodingKey { case title, line }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let title = BrowserWays.text(c, .title), let line = BrowserWays.text(c, .line) else {
                throw DecodingError.dataCorruptedError(forKey: .title, in: c, debugDescription: "a way with no words")
            }
            self.title = title
            self.line = line
        }
    }

    /// One saved sign-in on a `cloud` connection, as Connect apps lists them (`saved_sign_ins`, one per connection and
    /// site, beside `ways`): the site, which tafs use it, its health, and Sign in again (`sign_in`, the `site_sign_in`
    /// action) in tafs cloud's words.
    struct SavedSignIn: Decodable, Equatable, Identifiable {
        let grant: String
        let site: String
        let usedBy: [String]
        let health: Health?
        /// Sign in again's title, in tafs cloud's words; nil when tafs cloud offers none.
        let signIn: String?
        var id: String { grant + "|" + site }

        enum CodingKeys: String, CodingKey { case grant, site, usedBy = "used_by", health, signIn = "sign_in" }
        private struct Action: Decodable { let title: String? }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let grant = BrowserWays.text(c, .grant), let site = BrowserWays.text(c, .site) else {
                throw DecodingError.dataCorruptedError(forKey: .site, in: c, debugDescription: "a sign-in with no connection or site")
            }
            self.grant = grant
            self.site = site
            usedBy = (((try? c.decodeIfPresent([String].self, forKey: .usedBy)) ?? nil) ?? []).compactMap(BrowserWays.shown)
            // Health that doesn't read is none: the site is still listed, with nothing said about its sign-in.
            health = (try? c.decodeIfPresent(Health.self, forKey: .health)) ?? nil
            signIn = ((try? c.decodeIfPresent(Action.self, forKey: .signIn)) ?? nil)?.title.flatMap(BrowserWays.shown)
        }
    }

    /// One site of a `cloud` connection in a taf's setup (`connections[].sites[]`), with its sign-in's health.
    struct SetupSite: Decodable, Equatable, Identifiable {
        let site: String
        let health: Health?
        var id: String { site }
        enum CodingKeys: String, CodingKey { case site, health }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let site = BrowserWays.text(c, .site) else {
                throw DecodingError.dataCorruptedError(forKey: .site, in: c, debugDescription: "a site with no name")
            }
            self.site = site
            health = (try? c.decodeIfPresent(Health.self, forKey: .health)) ?? nil
        }
    }

    /// How a taf uses websites, on its setup (`browsing`): its sites, its way and the way's words, Coach's reason in tafs
    /// cloud's words (`why`), and the other way's button, an ask to Coach (`switch`).
    struct Browsing: Decodable, Equatable {
        let sites: [String]
        let way: String
        let wayWords: WayWords
        /// Coach's reason, in tafs cloud's words ("Coach chose the cloud browser because File invoices runs at 8:00, …").
        let why: String?
        /// The other way's button: its words, and what it writes in Coach's box (`ask`); nil when tafs cloud offers none.
        let switchTo: Switch?

        struct Switch: Decodable, Equatable {
            let button: String
            let ask: String
            enum CodingKeys: String, CodingKey { case words, ask }
            private struct Words: Decodable { let button: String? }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                guard let button = ((try? c.decodeIfPresent(Words.self, forKey: .words)) ?? nil)?.button.flatMap(BrowserWays.shown),
                      let ask = BrowserWays.text(c, .ask) else {
                    throw DecodingError.dataCorruptedError(forKey: .ask, in: c, debugDescription: "a switch with no button or ask")
                }
                self.button = button
                self.ask = ask
            }
        }

        enum CodingKeys: String, CodingKey { case sites, way, wayWords = "way_words", why, switchTo = "switch" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let sent = BrowserWays.text(c, .way)
            guard let way = sent, way == "cloud" || way == "chrome" else {
                throw DecodingError.dataCorruptedError(forKey: .way, in: c, debugDescription: "no way this app knows")
            }
            self.way = way
            wayWords = try c.decode(WayWords.self, forKey: .wayWords)
            sites = (((try? c.decodeIfPresent([String].self, forKey: .sites)) ?? nil) ?? []).compactMap(BrowserWays.shown)
            why = BrowserWays.text(c, .why)
            switchTo = (try? c.decodeIfPresent(Switch.self, forKey: .switchTo)) ?? nil
        }
    }

    /// A saved sign-in's health, as tafs cloud decided it from planque's check.
    struct Health: Decodable, Equatable {
        /// `signed_in`, `needs_you_soon`, `stopped` or `unknown`; anything else reads as `unknown`.
        let state: String
        let words: Words

        struct Words: Decodable, Equatable {
            /// "Signed in · checked today 07:00", "Needs you by Tue 2 Dec", "Stopped working at 07:55", "Not checked".
            let line: String
            /// The answer to Why?, when tafs cloud gives one.
            let why: String?
            enum CodingKeys: String, CodingKey { case line, why }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                guard let line = BrowserWays.text(c, .line) else {
                    throw DecodingError.dataCorruptedError(forKey: .line, in: c, debugDescription: "health with no line")
                }
                self.line = line
                why = BrowserWays.text(c, .why)
            }
        }

        enum CodingKeys: String, CodingKey { case state, words }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let sent = (try? c.decode(String.self, forKey: .state)) ?? ""
            state = Health.states.contains(sent) ? sent : "unknown"
            words = try c.decode(Words.self, forKey: .words)
        }

        static let states: Set<String> = ["signed_in", "needs_you_soon", "stopped", "unknown"]

        /// Whether the line is drawn as a warning: soon in amber, stopped in red. `unknown` and `signed_in` warn of nothing.
        var tone: Tone {
            switch state {
            case "needs_you_soon": return .soon
            case "stopped": return .stopped
            default: return .plain
            }
        }
        enum Tone: Equatable { case plain, soon, stopped }

        /// Sign in again is offered when the sign-in needs the owner, soon or now.
        var asksToSignIn: Bool { state == "needs_you_soon" || state == "stopped" }
    }

    /// Text as tafs cloud sent it, direction characters taken out; nil when it's blank.
    static func shown(_ s: String) -> String? {
        let kept = BidiFree.text(s)
        return kept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : kept
    }

    fileprivate static func text<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> String? {
        ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil).flatMap(shown)
    }

    /// The saved sign-ins as Connect apps lists them, each read on its own: one that doesn't read is left out, never the rest.
    static func savedSignIns(_ c: KeyedDecodingContainer<Apps.Page.CodingKeys>) -> [SavedSignIn] {
        struct Lenient: Decodable { let item: SavedSignIn?; init(from decoder: Decoder) throws { item = try? SavedSignIn(from: decoder) } }
        return (((try? c.decodeIfPresent([Lenient].self, forKey: .savedSignIns)) ?? nil) ?? []).compactMap(\.item)
    }

    /// The ways as Connect apps lists them, each read on its own: one that doesn't read is left out, never the rest.
    static func ways(_ c: KeyedDecodingContainer<Apps.Page.CodingKeys>) -> [Way] {
        struct Lenient: Decodable { let way: Way?; init(from decoder: Decoder) throws { way = try? Way(from: decoder) } }
        return (((try? c.decodeIfPresent([Lenient].self, forKey: .ways)) ?? nil) ?? []).compactMap(\.way)
            .filter { $0.way == "cloud" || $0.way == "chrome" }
    }
}

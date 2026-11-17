import Foundation

/// "Coach waiting" (`coach_waiting` on `GET /v1/home`), ported from the iPad's
/// `TafsCloud+CoachWaiting.swift`: a Coach chat paused on a card its person answers (an approval,
/// a sign-in, questions, a confirm). Home lists each once, oldest first, and counts it in Needs
/// you, so nothing says nothing needs the person while Coach waits. Every word is tafs cloud's.
struct CoachWaiting: Decodable, Equatable, Identifiable {
    struct Words: Decodable, Equatable {
        /// What Coach waits for: "Support: Coach is waiting for your approval since 09:12."
        var line = ""
        /// The way in: "Open Coach".
        var open = ""
        /// Set aside's words. None, no button.
        var setAside = ""

        init(line: String = "", open: String = "", setAside: String = "") { self.line = line; self.open = open; self.setAside = setAside }
        enum CodingKeys: String, CodingKey { case line, open, setAside = "set_aside" }
        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            func w(_ key: CodingKeys) -> String { (((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            line = w(.line); open = w(.open); setAside = w(.setAside)
        }
    }

    /// The taf the chat is on, and the chat (`session`) to open.
    var taf = ""
    var session = ""
    var run = ""
    var since = ""
    var words = Words()
    var id: String { session }
    /// Listed only with its chat and both of tafs cloud's lines, as the iPad's `usable`.
    var usable: Bool { !session.isEmpty && !words.line.isEmpty && !words.open.isEmpty }
    /// Set aside is offered only where tafs cloud sent its words, as the iPad's `canSetAside`.
    var canSetAside: Bool { !session.isEmpty && !words.setAside.isEmpty }

    init(taf: String = "", session: String = "", run: String = "", since: String = "", words: Words = Words()) {
        self.taf = taf; self.session = session; self.run = run; self.since = since; self.words = words
    }
    enum CodingKeys: String, CodingKey { case taf, session, run, since, words }
    /// Read leniently: one the app can't read is left out, never Home with it.
    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        func s(_ key: CodingKeys) -> String { ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil) ?? "" }
        taf = s(.taf); session = s(.session); run = s(.run); since = s(.since)
        words = ((try? c.decodeIfPresent(Words.self, forKey: .words)) ?? nil) ?? Words()
    }

    /// Home's list as Needs you draws it: only those it can, in tafs cloud's order. A list that
    /// isn't one is none, never Home with it.
    static func listed<Key: CodingKey>(_ c: KeyedDecodingContainer<Key>, _ key: Key) -> [CoachWaiting] {
        (((try? c.decodeIfPresent([CoachWaiting].self, forKey: key)) ?? nil) ?? []).filter(\.usable)
    }
}

/// Home's "Set all aside" (`coach_waiting_clear`), sent for two or more waiting chats: the button,
/// and the one ask before it, whose title names the count it ends. Every word is tafs cloud's.
struct CoachWaitingClear: Decodable, Equatable {
    struct Words: Decodable, Equatable {
        var button = ""
        var title = ""
        var text = ""
        var yes = ""
        var no = ""
        init(button: String = "", title: String = "", text: String = "", yes: String = "", no: String = "") {
            self.button = button; self.title = title; self.text = text; self.yes = yes; self.no = no
        }
        enum CodingKeys: String, CodingKey { case button, title, text, yes, no }
        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            func w(_ k: CodingKeys) -> String { (((try? c.decodeIfPresent(String.self, forKey: k)) ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            button = w(.button); title = w(.title); text = w(.text); yes = w(.yes); no = w(.no)
        }
    }
    var words = Words()
    init(words: Words = Words()) { self.words = words }
    enum CodingKeys: String, CodingKey { case words }
    /// Read leniently: one the app can't read is none, never Home with it.
    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        words = ((try? c.decodeIfPresent(Words.self, forKey: .words)) ?? nil) ?? Words()
    }
    /// One the app can draw: its button, the ask's title, and its yes.
    var usable: Bool { !words.button.isEmpty && !words.title.isEmpty && !words.yes.isEmpty }

    /// Home's, when it can be drawn; nil otherwise.
    static func read<Key: CodingKey>(_ c: KeyedDecodingContainer<Key>, _ key: Key) -> CoachWaitingClear? {
        ((try? c.decodeIfPresent(CoachWaitingClear.self, forKey: key)) ?? nil).flatMap { $0.usable ? $0 : nil }
    }
}

/// What setting Coach chats aside did: the chats it ended, and the connections it withdrew;
/// `already` when the same chat was set aside before (a POST sent again).
struct CoachSetAside: Decodable, Equatable {
    var setAside: [String] = []
    var withdrawn = 0
    var already = false
    enum CodingKeys: String, CodingKey { case setAside = "set_aside", withdrawn, already }
    init(setAside: [String] = [], withdrawn: Int = 0, already: Bool = false) {
        self.setAside = setAside; self.withdrawn = withdrawn; self.already = already
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        setAside = ((try? c.decodeIfPresent([String].self, forKey: .setAside)) ?? nil) ?? []
        withdrawn = ((try? c.decodeIfPresent(Int.self, forKey: .withdrawn)) ?? nil) ?? 0
        already = ((try? c.decodeIfPresent(Bool.self, forKey: .already)) ?? nil) ?? false
    }
}

/// Needs you's count and its line, as the iPad's `needsYouCount` and `needsYouWords`
/// (AppModel.swift:73-84): tafs cloud's count when it sent one, less the steps answered here it
/// still counts and the Coach chats left out (open in Coach, or being set aside); else the app's
/// own count of what it has: held calls, Card unit requests, steps, "Did this happen?" and Coach's
/// waiting chats.
enum NeedsYouCount {
    struct Parts: Equatable {
        /// tafs cloud's count and its words (`needs_you`); nil when it sent none.
        var home: Int?
        var homeWords: String?
        var held = 0
        var cardUnits = 0
        var steps = 0
        var unproven = 0
        /// Coach's waiting chats Needs you draws, and those Home listed that it leaves out.
        var coachWaiting = 0
        var coachWaitingHidden = 0
        /// Of tafs cloud's count, the steps answered here that it still counts.
        var answeredStillCounted = 0
    }

    static func count(_ p: Parts) -> Int {
        if let home = p.home { return max(0, home - p.answeredStillCounted - p.coachWaitingHidden) }
        return p.held + p.cardUnits + p.steps + p.unproven + p.coachWaiting
    }

    /// Home's line: tafs cloud's words while they still say what's counted, else the app's own.
    static func words(_ p: Parts, _ say: Words) -> String {
        if p.answeredStillCounted == 0, p.coachWaitingHidden == 0, let words = p.homeWords, !words.isEmpty { return words }
        let n = count(p)
        return n == 0 ? say("needs_you.nothing") : say.count("needs_you.count", n)
    }

    /// Coach's waiting chats as Needs you draws them, as the iPad's `coachWaiting`: Home's, less the
    /// chat open in Coach now (the person is in it), and less those being set aside.
    static func shown(_ listed: [CoachWaiting], onScreen: String?, settingAside: Set<String>) -> [CoachWaiting] {
        listed.filter { $0.session != onScreen && !settingAside.contains($0.session) }
    }
}

extension CloudClient {
    /// Where one waiting chat is set aside, or every one with no `session`, as the iPad's `setAsidePath`.
    static func setAsidePath(_ session: String?) -> String {
        "/v1/home/coach-waiting/" + (session.map { escaped($0) + "/" } ?? "") + "set-aside"
    }

    /// Sets one waiting Coach chat aside, or every one with no `session`, as the iPad's
    /// `setAsideCoach`: "not now", answered by tafs cloud, never an approval. Nothing is signed.
    /// The device's signed read of its connections (`proof`) lets tafs cloud withdraw a
    /// connection the chat asked for.
    func setAsideCoach(_ session: String?, proof: String?) async throws -> CoachSetAside {
        let body = try await post(Self.setAsidePath(session), body: [String: String](), headers: proof.map { ["Planque-Device-Signature": $0] } ?? [:])
        return try decoded(body)
    }
}

import Foundation

/// "Your brief" (kiff/tafs `docs/missions.md`, "Your brief"): what tafs got done and what needs
/// the person, twice a day, from `GET /v1/brief?label=`. Every word, count, order and urgency is
/// tafs cloud's; the app draws it and decides nothing. Read leniently, as the iPad's
/// `TafsCloud.Brief` (TafsCloud+Brief.swift:7-243, kiff/tafs#1173): a part the app can't read is
/// left out, never the brief with it.
struct Brief: Decodable, Equatable {
    /// The headings, in the person's language.
    struct Words: Decodable, Equatable {
        var tab = "", title = "", when = "", decisions = "", done = "", nextMove = "", recommends = "",
            meanwhile = "", evidence = "", all = "", urgent = ""
        enum CodingKeys: String, CodingKey {
            case tab, title, when, decisions, done, recommends, meanwhile, evidence, all, urgent
            case nextMove = "next_move"
        }
        init() {}
        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            func text(_ k: CodingKeys) -> String { Brief.text(c, k) ?? "" }
            tab = text(.tab); title = text(.title); when = text(.when); decisions = text(.decisions); done = text(.done)
            // tafs cloud's route sends the tab's name as `title` ("Your brief").
            if tab.isEmpty { tab = title }
            nextMove = text(.nextMove); recommends = text(.recommends); meanwhile = text(.meanwhile)
            evidence = text(.evidence); all = text(.all); urgent = text(.urgent)
        }
    }

    /// What a decision is about: a held call, a step, a connection or a proposal.
    struct Ref: Decodable, Equatable {
        var kind = "", id = "", taf = ""
        enum CodingKeys: String, CodingKey { case kind, id, taf }
        init(kind: String = "", id: String = "", taf: String = "") { self.kind = kind; self.id = id; self.taf = taf }
        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            kind = Brief.text(c, .kind) ?? ""; id = Brief.text(c, .id) ?? ""; taf = Brief.text(c, .taf) ?? ""
        }
        /// How Needs you names the same item: `hold:<id>`, `step:<handoff>`.
        var item: String { kind + ":" + id }
    }

    struct Answer: Decodable, Equatable, Identifiable {
        var words = "", answer = ""
        /// At most one, Coach's pick; with no `why`, the answers show as equals.
        var recommended = false
        /// A decline ("Don't send"): drawn as one, never read as a no by the app.
        var decline = false
        var id: String { answer + "|" + words }
        enum CodingKeys: String, CodingKey { case words, answer, recommended, decline }
        init(words: String = "", answer: String = "", recommended: Bool = false, decline: Bool = false) {
            self.words = words; self.answer = answer; self.recommended = recommended; self.decline = decline
        }
        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            words = Brief.text(c, .words) ?? ""; answer = Brief.text(c, .answer) ?? ""
            recommended = Brief.flag(c, .recommended); decline = Brief.flag(c, .decline)
        }
    }

    struct Decision: Decodable, Equatable, Identifiable {
        var id = "", question = ""
        var answers: [Answer] = []
        /// Why Coach recommends its answer; none, and no answer is drawn as recommended.
        var why: String?
        var meanwhile = ""
        /// When it must be decided by, in words ("by Fri 12:00").
        var deadline: String?
        var urgent = false
        /// "Later" moves it to the next brief; left out when it can't be put off.
        var later: String?
        /// Why it can't wait, when `later` is left out.
        var cantWait: String?
        /// A line under the answers.
        var note: String?
        var ref = Ref()
        enum CodingKeys: String, CodingKey {
            case id, question, answers, why, meanwhile, deadline, urgent, later, note, ref
            case cantWait = "cant_wait", nowWhy = "now_why"
        }
        private struct LaterWords: Decodable { var words: String? }
        init(id: String = "", question: String = "", answers: [Answer] = [], ref: Ref = Ref()) {
            self.id = id; self.question = question; self.answers = answers; self.ref = ref
        }
        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            id = Brief.text(c, .id) ?? ""; question = Brief.text(c, .question) ?? ""
            answers = (Brief.list(c, .answers) as [Answer]).filter { !$0.words.isEmpty }
            why = Brief.text(c, .why); meanwhile = Brief.text(c, .meanwhile) ?? ""; deadline = Brief.text(c, .deadline)
            urgent = Brief.flag(c, .urgent)
            later = ((try? c.decodeIfPresent(LaterWords.self, forKey: .later)) ?? nil)?.words
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
            // tafs cloud's route says why it can't wait as `now_why`.
            cantWait = Brief.text(c, .cantWait) ?? Brief.text(c, .nowWhy); note = Brief.text(c, .note)
            ref = ((try? c.decodeIfPresent(Ref.self, forKey: .ref)) ?? nil) ?? Ref()
        }
        /// Coach's pick, drawn first and filled; only with its why.
        var recommended: Answer? { why == nil ? nil : answers.first { $0.recommended } }
        /// One the app can draw: an id, a question and at least one answer.
        var usable: Bool { !id.isEmpty && !question.isEmpty && !answers.isEmpty }
        /// Later, as the card offers it: never for an urgent decision, whatever was sent.
        var offersLater: String? { urgent ? nil : later }
    }

    /// One item a job works on, in tafs cloud's line. Closed only when the source says so.
    struct Case: Decodable, Equatable, Identifiable {
        var name = "", words = "", state = ""
        var nextCheck: String?
        var id: String { name + "|" + words }
        enum CodingKeys: String, CodingKey { case name, words, state; case nextCheck = "next_check" }
        init(name: String = "", words: String = "", state: String = "") { self.name = name; self.words = words; self.state = state }
        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            name = Brief.text(c, .name) ?? ""; words = Brief.text(c, .words) ?? ""; state = Brief.text(c, .state) ?? ""
            nextCheck = Brief.text(c, .nextCheck)
        }
        var closed: Bool { state == "closed" }
        var waiting: Bool { state == "waiting" }
    }

    struct Done: Decodable, Equatable, Identifiable {
        /// The mission's name: its words, or the route's `{id, name}`.
        var mission: String?
        var cases: [Case] = []
        /// What it's worth, in words ("€3,400 due back").
        var value: String?
        /// The mission whose log holds the evidence.
        var log: String?
        var id: String { (mission ?? "") + "|" + cases.map(\.id).joined() }
        enum CodingKeys: String, CodingKey { case mission, cases, value, log }
        private struct Named: Decodable { var name: String? }
        private static func named(_ name: String?) -> String? {
            let t = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? nil : t
        }
        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            mission = Brief.text(c, .mission)
                ?? Self.named(((try? c.decodeIfPresent(Named.self, forKey: .mission)) ?? nil)?.name)
            cases = (Brief.list(c, .cases) as [Case]).filter { !$0.words.isEmpty || !$0.name.isEmpty }
            value = Brief.text(c, .value); log = Brief.text(c, .log)
        }
    }

    struct NextMove: Decodable, Equatable {
        var words = "", start = "", dismiss = ""
        enum CodingKeys: String, CodingKey { case words, start, dismiss }
        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            words = Brief.text(c, .words) ?? ""; start = Brief.text(c, .start) ?? ""; dismiss = Brief.text(c, .dismiss) ?? ""
        }
        var usable: Bool { !words.isEmpty && !start.isEmpty && !dismiss.isEmpty }
    }

    /// A count and its words: "more" decisions, the "rest" that need nothing now.
    struct Counted: Decodable, Equatable {
        var count = 0, words = ""
        enum CodingKeys: String, CodingKey { case count, words }
        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            count = ((try? c.decodeIfPresent(Int.self, forKey: .count)) ?? nil) ?? 0; words = Brief.text(c, .words) ?? ""
        }
    }

    var decisions: [Decision] = []
    var more: Counted?
    var done: [Done] = []
    var nextMove: NextMove?
    var rest: Counted?
    var credits: String?
    var labels: [HomeLabel] = []
    var words = Words()

    enum CodingKeys: String, CodingKey { case decisions, more, done, rest, credits, labels, words, nextMove = "next_move" }
    private struct CreditWords: Decodable { var words: String? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        decisions = (Self.list(c, .decisions) as [Decision]).filter(\.usable)
        more = ((try? c.decodeIfPresent(Counted.self, forKey: .more)) ?? nil).flatMap { $0.count > 0 && !$0.words.isEmpty ? $0 : nil }
        done = (Self.list(c, .done) as [Done]).filter { !$0.cases.isEmpty }
        nextMove = ((try? c.decodeIfPresent(NextMove.self, forKey: .nextMove)) ?? nil).flatMap { $0.usable ? $0 : nil }
        rest = ((try? c.decodeIfPresent(Counted.self, forKey: .rest)) ?? nil).flatMap { $0.words.isEmpty ? nil : $0 }
        credits = ((try? c.decodeIfPresent(CreditWords.self, forKey: .credits)) ?? nil)?.words.flatMap { $0.isEmpty ? nil : $0 }
        labels = HomeLabels.list(c, .labels)
        words = ((try? c.decodeIfPresent(Words.self, forKey: .words)) ?? nil) ?? Words()
    }

    /// Whether there's anything to show in Needs you's place, as the iPad's `loadBrief`: a brief
    /// with no decision, nothing done and no next move leaves Needs you as it is.
    var shown: Bool { !(decisions.isEmpty && done.isEmpty && nextMove == nil) }

    /// Where a decision is answered: the route it already has, where its own signed answer is
    /// given, as the iPad's `destination(of:answer:)`. A held call opens on its own card with
    /// **no answer chosen**: the answer is never part of the route, so nothing is signed from the
    /// brief and no unlock is reused. A step opens on its step; anything else, Needs you.
    enum Destination: Equatable {
        case hold(String), step(String), needsYou
    }
    static func destination(of decision: Decision) -> Destination {
        guard !decision.ref.id.isEmpty else { return .needsYou }
        switch decision.ref.kind {
        case "hold": return .hold(decision.ref.id)
        case "step": return .step(decision.ref.id)
        default: return .needsYou
        }
    }

    /// How much of Needs you the brief doesn't show, matched item by item, never by number, as the
    /// iPad's `needsYouBeyondBrief`: a held call or a step the brief shows is matched by its `ref`
    /// (`hold:<id>`, `step:<handoff>`), and anything the brief can't carry (`others`) counts.
    static func needsYouBeyond(items: [String], others: Int, shown: [Decision]) -> Int {
        let matched = Set(shown.map(\.ref.item))
        return items.filter { !matched.contains($0) }.count + others
    }

    /// A line of text, trimmed; none when absent, blank or of another shape.
    static func text<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> String? { HomeLabels.text(c, key) }

    fileprivate static func flag<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Bool {
        ((try? c.decodeIfPresent(Bool.self, forKey: key)) ?? nil) ?? false
    }

    /// A list whose items are read one by one: one the app can't read is left out, never the list.
    fileprivate static func list<K: CodingKey, T: Decodable>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [T] {
        (((try? c.decodeIfPresent([BriefItem<T>].self, forKey: key)) ?? nil) ?? []).compactMap(\.value)
    }
}

/// A mission's log (kiff/tafs `docs/missions.md`, "The log"), as the iPad's `TafsCloud.MissionLog`
/// (TafsCloud+Brief.swift:270-336): read only, newest first. Each entry says when, by whom (a taf,
/// the lead Coach, or the person), its kind and its words, with its evidence and value. A removed
/// taf's entries stay, marked removed.
struct MissionLog: Decodable, Equatable {
    struct Evidence: Decodable, Equatable, Identifiable {
        var kind = "", id = "", words = ""
        enum CodingKeys: String, CodingKey { case kind, id, words }
        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            kind = Brief.text(c, .kind) ?? ""; id = Brief.text(c, .id) ?? ""; words = Brief.text(c, .words) ?? ""
        }
    }

    /// Who wrote an entry, as tafs cloud sends it, or its own words when it sends them.
    enum Author: Equatable {
        case words(String)
        case taf(String?), lead(String?), person(String?)
    }

    struct Item: Decodable, Equatable, Identifiable {
        var at: Date?
        var author = Author.words("")
        var kind = "", words = ""
        /// The kind in the person's words ("delivered", "handed").
        var kindWords = ""
        var evidence: [Evidence] = []
        var value: String?
        var removed = false
        /// tafs cloud's id for the entry, when it sends one.
        var serverID: String?
        private var raw = ""
        var id: String { serverID ?? raw }
        enum CodingKeys: String, CodingKey {
            case at, by, kind, words, evidence, value, removed
            case kindWords = "kind_words", byWords = "by_words", serverID = "id"
        }
        /// `by`: `{kind: taf | lead | person, name?}`.
        private struct By: Decodable { var kind: String?; var name: String? }
        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            let atText = Brief.text(c, .at) ?? ""
            at = Thread.time(atText)
            kind = Brief.text(c, .kind) ?? ""; words = Brief.text(c, .words) ?? ""
            kindWords = Brief.text(c, .kindWords) ?? ""
            serverID = Brief.text(c, .serverID)
            if let said = Brief.text(c, .byWords) {
                author = .words(said)
            } else if let byText = Brief.text(c, .by) {
                author = .words(byText)
            } else if let who = (try? c.decodeIfPresent(By.self, forKey: .by)) ?? nil {
                let trimmed = who.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let name: String? = trimmed.isEmpty ? nil : trimmed
                switch who.kind {
                case "lead": author = .lead(name)
                case "person": author = .person(name)
                default: author = .taf(name)
                }
            }
            evidence = (Brief.list(c, .evidence) as [Evidence]).filter { !$0.words.isEmpty }
            value = Brief.text(c, .value)
            removed = Brief.flag(c, .removed)
            raw = atText + "|" + words
        }

        /// Who wrote it, in the person's words: its name, else the lead as Coach, the person as
        /// You, and a removed taf as "A taf", as the iPad's.
        func by(_ say: (String) -> String) -> String {
            switch author {
            case .words(let words): return words
            case .lead(let name): return name ?? say("coach.title")
            case .person(let name): return name ?? say("common.you")
            case .taf(let name): return name ?? say("needs_you.a_taf")
            }
        }
    }

    var items: [Item] = []
    var before: String?
    enum CodingKeys: String, CodingKey { case items, before }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (Brief.list(c, .items) as [Item]).filter { !$0.words.isEmpty }
        before = Brief.text(c, .before)
    }
}

/// One item of a list, or nothing, as the iPad's `LenientItem`.
private struct BriefItem<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

extension CloudClient {
    /// Your brief, filtered to a label or for all (`GET /v1/brief?label=`).
    func brief(label: String?) async throws -> Brief {
        try await get("/v1/brief" + (label.map { "?label=" + Self.query($0) } ?? ""))
    }

    /// "Later": the decision moves to the next brief (`POST /v1/brief/decisions/{id}/later`). Its id
    /// (`hold:<id>`, `step:<handoff>`) is one path segment, escaped as every id is.
    func briefLater(_ decision: String) async throws {
        _ = try await post("/v1/brief/decisions/\(Self.escaped(decision))/later", [:])
    }

    /// A mission's log, newest first, a page at a time (`GET /v1/missions/{id}/log?before=`).
    func missionLog(_ mission: String, before: String? = nil) async throws -> MissionLog {
        try await get("/v1/missions/\(Self.escaped(mission))/log" + (before.map { "?before=" + Self.query($0) } ?? ""))
    }
}

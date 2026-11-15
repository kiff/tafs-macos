import Foundation

/// The app's list (`GET /v1/home`): each taf with where its work stands, as tafs cloud counts
/// and words it. The app counts nothing itself and draws the lines as sent.
enum Home {
    struct Taf: Decodable, Identifiable, Equatable {
        /// Its health, as tafs cloud reads it, ported from the iPad's `TafsCloud.Health`: its
        /// level, each reason as a line in the person's language, and the fixes tafs cloud decides
        /// for the lines that have one. The app decides nothing: an unknown level is drawn as its
        /// lines, and a fix of a kind it doesn't know is no button.
        struct Health: Decodable, Equatable {
            /// A way to fix what one line says: Coach with `say` in its box (`coach`), or Plan &
            /// usage (`credits`). `line` is the line's index.
            struct Fix: Decodable, Equatable {
                let line: Int
                let kind: String
                let words: String
                let say: String?

                enum CodingKeys: String, CodingKey { case line, kind, words, say }
                init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    line = (try? c.decode(Int.self, forKey: .line)) ?? -1
                    kind = (try? c.decode(String.self, forKey: .kind)) ?? ""
                    words = (try? c.decode(String.self, forKey: .words)) ?? ""
                    say = (try? c.decodeIfPresent(String.self, forKey: .say)) ?? nil
                }
            }

            let level: String
            let lines: [String]
            let fixes: [Fix]

            enum CodingKeys: String, CodingKey { case level, lines, fixes }
            init(level: String, lines: [String], fixes: [Fix] = []) { self.level = level; self.lines = lines; self.fixes = fixes }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                level = ((try? c.decodeIfPresent(String.self, forKey: .level)) ?? nil) ?? "healthy"
                // Each line on its own, as the iPad's `LenientItem<String>`: one that isn't words is
                // left out, never the others.
                struct Line: Decodable { let line: String?; init(from decoder: Decoder) throws { line = try? String(from: decoder) } }
                lines = (((try? c.decodeIfPresent([Line].self, forKey: .lines)) ?? nil) ?? []).compactMap(\.line)
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                struct Lenient: Decodable { let fix: Fix?; init(from decoder: Decoder) throws { fix = try? Fix(from: decoder) } }
                fixes = (((try? c.decodeIfPresent([Lenient].self, forKey: .fixes)) ?? nil) ?? []).compactMap(\.fix)
            }
            var healthy: Bool { level == "healthy" }
            /// Not healthy, with tafs cloud's lines for why, as the iPad's `needsAttention`.
            var needsAttention: Bool { !healthy && !lines.isEmpty }
            var failing: Bool { level == "failing" }

            /// The fixes for one line, of the kinds the app can act on, in tafs cloud's order.
            func fixes(for line: Int) -> [Fix] {
                fixes.filter { $0.line == line && ["coach", "credits"].contains($0.kind) && !$0.words.isEmpty && ($0.kind != "coach" || !($0.say ?? "").isEmpty) }
            }
        }

        /// The KIFF agent it acts as: what tells one row from another.
        let kiffAgent: String
        /// Its id at tafs cloud; nil for an agent tafs doesn't run.
        let tafID: String?
        /// Its Cards, the live ones first.
        let cards: [TafCard]
        let name: String
        /// Its colour, by its index in the palette.
        let color: Int
        /// working, paused, waiting, idle or stopped, as tafs cloud names it.
        let state: String
        /// tafs cloud's record of it: `active` or `paused`, as the iPad's `CloudTaf.status`
        /// (`status ?? "active"`). Pausing is read from this, never from `state`, which says
        /// `waiting` for a paused taf with a call held.
        let status: String
        /// Paused on tafs cloud, as the iPad's `CloudTaf.paused`.
        var paused: Bool { status == "paused" }
        /// Its calls held for the person.
        let waiting: Int
        /// What it does, in words.
        let jobSummary: String?
        /// Where its work stands, in tafs cloud's line.
        let workLine: String?
        /// Something went wrong last: the line is drawn as a warning.
        let attention: Bool
        /// Its next run, in tafs cloud's words ("Next run Mon 08:00"), and as a time.
        let nextRunWords: String?
        let nextRun: Date?
        let health: Health?
        /// A taf with no schedule: it works from its chat.
        let unscheduled: Bool
        /// tafs cloud's status for its work: `working`, `idle`, `paused`.
        let workStatus: String?
        /// Its setup stopped partway: tafs cloud's words for it, in place of what it's doing.
        let finishWords: String?
        /// Where its results go that tafs cloud delivers (`door_reply`, `app`, `owner_email`),
        /// as sent; nil when tafs cloud doesn't say (Setup's Results go to then reads the dial).
        let results: [JSONValue]?

        var id: String { kiffAgent }

        enum CodingKeys: String, CodingKey {
            case kiffAgent = "kiff_agent", tafID = "id", card, name, color, state, status, waiting, jobSummary = "job_summary"
            case work, nextRunWords = "next_run_words", nextRun = "next_run", health, unscheduled, finish, results
        }
        enum WorkKeys: String, CodingKey { case line, attention, status }
        enum FinishKeys: String, CodingKey { case taf, session, words }
        enum CardKeys: String, CodingKey { case cards }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kiffAgent = try c.decode(String.self, forKey: .kiffAgent)
            tafID = (try? c.decodeIfPresent(String.self, forKey: .tafID)) ?? nil
            // A Card that doesn't read is left out, never the taf.
            struct Lenient: Decodable { let card: TafCard?; init(from decoder: Decoder) throws { card = try? TafCard(from: decoder) } }
            let summary = try? c.nestedContainer(keyedBy: CardKeys.self, forKey: .card)
            cards = (summary.flatMap { (try? $0.decodeIfPresent([Lenient].self, forKey: .cards)) ?? nil } ?? []).compactMap(\.card)
            name = try c.decode(String.self, forKey: .name)
            state = try c.decode(String.self, forKey: .state)
            status = try c.decodeIfPresent(String.self, forKey: .status) ?? "active"
            color = ((try? c.decodeIfPresent(Int.self, forKey: .color)) ?? nil) ?? 0
            waiting = ((try? c.decodeIfPresent(Int.self, forKey: .waiting)) ?? nil) ?? 0
            func text(_ value: String?) -> String? {
                guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return value
            }
            jobSummary = text((try? c.decodeIfPresent(String.self, forKey: .jobSummary)) ?? nil)
            nextRunWords = text((try? c.decodeIfPresent(String.self, forKey: .nextRunWords)) ?? nil)
            let work = try? c.nestedContainer(keyedBy: WorkKeys.self, forKey: .work)
            workLine = text(work.flatMap { (try? $0.decodeIfPresent(String.self, forKey: .line)) ?? nil })
            attention = work.flatMap { (try? $0.decodeIfPresent(Bool.self, forKey: .attention)) ?? nil } ?? false
            health = (try? c.decodeIfPresent(Health.self, forKey: .health)) ?? nil
            nextRun = (try? c.decodeIfPresent(Date.self, forKey: .nextRun)) ?? nil
            unscheduled = ((try? c.decodeIfPresent(Bool.self, forKey: .unscheduled)) ?? nil) ?? false
            workStatus = text(work.flatMap { (try? $0.decodeIfPresent(String.self, forKey: .status)) ?? nil })
            // One the app can show: its chat and its words, as the iPad's `Finish.usable`.
            let finish = try? c.nestedContainer(keyedBy: FinishKeys.self, forKey: .finish)
            func part(_ key: FinishKeys) -> String? { text(finish.flatMap { (try? $0.decodeIfPresent(String.self, forKey: key)) ?? nil })?.trimmingCharacters(in: .whitespacesAndNewlines) }
            finishWords = part(.taf) != nil && part(.session) != nil ? part(.words) : nil
            results = (try? c.decodeIfPresent([JSONValue].self, forKey: .results)) ?? nil
        }

        /// What "now" says, by its state, as the iPad's `KIFFMapping.taf`: waiting for the
        /// person, paused, halted, working from its chat, its next run (tafs cloud's words, else
        /// the time), running, acting under KIFF, or its Card not active. A setup stopped
        /// partway says tafs cloud's words for that instead.
        func now(_ words: Words, time: (Date) -> String) -> String {
            if let finishWords { return finishWords }
            switch state {
            case "waiting": return words("taf.now.waiting_on_you")
            case "paused": return words("taf.state.paused")
            case "halted": return words("taf.now.halted")
            case "working" where unscheduled: return words("taf.now.works_from_chat")
            case "working": return nextRunWords ?? nextRun.map { words("taf.now.next_run", ["time": time($0)]) } ?? words("taf.now.running")
            case "idle": return words("taf.now.acting_under_kiff")
            default: return words("taf.now.card_not_active")
            }
        }

        /// What went wrong last, before its next run, in tafs cloud's work line: when it flags
        /// it (`attention`), or when an idle taf isn't healthy, as the iPad's `healthNow`. The
        /// sidebar's row shows it in place of "now".
        var healthNow: String? {
            guard let workLine, attention || (workStatus == "idle" && health?.needsAttention == true) else { return nil }
            return workLine
        }
        /// The first thing wrong with it, in tafs cloud's words.
        var trouble: String? { health.flatMap { $0.healthy ? nil : $0.lines.first } }
    }

    struct Page: Decodable, Equatable {
        let tafs: [Taf]
        /// Home's first line, counted by tafs cloud ("2 tafs working.").
        let headline: String?
        /// What waits for the person, counted once by tafs cloud so every screen agrees.
        let needsYouCount: Int?
        let needsYouWords: String?

        enum CodingKeys: String, CodingKey { case tafs, headline, needsYou = "needs_you" }
        enum WordsKeys: String, CodingKey { case words, count }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // The tafs are the page: one that doesn't read makes it unreadable.
            tafs = try c.decode([Taf].self, forKey: .tafs)
            let head = try? c.nestedContainer(keyedBy: WordsKeys.self, forKey: .headline)
            let line = head.flatMap { (try? $0.decodeIfPresent(String.self, forKey: .words)) ?? nil }
            headline = line.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            let needs = try? c.nestedContainer(keyedBy: WordsKeys.self, forKey: .needsYou)
            needsYouCount = needs.flatMap { (try? $0.decodeIfPresent(Int.self, forKey: .count)) ?? nil }
            needsYouWords = needs.flatMap { (try? $0.decodeIfPresent(String.self, forKey: .words)) ?? nil }
        }
    }
}

/// Home's part of the recipes (`GET /v1/recipes`): tafs cloud's line for an account with no
/// taf yet ("Pick a job for your first taf."), read by the contract fixture `recipes-home.json`.
struct HomeWords: Decodable, Equatable {
    /// Whether Home shows it.
    let shown: Bool
    let words: String?

    enum Keys: String, CodingKey { case home }
    enum HomeKeys: String, CodingKey { case shown, words }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let home = try? c.nestedContainer(keyedBy: HomeKeys.self, forKey: .home)
        shown = home.flatMap { (try? $0.decodeIfPresent(Bool.self, forKey: .shown)) ?? nil } ?? false
        let line = home.flatMap { (try? $0.decodeIfPresent(String.self, forKey: .words)) ?? nil }
        words = line.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    /// The line to draw: only when tafs cloud says Home shows it.
    var line: String? { shown ? words : nil }
}

extension CloudClient {
    /// tafs cloud's line for a Home with no taf.
    func homeWords() async throws -> HomeWords { try await get("/v1/recipes") }

    /// The app's list, as tafs cloud sends it.
    func home() async throws -> Home.Page { try await get("/v1/home") }
}

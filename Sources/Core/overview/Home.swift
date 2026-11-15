import Foundation

/// The app's list (`GET /v1/home`): each taf with where its work stands, as tafs cloud counts
/// and words it. The app counts nothing itself and draws the lines as sent.
enum Home {
    struct Taf: Decodable, Identifiable, Equatable {
        /// Its health, with tafs cloud's lines; absent when it couldn't be read in time.
        struct Health: Decodable, Equatable {
            let level: String
            let lines: [String]

            enum CodingKeys: String, CodingKey { case level, lines }
            init(level: String, lines: [String]) { self.level = level; self.lines = lines }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                level = ((try? c.decodeIfPresent(String.self, forKey: .level)) ?? nil) ?? "healthy"
                lines = ((try? c.decodeIfPresent([String].self, forKey: .lines)) ?? nil) ?? []
            }
            var healthy: Bool { level == "healthy" }
        }

        /// The KIFF agent it acts as: what tells one row from another.
        let kiffAgent: String
        let name: String
        /// Its colour, by its index in the palette.
        let color: Int
        /// working, paused, waiting, idle or stopped, as tafs cloud names it.
        let state: String
        /// Its calls held for the person.
        let waiting: Int
        /// What it does, in words.
        let jobSummary: String?
        /// Where its work stands, in tafs cloud's line.
        let workLine: String?
        /// Something went wrong last: the line is drawn as a warning.
        let attention: Bool
        /// Its next run, in tafs cloud's words ("Next run Mon 08:00").
        let nextRunWords: String?
        let health: Health?

        var id: String { kiffAgent }

        enum CodingKeys: String, CodingKey {
            case kiffAgent = "kiff_agent", name, color, state, waiting, jobSummary = "job_summary"
            case work, nextRunWords = "next_run_words", health
        }
        enum WorkKeys: String, CodingKey { case line, attention }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kiffAgent = try c.decode(String.self, forKey: .kiffAgent)
            name = try c.decode(String.self, forKey: .name)
            state = try c.decode(String.self, forKey: .state)
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
        }

        /// What "now" says: tafs cloud's line for its work, else its next run. Nil when it
        /// sent neither: the app writes no line of its own.
        var now: String? { workLine ?? nextRunWords }
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

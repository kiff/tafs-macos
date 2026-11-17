import Foundation

/// One taf's credits in a period, with its runs, newest first, as the iPad's `TafsCloud.TafCredits`
/// (`GET /v1/usage/credits/tafs/{id}`): every line is tafs cloud's `words`, drawn as sent. The app
/// counts nothing.
struct TafCredits: Decodable, Equatable {
    /// One run: tafs cloud's words for it, when it ended, and whether it counted.
    struct Run: Decodable, Equatable, Identifiable {
        let run: String
        /// When the run ended.
        let at: Date
        let credits: Int
        let counted: Bool
        /// Why it wasn't counted (`trial`, `failed`, `coach`); nil on a counted run.
        let why: String?
        let words: String
        /// Whether its row opens the run's request, while tafs cloud says it can.
        let opens: Bool
        var id: String { run }

        enum CodingKeys: String, CodingKey { case run, at, credits, counted, why, words, opens }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            run = try c.decode(String.self, forKey: .run)
            at = try c.decode(Date.self, forKey: .at)
            credits = try c.decode(Int.self, forKey: .credits)
            counted = try c.decode(Bool.self, forKey: .counted)
            why = (try? c.decodeIfPresent(String.self, forKey: .why)) ?? nil
            words = try c.decode(String.self, forKey: .words)
            opens = ((try? c.decodeIfPresent(Bool.self, forKey: .opens)) ?? nil) ?? false
        }
    }

    let credits: Int
    let runs: Int
    /// The taf's credits in the period, in tafs cloud's words.
    let words: String
    /// Its runs read so far, newest first. One that doesn't read is left out, never the page.
    private(set) var items: [Run]
    /// The cursor for the next runs; nil once there are no more.
    private(set) var next: String?

    enum CodingKeys: String, CodingKey { case credits, runs, words, items, next }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        credits = try c.decode(Int.self, forKey: .credits)
        runs = ((try? c.decodeIfPresent(Int.self, forKey: .runs)) ?? nil) ?? 0
        words = try c.decode(String.self, forKey: .words)
        struct Lenient: Decodable { let run: Run?; init(from decoder: Decoder) throws { run = try? Run(from: decoder) } }
        items = (((try? c.decodeIfPresent([Lenient].self, forKey: .items)) ?? nil) ?? []).compactMap(\.run)
        next = ((try? c.decodeIfPresent(String.self, forKey: .next)) ?? nil).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The next page's runs after the ones read, as the iPad's `readTafCredits(more:)`: a run
    /// already read isn't read twice, and the cursor is the newer page's.
    mutating func append(_ more: TafCredits) {
        let seen = Set(items.map(\.run))
        items += more.items.filter { !seen.contains($0.run) }
        next = more.next
    }
}

extension CloudClient {
    /// One taf's credits and its newest runs, this period or the one before; with `after`, the
    /// runs after that cursor. Nil from a tafs cloud without the read (404), which shows nothing.
    func tafCredits(of taf: String, previous: Bool = false, after: String? = nil) async throws -> TafCredits? {
        var query: [String] = []
        if previous { query.append("period=previous") }
        if let after { query.append("after=\(Self.query(after))") }
        do {
            return try await get("/v1/usage/credits/tafs/\(Self.escaped(taf))" + (query.isEmpty ? "" : "?" + query.joined(separator: "&")), saying: true)
        } catch let refusal as CloudRefusal where refusal.status == 404 {
            return nil
        }
    }
}

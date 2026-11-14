import Foundation

/// Plan and usage, as tafs cloud says them: the balance now, and the period's credits. The
/// app draws the words and the meter; it works out no amount itself.
enum Usage {
    /// The balance now (`GET /v1/usage/balance`).
    struct Balance: Decodable, Equatable {
        /// `ok`, `warning` or `waiting` (the tafs wait for credits, a limit or a plan).
        let state: String
        /// How much is used, 0 to 100, or nil where nothing bounds it.
        let meter: Int?
        let words: String
        let detail: String?
        let warning: String?
        /// The plan's line, and whether it needs the person.
        let planLine: String?

        enum Keys: String, CodingKey { case balance, planLine = "plan_line" }
        enum BalanceKeys: String, CodingKey { case state, meter = "meter_pct", words, detail, warning }

        init(from decoder: Decoder) throws {
            let root = try decoder.container(keyedBy: Keys.self)
            let c = try root.nestedContainer(keyedBy: BalanceKeys.self, forKey: .balance)
            state = try c.decode(String.self, forKey: .state)
            words = try c.decode(String.self, forKey: .words)
            // How much is used. Kept within 0 to 100, as the phones keep it; no number, no bar.
            let pct = (try? c.decodeIfPresent(Int.self, forKey: .meter)) ?? nil
            meter = pct.map { min(max($0, 0), 100) }
            detail = Usage.text((try? c.decodeIfPresent(String.self, forKey: .detail)) ?? nil)
            warning = Usage.text((try? c.decodeIfPresent(String.self, forKey: .warning)) ?? nil)
            planLine = Usage.text((try? root.decodeIfPresent(String.self, forKey: .planLine)) ?? nil)
        }

        var waiting: Bool { state == "waiting" }
    }

    /// The period's credits (`GET /v1/usage/credits`), with those of each taf that used some.
    struct Credits: Decodable, Equatable {
        struct Row: Decodable, Identifiable, Equatable {
            /// The taf's id; nil on the one row for the rest ("Removed tafs", "Other tafs").
            let taf: String?
            let words: String
            /// A second line, once its runs cover a week ("At this pace, about 640 this month").
            let pace: String?
            let position: Int

            var id: Int { position }
        }

        /// The period's total, in tafs cloud's words.
        let words: String
        let rows: [Row]
        /// Coach's own use, once past what's included.
        let coach: String?
        /// What wasn't counted (trials, failed runs), in words.
        let notCounted: String?
        let note: String?

        enum Keys: String, CodingKey { case words, tafs, coach, notCounted = "not_counted", note }
        enum RowKeys: String, CodingKey { case taf, words, pace }
        enum WordsKeys: String, CodingKey { case words }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            words = try c.decode(String.self, forKey: .words)
            var list = try c.nestedUnkeyedContainer(forKey: .tafs)
            var rows: [Row] = []
            while !list.isAtEnd {
                // A row that doesn't read is left out, never the period.
                guard let row = try? list.nestedContainer(keyedBy: RowKeys.self) else { _ = try? list.decode(Skipped.self); continue }
                guard let words = Usage.text((try? row.decodeIfPresent(String.self, forKey: .words)) ?? nil) else { continue }
                rows.append(Row(taf: (try? row.decodeIfPresent(String.self, forKey: .taf)) ?? nil, words: words,
                                pace: Usage.text((try? row.decodeIfPresent(String.self, forKey: .pace)) ?? nil), position: rows.count))
            }
            self.rows = rows
            func nested(_ key: Keys) -> String? {
                guard let inner = try? c.nestedContainer(keyedBy: WordsKeys.self, forKey: key) else { return nil }
                return Usage.text((try? inner.decodeIfPresent(String.self, forKey: .words)) ?? nil)
            }
            coach = nested(.coach)
            notCounted = nested(.notCounted)
            note = Usage.text((try? c.decodeIfPresent(String.self, forKey: .note)) ?? nil)
        }

        private struct Skipped: Decodable {}
    }

    static func text(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}

extension CloudClient {
    func balance() async throws -> Usage.Balance { try await get("/v1/usage/balance") }

    /// This period's credits, or the one before.
    func credits(previous: Bool = false) async throws -> Usage.Credits {
        try await get(previous ? "/v1/usage/credits?period=previous" : "/v1/usage/credits")
    }
}

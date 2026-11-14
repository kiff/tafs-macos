import Foundation

/// The Record across the person's tafs (`GET /v1/record`): every call, newest first, found
/// by what it is about, its action or its amount. Every word on it is tafs cloud's.
enum Record {
    /// One call in the Record, as its taf's Activity words it.
    struct Entry: Decodable, Identifiable, Equatable {
        struct Taf: Decodable, Equatable {
            let id: String
            let name: String

            enum CodingKeys: String, CodingKey { case id, name }
            init(id: String, name: String) { self.id = id; self.name = name }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try c.decode(String.self, forKey: .id)
                name = ((try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? ""
            }
        }

        let id: String
        let at: Date
        /// How it went, as tafs cloud names it: done, held, refused…
        let kind: String
        let title: String
        let detail: String
        /// When, in the person's language and zone, as sent.
        let time: String
        /// The money it moved, as sent ("€150.00"); nil when it moved none.
        let amountText: String?
        let taf: Taf
        /// What the call is about, the taf's business reference ("Order 1042"): it opens the case.
        let about: String?

        enum CodingKeys: String, CodingKey { case id, at, kind, title, detail, time, amountText = "amount_text", taf, about }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            at = try c.decode(Date.self, forKey: .at)
            kind = try c.decode(String.self, forKey: .kind)
            title = try c.decode(String.self, forKey: .title)
            detail = try c.decode(String.self, forKey: .detail)
            time = try c.decode(String.self, forKey: .time)
            taf = try c.decode(Taf.self, forKey: .taf)
            func text(_ key: CodingKeys) -> String? {
                guard let value = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil else { return nil }
                return value.trimmingCharacters(in: .whitespaces).isEmpty ? nil : value
            }
            amountText = text(.amountText)
            about = text(.about)
        }
    }

    struct Group: Decodable, Identifiable, Equatable {
        let id: String
        let title: String
        let entries: [Entry]

        enum CodingKeys: String, CodingKey { case id, title, entries }
        init(id: String, title: String, entries: [Entry]) { self.id = id; self.title = title; self.entries = entries }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = ((try? c.decodeIfPresent(String.self, forKey: .title)) ?? nil) ?? ""
            entries = try c.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        }
    }

    /// One page of a search. The search box's words (`hint`), "nothing matched" and the
    /// end's words are tafs cloud's.
    struct Page: Decodable, Equatable {
        let hint: String
        let entries: [Entry]
        let groups: [Group]
        let nextCursor: String?
        let endWords: String?
        let noneWords: String?

        enum CodingKeys: String, CodingKey { case hint, entries, groups, nextCursor = "next_cursor", endWords = "end_words", noneWords = "none_words" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            hint = ((try? c.decodeIfPresent(String.self, forKey: .hint)) ?? nil) ?? ""
            // The entries are the page: one that doesn't read makes the page unreadable.
            entries = try c.decode([Entry].self, forKey: .entries)
            groups = try c.decodeIfPresent([Group].self, forKey: .groups) ?? []
            nextCursor = (try? c.decodeIfPresent(String.self, forKey: .nextCursor)) ?? nil
            endWords = (try? c.decodeIfPresent(String.self, forKey: .endWords)) ?? nil
            noneWords = (try? c.decodeIfPresent(String.self, forKey: .noneWords)) ?? nil
        }

        /// tafs cloud's groups, or every entry as one group when it sent none.
        var shown: [Group] {
            groups.isEmpty && !entries.isEmpty ? [Group(id: "all", title: "", entries: entries)] : groups
        }
        var isEmpty: Bool { entries.isEmpty && groups.allSatisfy { $0.entries.isEmpty } }
    }

    /// One case: every call about the same thing, oldest first.
    struct Case: Decodable, Equatable {
        struct Failed: Decodable, Equatable { let id: String; let words: String? }
        let about: String
        let steps: [Entry]
        /// The latest step that didn't go through, in tafs cloud's words.
        let failed: Failed?

        enum CodingKeys: String, CodingKey { case about, steps, failed }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            about = try c.decode(String.self, forKey: .about)
            steps = try c.decodeIfPresent([Entry].self, forKey: .steps) ?? []
            failed = (try? c.decodeIfPresent(Failed.self, forKey: .failed)) ?? nil
        }
    }

    /// The Record's filters, the iPad's: each keeps the calls of some kinds.
    enum Filter: String, CaseIterable, Identifiable {
        case all, moneyMoved, stopped, waiting

        var id: String { rawValue }

        /// The shared key of its name.
        var titleKey: String {
            switch self {
            case .all: return "record.filter.all"
            case .moneyMoved: return "record.filter.money_moved"
            case .stopped: return "record.filter.stopped"
            case .waiting: return "record.filter.waiting"
            }
        }

        func keeps(_ entry: Entry) -> Bool {
            switch self {
            case .all: return true
            case .moneyMoved: return entry.amountText != nil && ["done", "approved"].contains(entry.kind)
            case .stopped: return ["refused", "not_done", "revoked"].contains(entry.kind)
            case .waiting: return ["held", "sending", "unknown"].contains(entry.kind)
            }
        }

        /// The groups with only the calls it keeps; a group left with none is left out.
        func keeping(_ groups: [Group]) -> [Group] {
            guard self != .all else { return groups }
            return groups.compactMap { group in
                let kept = group.entries.filter(keeps)
                return kept.isEmpty ? nil : Group(id: group.id, title: group.title, entries: kept)
            }
        }
    }

    /// The longest search tafs cloud takes.
    static let longestSearch = 100
}

extension CloudClient {
    /// The Record searched by `q` (an order, an invoice, an amount or an action); `cursor`
    /// continues the same search.
    func record(_ q: String = "", cursor: String? = nil) async throws -> Record.Page {
        var query = ["q=\(Self.query(String(q.prefix(Record.longestSearch))))"]
        if let cursor { query.append("cursor=\(Self.query(cursor))") }
        return try await get("/v1/record?" + query.joined(separator: "&"))
    }

    /// One case: every call about `about`. A 404 says no call of the person's is about it.
    func recordCase(_ about: String) async throws -> Record.Case {
        try await get("/v1/record/cases/\(Self.query(about))")
    }
}

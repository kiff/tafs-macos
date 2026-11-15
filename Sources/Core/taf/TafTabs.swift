import Foundation

/// A taf's Activity (`GET /v1/tafs/{id}/activity`), ready to draw as tafs cloud sends it: its
/// calls by day, its filters, and its line for the end. The app words nothing here.
struct TafActivity: Decodable, Equatable {
    struct Entry: Decodable, Identifiable, Equatable {
        enum Tone: Equatable { case ok, amber, no }

        let id: String
        /// tafs cloud's kind: `done`, `approved`, `held`, `refused`, `not_done`, `sending` or `unknown`.
        let kind: String
        let title: String
        let detail: String?
        let time: String?
        /// The call's amount in tafs cloud's own words, drawn under the time; never built here.
        let amountText: String?

        enum CodingKeys: String, CodingKey { case id, kind, title, detail, time, amountText = "amount_text" }

        /// Its dot's colour, as the iPad's `RecordEntry.Kind.color`: done and approved green;
        /// refused, not done and revoked red; held, sending, and any other kind (read as
        /// unknown) amber.
        var tone: Tone {
            switch kind {
            case "done", "approved": return .ok
            case "refused", "not_done", "revoked": return .no
            default: return .amber
            }
        }
    }

    struct Group: Identifiable, Equatable {
        let id: String
        let title: String
        let entries: [Entry]
    }

    struct Filter: Decodable, Identifiable, Equatable {
        let id: String
        let title: String
    }

    private(set) var groups: [Group]
    let filters: [Filter]
    /// The filter this page is for.
    let filter: String
    /// What the app sends back as `If-None-Match` to ask whether anything changed.
    let revision: String?
    /// tafs cloud's line under the last call ("Nothing older in this view"), on the last page only.
    private(set) var endWords: String?
    /// The next page's cursor, while tafs cloud has more calls than this page holds.
    private(set) var nextCursor: String?
    let exceptions: [CardUnitException]

    enum Keys: String, CodingKey {
        case entries, groups, filters, filter, revision, endWords = "end_words", nextCursor = "next_cursor", exceptions = "card_unit_exceptions"
    }
    enum GroupKeys: String, CodingKey { case id, title, entries }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        // The calls must be there, by day or as one list: an answer with neither is unreadable.
        var groups: [Group] = []
        if var list = try? c.nestedUnkeyedContainer(forKey: .groups) {
            while !list.isAtEnd {
                guard let g = try? list.nestedContainer(keyedBy: GroupKeys.self) else { _ = try? list.decode(Skipped.self); continue }
                guard let id = try? g.decode(String.self, forKey: .id) else { continue }
                let entries = ((try? g.decodeIfPresent([Lenient<Entry>].self, forKey: .entries)) ?? nil)?.compactMap(\.value) ?? []
                guard !entries.isEmpty else { continue }
                groups.append(Group(id: id, title: Lines.line((try? g.decodeIfPresent(String.self, forKey: .title)) ?? nil) ?? "", entries: entries))
            }
        } else {
            let entries = try c.decode([Lenient<Entry>].self, forKey: .entries).compactMap(\.value)
            if !entries.isEmpty { groups = [Group(id: "all", title: "", entries: entries)] }
        }
        self.groups = groups
        filters = ((try? c.decodeIfPresent([Lenient<Filter>].self, forKey: .filters)) ?? nil)?.compactMap(\.value) ?? []
        filter = ((try? c.decodeIfPresent(String.self, forKey: .filter)) ?? nil) ?? "all"
        revision = (try? c.decodeIfPresent(String.self, forKey: .revision)) ?? nil
        endWords = Lines.line((try? c.decodeIfPresent(String.self, forKey: .endWords)) ?? nil)
        nextCursor = Lines.line((try? c.decodeIfPresent(String.self, forKey: .nextCursor)) ?? nil)
        exceptions = ((try? c.decodeIfPresent([Lenient<CardUnitException>].self, forKey: .exceptions)) ?? nil)?.compactMap(\.value) ?? []
    }

    /// The next page after this one, as the iPad adds it: a first day with no title carries on
    /// the last day here; a call already listed isn't listed twice; the end and the cursor are
    /// the new page's.
    mutating func append(_ next: TafActivity) {
        var listed = Set(groups.flatMap { $0.entries.map(\.id) })
        var rest = next.groups
        if let first = rest.first, first.title.isEmpty, let last = groups.last {
            let more = first.entries.filter { !listed.contains($0.id) }
            groups[groups.count - 1] = Group(id: last.id, title: last.title, entries: last.entries + more)
            more.forEach { listed.insert($0.id) }
            rest.removeFirst()
        }
        for group in rest {
            let entries = group.entries.filter { !listed.contains($0.id) }
            entries.forEach { listed.insert($0.id) }
            if !entries.isEmpty { groups.append(Group(id: group.id, title: group.title, entries: entries)) }
        }
        endWords = next.endWords
        nextCursor = next.nextCursor
    }

    private struct Skipped: Decodable {}
}

/// A taf's Setup (`GET /v1/tafs/{id}/setup`), for someone who manages it, as tafs cloud sends
/// it: each part's title and its line, ready to draw.
struct TafSetup: Decodable, Equatable {
    /// A part of the Setup: tafs cloud's title for it and its one line.
    struct Part: Equatable {
        let title: String
        let summary: String?
    }

    let workflow: Part?
    let memory: Part?
    let versions: Part?
    /// tafs cloud's line when the connections couldn't be read.
    let connectionsError: String?
    let exceptions: [CardUnitException]

    enum Keys: String, CodingKey { case workflow, memory, versions, connections, connectionsError = "connections_error", exceptions = "card_unit_exceptions" }
    enum PartKeys: String, CodingKey { case title, summary, latest }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        // Each part's title and its line; the notes' line is the latest note (`latest`), as the
        // iPad's `MemorySummaryPanel` draws it.
        func part(_ key: Keys, line: PartKeys = .summary) -> Part? {
            guard let p = try? c.nestedContainer(keyedBy: PartKeys.self, forKey: key),
                  let title = Lines.line((try? p.decodeIfPresent(String.self, forKey: .title)) ?? nil) else { return nil }
            return Part(title: title, summary: Lines.line((try? p.decodeIfPresent(String.self, forKey: line)) ?? nil))
        }
        workflow = part(.workflow)
        memory = part(.memory, line: .latest)
        versions = part(.versions)
        connectionsError = Lines.line((try? c.decodeIfPresent(String.self, forKey: .connectionsError)) ?? nil)
        exceptions = ((try? c.decodeIfPresent([Lenient<CardUnitException>].self, forKey: .exceptions)) ?? nil)?.compactMap(\.value) ?? []
        // A Setup with none of its parts isn't one.
        guard workflow != nil || memory != nil || versions != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "no part of a Setup"))
        }
    }
}

/// A call refused because its amount is in a unit the Card has no limit for: tafs cloud's
/// title and words for it, as Home and the Setup show it.
struct CardUnitException: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let words: String?
    let history: String?
}

/// Reads one item of a list, or nothing: an item that doesn't read is left out, never the list.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

private enum Lines {
    /// tafs cloud's line, or nil when it sent none or only spaces.
    static func line(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}

extension CloudClient {
    /// A taf's Activity, for one of tafs cloud's filters; the next page with its cursor.
    func activity(of taf: String, filter: String = "all", cursor: String? = nil) async throws -> TafActivity {
        let more = cursor.map { "&cursor=\(Self.query($0))" } ?? ""
        return try await get("/v1/tafs/\(Self.query(taf))/activity?filter=\(Self.query(filter))\(more)")
    }

    /// A taf's Setup.
    func setup(of taf: String) async throws -> TafSetup {
        try await get("/v1/tafs/\(Self.query(taf))/setup")
    }
}

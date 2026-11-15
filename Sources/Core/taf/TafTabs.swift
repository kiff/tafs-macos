import Foundation

/// A taf's Activity (`GET /v1/tafs/{id}/activity`), ready to draw as tafs cloud sends it: its
/// calls by day, its filters, and its line for the end. The app words nothing here.
struct TafActivity: Decodable, Equatable {
    struct Entry: Decodable, Identifiable, Equatable {
        let id: String
        /// `done`, `held`, `refused`, or a kind this app doesn't know (drawn without a colour).
        let kind: String
        let title: String
        let detail: String?
        let time: String?
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

    let groups: [Group]
    let filters: [Filter]
    /// The filter this page is for.
    let filter: String
    /// What the app sends back as `If-None-Match` to ask whether anything changed.
    let revision: String?
    /// tafs cloud's line under the last call ("Nothing older in this view").
    let endWords: String?
    let exceptions: [CardUnitException]

    enum Keys: String, CodingKey { case entries, groups, filters, filter, revision, endWords = "end_words", exceptions = "card_unit_exceptions" }
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
        exceptions = ((try? c.decodeIfPresent([Lenient<CardUnitException>].self, forKey: .exceptions)) ?? nil)?.compactMap(\.value) ?? []
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
    /// How many earlier versions tafs cloud keeps.
    let earlierVersions: Int
    /// How many connections tafs cloud listed.
    let connections: Int
    /// tafs cloud's line when the connections couldn't be read.
    let connectionsError: String?
    let exceptions: [CardUnitException]

    enum Keys: String, CodingKey { case workflow, memory, versions, connections, connectionsError = "connections_error", exceptions = "card_unit_exceptions" }
    enum PartKeys: String, CodingKey { case title, summary, earlier }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        func part(_ key: Keys) -> Part? {
            guard let p = try? c.nestedContainer(keyedBy: PartKeys.self, forKey: key),
                  let title = Lines.line((try? p.decodeIfPresent(String.self, forKey: .title)) ?? nil) else { return nil }
            return Part(title: title, summary: Lines.line((try? p.decodeIfPresent(String.self, forKey: .summary)) ?? nil))
        }
        workflow = part(.workflow)
        memory = part(.memory)
        versions = part(.versions)
        let v = try? c.nestedContainer(keyedBy: PartKeys.self, forKey: .versions)
        earlierVersions = (v.flatMap { (try? $0.decodeIfPresent(Int.self, forKey: .earlier)) ?? nil }) ?? 0
        struct Listed: Decodable {}
        connections = ((try? c.decodeIfPresent([Lenient<Listed>].self, forKey: .connections)) ?? nil)?.count ?? 0
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
    /// A taf's Activity, for one of tafs cloud's filters.
    func activity(of taf: String, filter: String = "all") async throws -> TafActivity {
        try await get("/v1/tafs/\(Self.query(taf))/activity?filter=\(Self.query(filter))")
    }

    /// A taf's Setup.
    func setup(of taf: String) async throws -> TafSetup {
        try await get("/v1/tafs/\(Self.query(taf))/setup")
    }
}

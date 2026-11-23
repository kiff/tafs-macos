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
        /// A not-done call's next step, in tafs cloud's words (kiff/tafs#476, gap 10); nil for none, or one that doesn't read.
        var next: NextStep?
        /// The call as the Record reads it, with KIFF's `call`, for its sheet (the iPad's `SourceActivityRow.evidence`): its
        /// receipt, who answered and what became of it. Read with no taf (`Record.Entry.on` names it); nil when it doesn't
        /// read as a Record line, which leaves the row as it is.
        var record: Record.Entry?

        enum CodingKeys: String, CodingKey { case id, kind, title, detail, time, next, amountText = "amount_text" }

        init(id: String, kind: String, title: String, detail: String?, time: String?, amountText: String?, next: NextStep? = nil,
             record: Record.Entry? = nil) {
            self.id = id; self.kind = kind; self.title = title; self.detail = detail; self.time = time
            self.amountText = amountText; self.next = next; self.record = record
        }

        /// The call's sheet opens from its row whenever KIFF's call names its taf (the iPad's `evidence`, which needs the
        /// call's `actor_id`), receipt or not, as the Record's own Activity rows (`RecordStepRow`).
        func sheet(on taf: Record.Entry.Taf) -> Record.Entry? {
            guard let record, record.hasActor else { return nil }
            return record.on(taf)
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            kind = try c.decode(String.self, forKey: .kind)
            title = try c.decode(String.self, forKey: .title)
            detail = try c.decodeIfPresent(String.self, forKey: .detail)
            time = try c.decodeIfPresent(String.self, forKey: .time)
            amountText = try c.decodeIfPresent(String.self, forKey: .amountText)
            // A next step that doesn't read is none, never the row with it.
            next = (try? c.decodeIfPresent(NextStep.self, forKey: .next)) ?? nil
            // The same entry, as the Record reads a line: one that doesn't read is no sheet, never the row.
            record = try? Record.Entry.activity(decoder, taf: Record.Entry.Taf(id: "", name: ""))
        }

        /// What a not-done call's next step is, as tafs cloud says it: its kind, its words, and for Ask Coach its message.
        struct NextStep: Decodable, Equatable {
            let kind: String
            let words: String
            var tool: String?
            var message: String?

            /// What it does on this Mac, as the iPad's `NextStepWords.action`. A `reconnect` is Connect apps: signing in
            /// again is the phone's on macOS 12, and Connect apps says so where it would be. `ask_coach` is Coach on the taf
            /// with tafs cloud's message, else `fallback`, in its box. Any other kind is its words alone.
            enum Action: Equatable {
                case connectApps
                case askCoach(String)
                case line
            }

            func action(fallback: String) -> Action {
                switch kind {
                case "reconnect": return .connectApps
                case "ask_coach":
                    let said = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return .askCoach(said.isEmpty ? fallback : said)
                default: return .line
                }
            }
        }

        /// Its dot's colour, as the iPad's `RecordEntry.Kind.color`: done and approved green;
        /// refused, not done and revoked red; held, sending, and any other kind (read as
        /// unknown) amber.
        var tone: Tone { Self.tone(of: kind) }

        /// A kind's colour, for any of tafs cloud's calls: a taf's Activity and the Record.
        static func tone(of kind: String) -> Tone {
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

    struct WorkflowStep: Decodable, Equatable {
        let number: Int
        let label: String
        let words: String
        let app: String?
        let running: Bool

        enum CodingKeys: String, CodingKey { case number, label, words, app, running }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            number = try c.decode(Int.self, forKey: .number)
            label = try c.decode(String.self, forKey: .label)
            guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .label, in: c, debugDescription: "a step with no label")
            }
            words = ((try? c.decodeIfPresent(String.self, forKey: .words)) ?? nil) ?? ""
            app = ((try? c.decodeIfPresent(String.self, forKey: .app)) ?? nil).flatMap { $0.isEmpty ? nil : $0 }
            running = ((try? c.decodeIfPresent(Bool.self, forKey: .running)) ?? nil) ?? false
        }
    }

    let workflow: Part?
    /// Its workflow's steps, in tafs cloud's order and words, as the iPad's `WorkflowStep`: each one's number, label,
    /// words, the app it uses, and whether it runs now. Empty when it has none yet; a step that doesn't read is left out.
    let workflowSteps: [WorkflowStep]
    let memory: Part?
    let versions: Part?
    /// Its versions counted, as tafs cloud counts them (`versions.live`, `versions.earlier`): the
    /// live one's number, nil while it runs its first definition, and how many came before it. The
    /// app draws tafs cloud's `title` and `summary`, never words of its own from these.
    let versionsLive: Int?
    let versionsEarlier: Int?
    /// The apps the taf is connected to, as tafs cloud words them.
    let connections: [Connection]
    /// tafs cloud's words when the taf's own sign-in expired and it must connect again.
    let connectAgain: ConnectAgain?
    /// tafs cloud's line when the connections couldn't be read.
    let connectionsError: String?
    let exceptions: [CardUnitException]

    /// One connected app: its name, tafs cloud's words for its status, its actions with their
    /// limits, and its week in words. `reconnect` when its sign-in must be done again.
    struct Connection: Decodable, Identifiable, Equatable {
        struct Action: Decodable, Equatable {
            let title: String
            let limits: [String]
            /// Which steps of its workflow use it, in tafs cloud's words.
            let stepWords: String?

            enum Keys: String, CodingKey { case title, limits, stepWords = "step_words" }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: Keys.self)
                title = try c.decode(String.self, forKey: .title)
                limits = (((try? c.decodeIfPresent([String].self, forKey: .limits)) ?? nil) ?? []).compactMap(Lines.line)
                stepWords = Lines.line((try? c.decodeIfPresent(String.self, forKey: .stepWords)) ?? nil)
            }
        }

        let id: String
        let name: String
        let statusWords: String?
        let reconnect: Bool
        let actionWords: String?
        let actions: [Action]
        /// How many of its actions the taf may take: the app's node is the connection with some.
        let actionCount: Int
        /// The taf is using it now: its words are green.
        let running: Bool
        let statsWords: String?
        /// The taf's Activity for this app's calls, as tafs cloud writes the query.
        let activityQuery: String?

        enum Keys: String, CodingKey {
            case id, name, statusWords = "status_words", reconnect, actionWords = "action_words", actions, stats
            case actionCount = "action_count", running
        }
        enum StatsKeys: String, CodingKey { case words, activityQuery = "activity_query" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            statusWords = Lines.line((try? c.decodeIfPresent(String.self, forKey: .statusWords)) ?? nil)
            reconnect = ((try? c.decodeIfPresent(Bool.self, forKey: .reconnect)) ?? nil) ?? false
            actionWords = Lines.line((try? c.decodeIfPresent(String.self, forKey: .actionWords)) ?? nil)
            actions = ((try? c.decodeIfPresent([Lenient<Action>].self, forKey: .actions)) ?? nil)?.compactMap(\.value) ?? []
            actionCount = ((try? c.decodeIfPresent(Int.self, forKey: .actionCount)) ?? nil) ?? actions.count
            running = ((try? c.decodeIfPresent(Bool.self, forKey: .running)) ?? nil) ?? false
            let stats = try? c.nestedContainer(keyedBy: StatsKeys.self, forKey: .stats)
            statsWords = Lines.line(stats.flatMap { (try? $0.decodeIfPresent(String.self, forKey: .words)) ?? nil })
            activityQuery = Lines.line(stats.flatMap { (try? $0.decodeIfPresent(String.self, forKey: .activityQuery)) ?? nil })
        }
    }

    /// One app on the taf, as the iPad's `ConnectedToolsRing.Node`: the connection that does the
    /// work, with any other sign-in to the same app inside its sheet.
    struct Node: Identifiable, Equatable {
        let app: Connection
        let others: [Connection]
        var id: String { app.id }
    }

    /// One node per app, in tafs cloud's order of each app's first connection, as the iPad's
    /// `nodes`: the one shown is the first with actions, else one to sign in again, else the
    /// first. Two "Stripe" rows would read as two Stripes.
    static func nodes(_ apps: [Connection]) -> [Node] {
        var order: [String] = []
        var byName: [String: [Connection]] = [:]
        for app in apps {
            if byName[app.name] == nil { order.append(app.name) }
            byName[app.name, default: []].append(app)
        }
        return order.compactMap { name in
            guard let all = byName[name], let first = all.first else { return nil }
            let main = all.first { $0.actionCount > 0 } ?? all.first { $0.reconnect } ?? first
            return Node(app: main, others: all.filter { $0.id != main.id })
        }
    }

    /// Connect again, as the iPad's `TafsCloud.ConnectAgain`: the connection to sign in again (`grant`), tafs cloud's
    /// words for it and its button's title, each trimmed.
    struct ConnectAgain: Decodable, Equatable {
        let grant: String
        let title: String
        let words: String?

        init(grant: String, title: String, words: String?) {
            self.grant = grant
            self.title = title
            self.words = words
        }

        /// Drawn only with a connection, a title and words, as the iPad's `usable`.
        var usable: Bool { !grant.isEmpty && !title.isEmpty && !(words ?? "").isEmpty }

        enum Keys: String, CodingKey { case grant, title, words }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            func text(_ key: Keys) -> String {
                (((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            grant = text(.grant)
            title = text(.title)
            let said = text(.words)
            words = said.isEmpty ? nil : said
        }
    }

    enum Keys: String, CodingKey {
        case workflow, memory, versions, connections, connectionsError = "connections_error", exceptions = "card_unit_exceptions"
        case connectAgain = "connect_again"
    }
    enum PartKeys: String, CodingKey { case title, summary, latest, live, earlier, steps }

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
        let steps = try? c.nestedContainer(keyedBy: PartKeys.self, forKey: .workflow)
        workflowSteps = ((steps.flatMap { try? $0.decodeIfPresent([Lenient<WorkflowStep>].self, forKey: .steps) } ?? nil) ?? []).compactMap(\.value)
        memory = part(.memory, line: .latest)
        versions = part(.versions)
        let counted = try? c.nestedContainer(keyedBy: PartKeys.self, forKey: .versions)
        versionsLive = counted.flatMap { (try? $0.decodeIfPresent(Int.self, forKey: .live)) ?? nil }
        versionsEarlier = counted.flatMap { (try? $0.decodeIfPresent(Int.self, forKey: .earlier)) ?? nil }
        connections = ((try? c.decodeIfPresent([Lenient<Connection>].self, forKey: .connections)) ?? nil)?.compactMap(\.value) ?? []
        connectAgain = (try? c.decodeIfPresent(ConnectAgain.self, forKey: .connectAgain)) ?? nil
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
    /// A taf's Activity, for one of tafs cloud's filters, or for tafs cloud's own query (an
    /// app's calls, from its Setup); the next page with its cursor.
    func activity(of taf: String, filter: String = "all", query: String? = nil, cursor: String? = nil) async throws -> TafActivity {
        let more = cursor.map { "&cursor=\(Self.query($0))" } ?? ""
        let asked = query.flatMap(Self.activityQuery) ?? "filter=\(Self.query(filter))"
        return try await get("/v1/tafs/\(Self.escaped(taf))/activity?\(asked)\(more)")
    }

    /// tafs cloud's query for an app's calls, sent as it wrote it, but only as a query: names
    /// and values of letters, digits and `%._-:`, joined by `=` and `&`. Anything else is none.
    static func activityQuery(_ query: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "%._-:=&"))
        guard !query.isEmpty, query.count <= 500, query.unicodeScalars.allSatisfy({ $0.isASCII && allowed.contains($0) }) else { return nil }
        return query
    }

    /// A taf's Setup, as the iPad's `setupView(_:proof:)`: with this device's planque proof
    /// (`Planque-Device-Signature`) when there is one, so it can list the taf's connected apps.
    func setup(of taf: String, proof: String? = nil) async throws -> TafSetup {
        try await get("/v1/tafs/\(Self.escaped(taf))/setup", headers: proof.map { ["Planque-Device-Signature": $0] } ?? [:])
    }
}

import Foundation

/// A chat with Coach or a taf, as tafs cloud orders it (`GET /v1/tafs/{id}/conversation`):
/// one list of messages, cards and held calls by time. The app draws the list as it comes,
/// and places or folds nothing itself.
enum Thread {
    struct Message: Equatable {
        /// tafs cloud's id for it, when it sends one.
        let id: String?
        let at: Date?
        /// `owner` (the person) or `taf`.
        let from: String
        /// `kickoff` (a job's instruction, shown as a small note) or `message`.
        let kind: String
        let text: String
        /// What the run did before these words: how long it worked, and its steps.
        var work: Work?

        var fromPerson: Bool { from == "owner" }
        var isNote: Bool { kind == "kickoff" }
    }

    /// A run's work, on its first message: the time from its start to its last words, and the
    /// steps it took, in tafs cloud's words. A step with no words isn't shown; its tool's name
    /// never is.
    struct Work: Equatable {
        struct Step: Equatable {
            let words: String
            let failed: Bool
            /// tafs cloud's one line of why it failed.
            let why: String?
            /// Refused back unmade: nothing reached KIFF or the app, so it isn't a failure.
            let notMade: Bool
        }
        let ms: Int
        let steps: [Step]

        /// "32 s", "4 min": how long it worked, to the second under two minutes.
        var took: String {
            let seconds = max(1, Int((Double(ms) / 1000).rounded()))
            return seconds < 120 ? "\(seconds) s" : "\(seconds / 60) min"
        }
    }

    /// A card Coach or a taf showed. The run pauses on one that waits, and its answer goes
    /// back as data, never as text in the chat.
    struct Card: Equatable {
        struct Option: Equatable {
            let label: String
            let value: String
        }
        /// Unique in the thread: a card is known by it, never only by the name the model gave it.
        let key: String
        /// The name the model gave it: what an answer is sent to.
        let id: String
        /// `confirm`, `questions`, `approval`, `sign_in`, or a kind that only shows something.
        let type: String
        /// The chat it is in.
        let session: String?
        let title: String?
        let text: String?
        let options: [Option]
        /// `owner` when its run waits on the person; `service` when tafs cloud answers it.
        let waits: String?
        /// What was answered, in tafs cloud's words, once it was.
        let answered: String?
        /// A plan's steps (`steps`): each with its label and whether it is done.
        var plan: [PlanStep] = []
        /// `info`, `success`, `warning` or `error`, for a notice.
        var tone: String?
        /// The taf a hand-over (`result`) made: its name, and its id at tafs cloud.
        var tafName: String?
        var tafID: String?
        /// The tools a hand-over lists, in KIFF's words for them.
        var tools: [String] = []
        /// On an approval whose connection is already made: tafs cloud's line for it.
        var connectionWords: String?

        struct PlanStep: Equatable {
            let label: String
            /// pending, active, done, failed or skipped.
            let status: String
        }

        var isPlan: Bool { type == "steps" && !plan.isEmpty }
        var isHandOver: Bool { type == "result" && tafName != nil }
        var planDone: Int { plan.filter { $0.status == "done" }.count }

        var waitsForPerson: Bool { waits == "owner" && answered == nil }
        /// A choice between a few answers, which grants nothing: the only kind answered here.
        var isChoice: Bool { type == "confirm" && !options.isEmpty }
        /// A card whose answer is a signature: approving a connection or a Card.
        var grants: Bool { type == "approval" || type == "sign_in" }
    }

    enum Item: Identifiable, Equatable {
        case message(Message, position: Int)
        /// A card that waits for an answer (`owner`), or that tafs cloud answers (`service`).
        case card(Card, position: Int)
        /// A call KIFF held, at the point it was held. Only KIFF's keys: it is answered in Needs you.
        case held(exception: String, position: Int)
        /// Something this app doesn't draw yet (a drive's end, a kind it doesn't know).
        case other(type: String, position: Int)

        var id: Int {
            switch self {
            case .message(_, let p), .card(_, let p), .held(_, let p), .other(_, let p): return p
            }
        }
    }

    struct Page: Decodable, Equatable {
        let items: [Item]
        /// The taf is at work in this chat.
        let working: Bool

        enum Keys: String, CodingKey { case items, working }
        enum ItemKeys: String, CodingKey { case type, message, card, held }
        enum MessageKeys: String, CodingKey { case id, at, from, kind, text, work }
        enum CardKeys: String, CodingKey { case key, id, type, session, title, text, options, waits, answer, steps, tone, taf, tools, connection, tafID = "taf_id" }
        enum PlanKeys: String, CodingKey { case label, status }
        enum TafKeys: String, CodingKey { case name }
        enum ConnectionKeys: String, CodingKey { case done, words }
        enum WorkKeys: String, CodingKey { case ms, steps }
        enum WorkStepKeys: String, CodingKey { case words, failed, error, why, notMade = "not_made" }
        enum OptionKeys: String, CodingKey { case label, value }
        enum AnswerKeys: String, CodingKey { case words, state }
        enum HeldKeys: String, CodingKey { case exception }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            working = ((try? c.decodeIfPresent(Bool.self, forKey: .working)) ?? nil) ?? false
            // The ordered list must be there: an answer without it is unreadable.
            var list = try c.nestedUnkeyedContainer(forKey: .items)
            var items: [Item] = []
            while !list.isAtEnd {
                let position = items.count
                guard let item = try? list.nestedContainer(keyedBy: ItemKeys.self) else { _ = try? list.decode(Skipped.self); continue }
                let type = ((try? item.decodeIfPresent(String.self, forKey: .type)) ?? nil) ?? ""
                switch type {
                case "message":
                    guard let m = try? item.nestedContainer(keyedBy: MessageKeys.self, forKey: .message),
                          let from = try? m.decode(String.self, forKey: .from),
                          let text = try? m.decode(String.self, forKey: .text) else { continue }
                    let at = ((try? m.decodeIfPresent(String.self, forKey: .at)) ?? nil).flatMap(Thread.time)
                    var work: Work?
                    if let w = try? m.nestedContainer(keyedBy: WorkKeys.self, forKey: .work), let ms = try? w.decode(Int.self, forKey: .ms), ms >= 0 {
                        var steps: [Work.Step] = []
                        if var list = try? w.nestedUnkeyedContainer(forKey: .steps) {
                            while !list.isAtEnd {
                                guard let step = try? list.nestedContainer(keyedBy: WorkStepKeys.self) else { _ = try? list.decode(Skipped.self); continue }
                                // A step is shown by tafs cloud's words for it, never by its tool's name.
                                guard let words = (try? step.decodeIfPresent(String.self, forKey: .words)) ?? nil,
                                      !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                                let failed = ((try? step.decodeIfPresent(Bool.self, forKey: .failed)) ?? nil) ?? ((try? step.decodeIfPresent(Bool.self, forKey: .error)) ?? nil) ?? false
                                steps.append(Work.Step(words: words, failed: failed, why: (try? step.decodeIfPresent(String.self, forKey: .why)) ?? nil,
                                                       notMade: ((try? step.decodeIfPresent(Bool.self, forKey: .notMade)) ?? nil) ?? false))
                            }
                        }
                        work = Work(ms: ms, steps: steps)
                    }
                    items.append(.message(Message(id: (try? m.decodeIfPresent(String.self, forKey: .id)) ?? nil, at: at, from: from,
                                                  kind: ((try? m.decodeIfPresent(String.self, forKey: .kind)) ?? nil) ?? "message", text: text, work: work), position: position))
                case "card":
                    guard let card = try? item.nestedContainer(keyedBy: CardKeys.self, forKey: .card) else { continue }
                    func text(_ key: CardKeys) -> String? {
                        guard let value = (try? card.decodeIfPresent(String.self, forKey: key)) ?? nil,
                              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                        return value
                    }
                    guard let id = text(.id) ?? text(.key) else { continue }
                    var options: [Card.Option] = []
                    if var list = try? card.nestedUnkeyedContainer(forKey: .options) {
                        while !list.isAtEnd {
                            guard let option = try? list.nestedContainer(keyedBy: OptionKeys.self) else { _ = try? list.decode(Skipped.self); continue }
                            // An option with no value can't be answered, and one with no label can't be read.
                            guard let label = try? option.decode(String.self, forKey: .label), let value = try? option.decode(String.self, forKey: .value),
                                  !label.isEmpty, !value.isEmpty else { continue }
                            options.append(Card.Option(label: label, value: value))
                        }
                    }
                    let answer = try? card.nestedContainer(keyedBy: AnswerKeys.self, forKey: .answer)
                    let answered = answer.flatMap { ((try? $0.decodeIfPresent(String.self, forKey: .words)) ?? nil) ?? ((try? $0.decodeIfPresent(String.self, forKey: .state)) ?? nil) }
                    var made = Card(key: text(.key) ?? id, id: id, type: text(.type) ?? "", session: text(.session), title: text(.title),
                                    text: text(.text), options: options, waits: text(.waits), answered: answered)
                    if var list = try? card.nestedUnkeyedContainer(forKey: .steps) {
                        while !list.isAtEnd {
                            guard let step = try? list.nestedContainer(keyedBy: PlanKeys.self) else { _ = try? list.decode(Skipped.self); continue }
                            guard let label = try? step.decode(String.self, forKey: .label), !label.isEmpty else { continue }
                            made.plan.append(Card.PlanStep(label: label, status: ((try? step.decodeIfPresent(String.self, forKey: .status)) ?? nil) ?? "pending"))
                        }
                    }
                    made.tone = text(.tone)
                    made.tafID = text(.tafID)
                    if let taf = try? card.nestedContainer(keyedBy: TafKeys.self, forKey: .taf) {
                        made.tafName = ((try? taf.decodeIfPresent(String.self, forKey: .name)) ?? nil).flatMap { $0.isEmpty ? nil : $0 }
                    }
                    made.tools = (((try? card.decodeIfPresent([String].self, forKey: .tools)) ?? nil) ?? []).filter { !$0.isEmpty }
                    if let connection = try? card.nestedContainer(keyedBy: ConnectionKeys.self, forKey: .connection),
                       ((try? connection.decodeIfPresent(Bool.self, forKey: .done)) ?? nil) == true {
                        made.connectionWords = ((try? connection.decodeIfPresent(String.self, forKey: .words)) ?? nil).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                    }
                    items.append(.card(made, position: position))
                case "held":
                    guard let held = try? item.nestedContainer(keyedBy: HeldKeys.self, forKey: .held),
                          let exception = try? held.decode(String.self, forKey: .exception) else { continue }
                    items.append(.held(exception: exception, position: position))
                default:
                    items.append(.other(type: type, position: position))
                }
            }
            self.items = items
        }

        private struct Skipped: Decodable {}

        /// Whether the thread has the message tafs cloud gave this id.
        func has(message id: String) -> Bool {
            items.contains { item in
                if case .message(let message, _) = item { return message.id == id }
                return false
            }
        }

        /// Whether the person's latest message in the thread is this text, sent at or after
        /// `since` (give or take a minute of clock difference): a first try that did arrive.
        func hasPersonsLast(_ text: String, since: Date) -> Bool {
            for item in items.reversed() {
                guard case .message(let message, _) = item, message.fromPerson else { continue }
                guard message.text.trimmingCharacters(in: .whitespacesAndNewlines) == text, let at = message.at else { return false }
                return at >= since.addingTimeInterval(-60)
            }
            return false
        }

        /// Whether something in this chat waits for the person.
        var waitsForPerson: Bool {
            items.contains { item in
                switch item {
                case .card(let card, _): return card.waitsForPerson
                case .held: return true
                default: return false
                }
            }
        }
    }

    static func time(_ text: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// The account's Coach, as tafs cloud names it; nil before Coach is started.
struct Coach: Decodable, Equatable {
    let id: String
    let name: String
}

/// A message as it may be sent: 1 to 2,000 characters once trimmed.
enum Outgoing {
    static let longest = 2000

    /// The text to send, or nil when there is nothing to send or it is too long.
    static func text(_ typed: String) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.count > longest ? nil : trimmed
    }

    /// What tafs cloud answers a sent message: the thread gives the same message that id.
    struct Sent: Decodable, Equatable {
        struct Message: Decodable, Equatable { let id: String }
        let session: String
        let message: Message?
    }
}

extension CloudClient {
    /// The account's Coach. A plain read: it sends no time zone, so it changes nothing.
    func coach() async throws -> Coach? {
        struct Answer: Decodable { let setup: Coach? }
        let answer: Answer = try await get("/v1/setup")
        return answer.setup
    }

    /// Sends the person's message to a taf's live chat, or to Coach's. It starts a run: only
    /// ever called for what the person typed and sent.
    func send(_ text: String, to taf: String) async throws -> Outgoing.Sent {
        guard let text = Outgoing.text(text) else { throw CloudRefusal(status: 0, body: Data(#"{"error":"not_a_message"}"#.utf8)) }
        let body = try await post("/v1/tafs/\(Self.query(taf))/messages", ["text": text])
        guard let sent = try? JSONDecoder().decode(Outgoing.Sent.self, from: body) else { throw KIFFError.unreadable }
        return sent
    }

    /// Answers a card that waits with one of its own options, as data. The run that waited
    /// goes on. Only a choice is answered this way: never a card whose answer is a signature.
    func answer(_ card: Thread.Card, with option: Thread.Card.Option, in taf: String) async throws {
        guard card.isChoice, !card.grants, card.options.contains(option) else {
            throw CloudRefusal(status: 0, body: Data(#"{"error":"not_this_cards_answer"}"#.utf8))
        }
        var fields = ["answer": option.value]
        if let session = card.session { fields["session"] = session }
        _ = try await post("/v1/tafs/\(Self.query(taf))/components/\(Self.query(card.id))/answer", fields)
    }

    /// Says no to a card whose answer would be a signature: `declined` for an approval, `not now`
    /// for a sign-in. Saying no grants nothing, so it needs no signature. These two words are
    /// the only answers this app ever sends such a card.
    func decline(_ card: Thread.Card, in taf: String) async throws {
        let word: String
        switch card.type {
        case "approval": word = "declined"
        case "sign_in": word = "not now"
        default: throw CloudRefusal(status: 0, body: Data(#"{"error":"not_this_cards_answer"}"#.utf8))
        }
        var fields = ["answer": word]
        if let session = card.session { fields["session"] = session }
        _ = try await post("/v1/tafs/\(Self.query(taf))/components/\(Self.query(card.id))/answer", fields)
    }

    /// Allows AI use, for the version of the words the person read.
    func allowAI(version: String) async throws {
        _ = try await post("/v1/me/ai-consent", ["version": version])
    }

    /// The thread of the person's chats with a taf, or with Coach.
    func thread(of taf: String) async throws -> Thread.Page {
        try await get("/v1/tafs/\(Self.query(taf))/conversation")
    }
}

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

        var fromPerson: Bool { from == "owner" }
        var isNote: Bool { kind == "kickoff" }
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
        enum MessageKeys: String, CodingKey { case id, at, from, kind, text }
        enum CardKeys: String, CodingKey { case key, id, type, session, title, text, options, waits, answer }
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
                    items.append(.message(Message(id: (try? m.decodeIfPresent(String.self, forKey: .id)) ?? nil, at: at, from: from,
                                                  kind: ((try? m.decodeIfPresent(String.self, forKey: .kind)) ?? nil) ?? "message", text: text), position: position))
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
                    items.append(.card(Card(key: text(.key) ?? id, id: id, type: text(.type) ?? "", session: text(.session), title: text(.title),
                                            text: text(.text), options: options, waits: text(.waits), answered: answered), position: position))
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

    /// Allows AI use, for the version of the words the person read.
    func allowAI(version: String) async throws {
        _ = try await post("/v1/me/ai-consent", ["version": version])
    }

    /// The thread of the person's chats with a taf, or with Coach.
    func thread(of taf: String) async throws -> Thread.Page {
        try await get("/v1/tafs/\(Self.query(taf))/conversation")
    }
}

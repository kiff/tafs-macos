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

    enum Item: Identifiable, Equatable {
        case message(Message, position: Int)
        /// A card that waits for an answer (`owner`), or that tafs cloud answers (`service`).
        case card(key: String, waits: String?, position: Int)
        /// A call KIFF held, at the point it was held. Only KIFF's keys: it is answered in Needs you.
        case held(exception: String, position: Int)
        /// Something this app doesn't draw yet (a drive's end, a kind it doesn't know).
        case other(type: String, position: Int)

        var id: Int {
            switch self {
            case .message(_, let p), .card(_, _, let p), .held(_, let p), .other(_, let p): return p
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
        enum CardKeys: String, CodingKey { case key, id, waits }
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
                    guard let card = try? item.nestedContainer(keyedBy: CardKeys.self, forKey: .card),
                          let key = ((try? card.decodeIfPresent(String.self, forKey: .key)) ?? nil) ?? ((try? card.decodeIfPresent(String.self, forKey: .id)) ?? nil) else { continue }
                    items.append(.card(key: key, waits: (try? card.decodeIfPresent(String.self, forKey: .waits)) ?? nil, position: position))
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

        /// Whether something in this chat waits for the person.
        var waitsForPerson: Bool {
            items.contains { item in
                switch item {
                case .card(_, let waits, _): return waits == "owner"
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

extension CloudClient {
    /// The account's Coach. A plain read: it sends no time zone, so it changes nothing.
    func coach() async throws -> Coach? {
        struct Answer: Decodable { let setup: Coach? }
        let answer: Answer = try await get("/v1/setup")
        return answer.setup
    }

    /// The thread of the person's chats with a taf, or with Coach.
    func thread(of taf: String) async throws -> Thread.Page {
        try await get("/v1/tafs/\(Self.query(taf))/conversation")
    }
}

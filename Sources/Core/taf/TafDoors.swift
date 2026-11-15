import Foundation

/// A taf's doors (docs/doors.md), as the iPad's `TafsCloud+Doors.swift`: where work reaches it
/// from outside the app, with the answer going back the same way. tafs cloud keeps them; the
/// Mac opens, pairs and closes them with the person's session. Nothing here is signed.
enum TafDoors {
    /// One door: an email address or a WhatsApp number.
    struct Door: Decodable, Equatable, Identifiable {
        struct Key: Decodable, Equatable, Identifiable {
            let id: String
            var name: String? = nil
            /// Paired by tafs: the owner's own sign-in email.
            var auto: Bool = false

            enum CodingKeys: String, CodingKey { case id, name, auto }
            init(id: String, name: String? = nil, auto: Bool = false) {
                self.id = id; self.name = name; self.auto = auto
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try c.decode(String.self, forKey: .id)
                name = try? c.decodeIfPresent(String.self, forKey: .name)
                auto = (try? c.decode(Bool.self, forKey: .auto)) ?? false
            }
        }

        let id: String
        let app: String
        let kind: String
        let label: String
        var open: Bool
        let address: String
        /// "proven": it can tell who wrote, so it holds keys. "none": everything knocks.
        let proof: String
        /// How it knows who's writing, in a line.
        let how: String
        var keys: [Key]
        /// Today's messages from the owner and paired senders, and their cap.
        var today: Int
        var limit: Int
        var resting: Bool
        /// Today's messages from anyone else, and their own cap.
        var othersToday: Int? = nil
        var othersLimit: Int? = nil
        /// tafs cloud's words for the door, shown as they are; none from an older tafs cloud.
        var words: Words? = nil
        /// A Slack door's connection, channel and planque subscription.
        var grant: String? = nil
        var channel: String? = nil
        var trigger: String? = nil

        /// Where the door stands, what a tap on it does, and that its settings are below.
        struct Words: Decodable, Equatable {
            let state: String
            let tap: String
            let settings: String
        }

        enum CodingKeys: String, CodingKey {
            case id, app, kind, label, open, address, proof, how, keys, today, limit, resting, words, grant, channel, trigger
            case othersToday = "others_today", othersLimit = "others_limit"
        }

        var holdsKeys: Bool { proof == "proven" }
    }

    /// An app a door can open on here.
    struct App: Decodable, Equatable, Identifiable {
        let id: String
        let label: String
        let kind: String
        let proof: String
        let how: String
    }

    /// Someone without a key wrote: the owner decides.
    struct Knock: Decodable, Equatable, Identifiable {
        let id: String
        let door: String
        let app: String
        let from: String
        var name: String? = nil
        /// "pass", "fail" (the sender check failed) or "none" (the door can't tell).
        let proof: String
        var subject: String? = nil
        let text: String
        var attachments: Int = 0
        let at: Date
        let state: String
        /// Not a message: the line saying the door had its day's messages, from the owner and
        /// paired senders ("keys") or from anyone else ("others"), and how many more were dropped.
        var rest: String? = nil
        var dropped: Int = 0
        /// Its sender was paired from it; the message still waits.
        var paired = false

        enum CodingKeys: String, CodingKey { case id, door, app, from, name, proof, subject, text, attachments, at, state, rest, dropped, paired }

        var isLine: Bool { rest != nil }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            door = try c.decode(String.self, forKey: .door)
            app = try c.decode(String.self, forKey: .app)
            from = try c.decode(String.self, forKey: .from)
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            proof = (try? c.decode(String.self, forKey: .proof)) ?? "none"
            subject = try? c.decodeIfPresent(String.self, forKey: .subject)
            text = (try? c.decode(String.self, forKey: .text)) ?? ""
            attachments = (try? c.decode(Int.self, forKey: .attachments)) ?? 0
            at = try c.decode(Date.self, forKey: .at)
            state = (try? c.decode(String.self, forKey: .state)) ?? "open"
            rest = try? c.decodeIfPresent(String.self, forKey: .rest)
            dropped = (try? c.decode(Int.self, forKey: .dropped)) ?? 0
            paired = (try? c.decode(Bool.self, forKey: .paired)) ?? false
        }

        /// Who wrote, as the owner reads it.
        var who: String { name.map { "\($0) (\(from))" } ?? from }
    }

    struct Page: Decodable, Equatable {
        var doors: [Door]
        var apps: [App]
        var knocks: [Knock]
    }

    /// A taf's doors on Home, for its avatar's rim and Needs you's knocks, as the iPad's
    /// `DoorLight`: what's missing reads as nothing to show.
    struct Light: Decodable, Equatable {
        let app: String
        let open: Bool
        let resting: Bool
        let knocks: Int

        enum CodingKeys: String, CodingKey { case app, open, resting, knocks }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            app = (try? c.decode(String.self, forKey: .app)) ?? ""
            open = (try? c.decode(Bool.self, forKey: .open)) ?? false
            resting = (try? c.decode(Bool.self, forKey: .resting)) ?? false
            knocks = (try? c.decode(Int.self, forKey: .knocks)) ?? 0
        }
    }

    /// The knocks waiting at a taf's doors, as Needs you counts them (`NeedsYouView.knocks`).
    static func knocks(_ lights: [Light]?) -> Int { (lights ?? []).reduce(0) { $0 + $1.knocks } }

    /// How a door's app is named, as the iPad's `DoorNames`.
    static func label(_ app: String) -> String {
        switch app {
        case "email": return "email"
        case "whatsapp": return "WhatsApp"
        default: return app.prefix(1).uppercased() + app.dropFirst()
        }
    }

    static func mark(_ app: String) -> String {
        switch app {
        case "email": return "@"
        case "whatsapp": return "W"
        default: return String(app.prefix(1)).uppercased()
        }
    }
}

extension CloudClient {
    private struct DoorAnswer: Decodable { let door: TafDoors.Door }

    /// One change to a taf's doors: its method, path and body, with the session; a refusal
    /// throws `CloudRefusal`, as `post` does.
    func doorChange<Body: Encodable>(_ method: String, _ path: String, body: Body?) async throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var headers = ["Authorization": "Bearer \(session.accessToken)", "Accept": "application/json",
                       "Accept-Language": language, "User-Agent": "tafs-macos"]
        var data = Data()
        if let body {
            headers["Content-Type"] = "application/json"
            data = try encoder.encode(body)
        }
        let (status, answer) = try await transport.send(HTTPRequest(method: method, path: path, headers: headers, body: data))
        guard (200..<300).contains(status) else { throw CloudRefusal(status: status, body: answer) }
        return answer
    }

    private func door(_ data: Data) throws -> TafDoors.Door {
        guard let answer = try? AccountClient.decoder.decode(DoorAnswer.self, from: data) else { throw KIFFError.unreadable }
        return answer.door
    }

    private func doorsPath(_ taf: String) -> String { "/v1/tafs/\(Self.escaped(taf))/doors" }

    func doors(of taf: String) async throws -> TafDoors.Page {
        try await get(doorsPath(taf))
    }

    /// Turns a door on. Email needs nothing more; WhatsApp, its signup's code and ids.
    func addDoor(_ taf: String, app: String, extra: [String: String] = [:]) async throws -> TafDoors.Door {
        var body = extra
        body["app"] = app
        return try door(try await doorChange("POST", doorsPath(taf), body: body))
    }

    func setDoorOpen(_ taf: String, door id: String, open: Bool) async throws -> TafDoors.Door {
        try door(try await doorChange("PATCH", doorsPath(taf) + "/\(Self.escaped(id))", body: ["open": open]))
    }

    func removeDoor(_ taf: String, door id: String) async throws {
        struct Answer: Decodable { let removed: String }
        let data = try await doorChange("DELETE", doorsPath(taf) + "/\(Self.escaped(id))", body: Optional<[String: String]>.none)
        guard (try? JSONDecoder().decode(Answer.self, from: data)) != nil else { throw KIFFError.unreadable }
    }

    func pair(_ taf: String, door id: String, sender: String, name: String?) async throws -> TafDoors.Door {
        var body = ["id": sender]
        if let name, !name.isEmpty { body["name"] = name }
        return try door(try await doorChange("POST", doorsPath(taf) + "/\(Self.escaped(id))/keys", body: body))
    }

    func unpair(_ taf: String, door id: String, sender: String) async throws -> TafDoors.Door {
        try door(try await doorChange("DELETE", doorsPath(taf) + "/\(Self.escaped(id))/keys/\(Self.escaped(sender))", body: Optional<[String: String]>.none))
    }

    /// The owner's answer to a knock: "do" (with their own words, if they wrote some), "pair" or "ignore".
    func answerKnock(_ taf: String, knock: String, action: String, say: String? = nil) async throws {
        struct Answer: Decodable { let state: String }
        var body = ["action": action]
        if let say, !say.isEmpty { body["say"] = say }
        let data = try await doorChange("POST", doorsPath(taf) + "/knocks/\(Self.escaped(knock))", body: body)
        guard (try? JSONDecoder().decode(Answer.self, from: data)) != nil else { throw KIFFError.unreadable }
    }
}

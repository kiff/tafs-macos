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
            /// An API door's key (`api`): its last four, when it was made and last used, as tafs cloud writes them.
            /// Never the key itself.
            var last4: String? = nil
            var madeAt: String? = nil
            var lastUsedAt: String? = nil

            enum CodingKeys: String, CodingKey { case id, name, auto, last4, madeAt = "made_at", lastUsedAt = "last_used_at" }
            init(id: String, name: String? = nil, auto: Bool = false) {
                self.id = id; self.name = name; self.auto = auto
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try c.decode(String.self, forKey: .id)
                name = try? c.decodeIfPresent(String.self, forKey: .name)
                auto = (try? c.decode(Bool.self, forKey: .auto)) ?? false
                last4 = (try? c.decodeIfPresent(String.self, forKey: .last4)) ?? nil
                madeAt = (try? c.decodeIfPresent(String.self, forKey: .madeAt)) ?? nil
                lastUsedAt = (try? c.decodeIfPresent(String.self, forKey: .lastUsedAt)) ?? nil
            }

            /// What a key is called: its name, else its last four.
            var shownName: String { name ?? last4.map { "…" + $0 } ?? id }
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
        /// An API door's last request: its state, when, and tafs cloud's word for that state.
        var lastRequest: LastRequest? = nil

        struct LastRequest: Decodable, Equatable {
            let status: String
            let at: String
            var words: String? = nil
            /// tafs cloud's word, trimmed; none until it sends one, never the raw `status`.
            var shownWords: String? {
                let w = words?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return w.isEmpty ? nil : w
            }
        }

        /// Where the door stands, what a tap on it does, and that its settings are below.
        struct Words: Decodable, Equatable {
            let state: String
            let tap: String
            let settings: String
        }

        enum CodingKeys: String, CodingKey {
            case id, app, kind, label, open, address, proof, how, keys, today, limit, resting, words, grant, channel, trigger
            case othersToday = "others_today", othersLimit = "others_limit", lastRequest = "last_request"
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
        /// The replies waiting for the owner to send them (tafs cloud holds a door's reply to someone outside): each read
        /// on its own, so one that doesn't read never hides the rest. None from a tafs cloud before them.
        var replies: [HeldReply] = []
        /// The writers the taf couldn't help (tafs cloud's `unanswered`): nothing was drafted, so the owner answers in
        /// their own words or ignores it. Read each on its own, as the replies are; none from a tafs cloud before them.
        var unanswered: [Unanswered] = []

        enum CodingKeys: String, CodingKey { case doors, apps, knocks, replies, unanswered }
        init(doors: [Door], apps: [App], knocks: [Knock], replies: [HeldReply] = [], unanswered: [Unanswered] = []) {
            self.doors = doors
            self.apps = apps
            self.knocks = knocks
            self.replies = replies
            self.unanswered = unanswered
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            doors = try c.decode([Door].self, forKey: .doors)
            apps = try c.decode([App].self, forKey: .apps)
            knocks = try c.decode([Knock].self, forKey: .knocks)
            struct Lenient: Decodable {
                let reply: HeldReply?
                init(from decoder: Decoder) throws { reply = try? HeldReply(from: decoder) }
            }
            replies = ((try? c.decodeIfPresent([Lenient].self, forKey: .replies)) ?? nil)?.compactMap(\.reply) ?? []
            struct LenientUnanswered: Decodable {
                let item: Unanswered?
                init(from decoder: Decoder) throws { item = try? Unanswered(from: decoder) }
            }
            unanswered = ((try? c.decodeIfPresent([LenientUnanswered].self, forKey: .unanswered)) ?? nil)?.compactMap(\.item) ?? []
        }
    }

    /// A writer the taf couldn't help, waiting for the owner: why (`cant_do`), who, and tafs cloud's words. Nothing was
    /// drafted and the writer has had nothing. The owner answers in their own words (Send signs the SHA-256 of the text
    /// as typed) or ignores it, and connects an app when the one it needs isn't connected.
    struct Unanswered: Decodable, Equatable, Identifiable {
        let run: String
        let door: String
        let to: String
        let subject: String?
        /// `no_app` (the app it needs isn't connected), `other`, or `unfinished` (its run stopped before an answer).
        let cantDo: String
        let words: Words

        var id: String { run }

        /// The most an own answer can be, as tafs cloud counts it (JavaScript's `length`: UTF-16 units).
        static let maxText = 4000

        /// Whether `text` can be sent as the owner's answer: something besides spaces, within tafs cloud's limit.
        static func sendable(_ text: String) -> Bool {
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf16.count <= maxText
        }

        /// Every line the app draws for it, tafs cloud's in the person's language. `connect` comes only for `no_app`.
        struct Words: Decodable, Equatable {
            let line: String
            let connect: String?
            let reply: String
            let ignore: String
            let prompt: String
            let changed: String
        }

        enum CodingKeys: String, CodingKey { case run, door, to, subject, cantDo = "cant_do", words }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            run = try c.decode(String.self, forKey: .run)
            door = try c.decode(String.self, forKey: .door)
            to = try c.decode(String.self, forKey: .to)
            subject = try c.decodeIfPresent(String.self, forKey: .subject)
            cantDo = try c.decode(String.self, forKey: .cantDo)
            // Without its words it isn't drawn: it would have to be worded here.
            words = try c.decode(Words.self, forKey: .words)
            guard !run.isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .run, in: c, debugDescription: "an unanswered writer with no run")
            }
        }
    }

    /// A door's reply waiting for the owner: the exact text that would go to `to`, and tafs cloud's words for it. Sent only
    /// as read: Send names the text's SHA-256, and tafs cloud sends nothing if the held text has changed since.
    struct HeldReply: Decodable, Equatable, Identifiable {
        let run: String
        let door: String
        let to: String
        let subject: String?
        let text: String
        let textSHA256: String
        let words: Words

        var id: String { run }

        /// Every line the app draws for it, tafs cloud's in the person's language: the app has none of its own for it.
        struct Words: Decodable, Equatable {
            let line: String
            let send: String
            let discard: String
            let prompt: String
            let changed: String
        }

        enum CodingKeys: String, CodingKey { case run, door, to, subject, text, textSHA256 = "text_sha256", words }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            run = try c.decode(String.self, forKey: .run)
            door = try c.decode(String.self, forKey: .door)
            to = try c.decode(String.self, forKey: .to)
            subject = try c.decodeIfPresent(String.self, forKey: .subject)
            text = try c.decode(String.self, forKey: .text)
            textSHA256 = try c.decode(String.self, forKey: .textSHA256)
            // A reply without its words isn't drawn: it would have to be worded here.
            words = try c.decode(Words.self, forKey: .words)
            guard !run.isEmpty, Purchase.isDigest(textSHA256) else {
                throw DecodingError.dataCorruptedError(forKey: .textSHA256, in: c, debugDescription: "a held reply that can't be sent as read")
            }
        }
    }

    /// A taf's doors on Home, for its avatar's rim and Needs you's knocks, as the iPad's
    /// `DoorLight`: what's missing reads as nothing to show.
    struct Light: Decodable, Equatable {
        let app: String
        let open: Bool
        let resting: Bool
        let knocks: Int
        /// The replies waiting at this door for the owner to send them.
        let replies: Int
        /// The newest held reply's line, as its notification said it, for Needs you's row.
        let replyLine: String?

        enum CodingKeys: String, CodingKey { case app, open, resting, knocks, replies, replyLine = "reply_line" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            app = (try? c.decode(String.self, forKey: .app)) ?? ""
            open = (try? c.decode(Bool.self, forKey: .open)) ?? false
            resting = (try? c.decode(Bool.self, forKey: .resting)) ?? false
            knocks = (try? c.decode(Int.self, forKey: .knocks)) ?? 0
            replies = max(0, (try? c.decode(Int.self, forKey: .replies)) ?? 0)
            replyLine = (try? c.decodeIfPresent(String.self, forKey: .replyLine)) ?? nil
        }
    }

    /// The replies waiting at a taf's doors for the owner to send, and the newest one's line, for Needs you's row.
    static func heldReplies(_ lights: [Light]?) -> (count: Int, line: String?) {
        let held = (lights ?? []).filter { $0.replies > 0 }
        return (held.reduce(0) { $0 + $1.replies }, held.compactMap(\.replyLine).last)
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

    /// An API door's act on this Mac's security key (`KeyAct.reopenAPIDoor`, `revokeAPIDoorKey`, `removeAPIDoor`): the act's
    /// own request, with the key's assertion over exactly it (tafs cloud's `doorSigned`, as a removal). The door as tafs
    /// cloud answers, when it answers one.
    func signedDoorChange(_ act: KeyAct, assertion: String) async throws -> TafDoors.Door? {
        var headers = ["Authorization": "Bearer \(session.accessToken)", "Accept": "application/json",
                       "Accept-Language": language, "User-Agent": "tafs-macos", Passkeys.headerName: assertion]
        if !act.body.isEmpty { headers["Content-Type"] = "application/json" }
        let (status, answer) = try await transport.send(HTTPRequest(method: act.method, path: act.path, headers: headers, body: act.body))
        guard (200..<300).contains(status) else { throw CloudRefusal(status: status, body: answer) }
        return try? AccountClient.decoder.decode(DoorAnswer.self, from: answer).door
    }

    /// A door's new key, issued once (the iPad's `TafsCloud.IssuedKey`): the key itself, which is never shown again,
    /// its id, its last four and when it was made.
    struct IssuedKey: Decodable, Equatable, Identifiable {
        let id: String
        let key: String
        let last4: String
        let madeAt: String
        enum CodingKeys: String, CodingKey { case id, key, last4, madeAt = "made_at" }
    }

    /// Makes an API door's new key on the security key (`KeyAct.newAPIDoorKey`), as `signedDoorChange` sends the door's
    /// other acts. The answer is the key, which only this call ever sees.
    func newDoorKey(_ act: KeyAct, assertion: String) async throws -> IssuedKey {
        let headers = ["Authorization": "Bearer \(session.accessToken)", "Accept": "application/json", "Accept-Language": language,
                       "User-Agent": "tafs-macos", Passkeys.headerName: assertion, "Content-Type": "application/json"]
        let (status, answer) = try await transport.send(HTTPRequest(method: act.method, path: act.path, headers: headers, body: act.body))
        guard (200..<300).contains(status) else { throw CloudRefusal(status: status, body: answer) }
        guard let key = try? AccountClient.decoder.decode(IssuedKey.self, from: answer), !key.key.isEmpty else { throw KIFFError.unreadable }
        return key
    }

    /// The door a drafted door's approval opened, and its first key, in this one answer only (the iPad's `AddedAPIDoor`).
    struct AddedAPIDoor: Decodable, Equatable {
        let door: TafDoors.Door
        let key: IssuedKey
    }

    /// Approves Coach's drafted door on the security key (`KeyAct.addDraftedAPIDoor`), as `newDoorKey` sends its act.
    /// tafs cloud refuses a used draft (410 `draft_used`) and a lapsed one (404 `draft_lapsed`) in its own words.
    func addDraftedDoor(_ act: KeyAct, assertion: String) async throws -> AddedAPIDoor {
        let headers = ["Authorization": "Bearer \(session.accessToken)", "Accept": "application/json", "Accept-Language": language,
                       "User-Agent": "tafs-macos", Passkeys.headerName: assertion, "Content-Type": "application/json"]
        let (status, answer) = try await transport.send(HTTPRequest(method: act.method, path: act.path, headers: headers, body: act.body))
        guard (200..<300).contains(status) else { throw CloudRefusal(status: status, body: answer) }
        guard let added = try? AccountClient.decoder.decode(AddedAPIDoor.self, from: answer), !added.key.key.isEmpty else { throw KIFFError.unreadable }
        return added
    }

    /// Don't send: nothing goes, so nothing is signed. The reply leaves Needs you.
    func discardHeldReply(_ taf: String, run: String) async throws {
        _ = try await doorChange("POST", doorsPath(taf) + "/replies/\(Self.escaped(run))", body: ["action": "discard"])
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

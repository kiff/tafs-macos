import Foundation

/// One of a taf's chats (`GET /v1/tafs/{id}/chats`), as the iPad's `TafsCloud.Chat`.
struct CoachChat: Decodable, Equatable, Identifiable {
    let session: String
    let started: Date
    let updated: Date
    let title: String
    var id: String { session }
}

/// Where a message goes, as the iPad's `TafsCloud.ChatTarget`: the live chat unless it names
/// one or asks for a new one.
struct ChatTarget: Equatable {
    var session: String?
    var newChat = false
    /// The app follows a new chat: a message to a Coach chat that already handed a taf over
    /// starts a new one, and the answer and the stream's `session` event say `new_session`.
    var newChatAfterHandover = false
    static let live = ChatTarget()
    static let new = ChatTarget(newChat: true)

    /// A message as tafs cloud takes it, as the iPad's `MessageBody`: a flag only when it's set.
    struct Message: Encodable {
        let text: String
        let session: String?
        let newChat: Bool?
        let newChatAfterHandover: Bool?
        /// The files attached to it, by the ids their uploads gave; none, and it's left out.
        let attachments: [String]?
        enum CodingKeys: String, CodingKey { case text, session, attachments, newChat = "new_chat", newChatAfterHandover = "new_chat_after_handover" }

        init(_ text: String, _ target: ChatTarget, files: [AttachmentRef] = []) {
            self.text = text
            session = target.session
            newChat = target.newChat ? true : nil
            newChatAfterHandover = target.newChatAfterHandover ? true : nil
            attachments = files.isEmpty ? nil : files.map(\.id)
        }
    }
}

/// tafs cloud's words for deleting a conversation, in the person's language, sent with each chats-list read (`delete`), as
/// the iPad's `TafsCloud.DeleteWords` (kiff/tafs#2107). The app has none of its own: Delete is offered only once a read has
/// brought all five, each with something in it.
struct ChatDeleteWords: Decodable, Equatable {
    let item: String
    let confirmTitle: String
    let confirmBody: String
    let confirmButton: String
    let failed: String

    enum CodingKeys: String, CodingKey {
        case item, failed
        case confirmTitle = "confirm_title", confirmBody = "confirm_body", confirmButton = "confirm_button"
    }

    /// Every line there: a read with one missing or blank offers no Delete at all.
    var complete: Bool {
        ![item, confirmTitle, confirmBody, confirmButton, failed].contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// A chats-list read (`GET …/chats`, `…/chats/archived`): the chats, newest first, and the words for deleting one when
/// tafs cloud sends them all, as the iPad's `ChatsRead`.
struct CoachChatsRead: Decodable {
    let chats: [CoachChat]
    /// Nil from a tafs cloud that doesn't send them, or whose words don't read or leave a line blank.
    let delete: ChatDeleteWords?

    enum CodingKeys: String, CodingKey { case chats, delete }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chats = try c.decode([CoachChat].self, forKey: .chats)
        // Words that don't read leave the list as it is, with no Delete.
        delete = (try? c.decodeIfPresent(ChatDeleteWords.self, forKey: .delete)).flatMap { $0?.complete == true ? $0 : nil }
    }
}

/// What became of a conversation the person asked to delete, as the iPad's `deleteSetupChat` (kiff/tafs#2107). tafs
/// cloud decides whose it is; the app decides nothing.
enum ChatDelete: Equatable {
    /// Gone (or tafs cloud never had it for this person: 404), so it leaves both lists.
    case gone
    /// Still there, with the line saying why: the 409's own words (working or waiting on a card), or tafs cloud's
    /// `failed` from the last read for anything else, the network included.
    case kept(String)

    /// The outcome of the `DELETE`: nil, it went through.
    static func outcome(_ error: Error?, words: ChatDeleteWords, say: Words) -> ChatDelete {
        guard let error else { return .gone }
        if let refusal = error as? CloudRefusal {
            if refusal.status == 404 { return .gone }
            if refusal.status == 409 { return .kept(refusal.why(say)) }
        }
        return .kept(words.failed)
    }
}

extension CloudClient {
    /// Opens a new conversation with Coach on this taf, as the iPad's `improve`: tafs cloud puts
    /// the taf's job, Card and latest calls in front of the person's words.
    func improve(_ taf: String, text: String) async throws -> Outgoing.Sent {
        guard let text = Outgoing.text(text) else { throw CloudRefusal(status: 0, body: Data(#"{"error":"not_a_message"}"#.utf8)) }
        let body = try await post("/v1/tafs/\(Self.escaped(taf))/improve", ["text": text])
        guard let sent = try? JSONDecoder().decode(Outgoing.Sent.self, from: body) else { throw KIFFError.unreadable }
        return sent
    }

    /// The taf's chats, newest first.
    func chats(of taf: String) async throws -> [CoachChat] { try await chatsRead(of: taf).chats }

    /// The taf's chats, with what tafs cloud sends beside them (the words for deleting one).
    func chatsRead(of taf: String) async throws -> CoachChatsRead {
        try await get("/v1/tafs/\(Self.escaped(taf))/chats")
    }

    /// Archives one of the taf's chats, as the iPad's `archiveChat` (TafsCloud.swift:1560-1565):
    /// tafs cloud leaves it out of `chats` and the thread from then on, on every device. It isn't
    /// deleted. An answer that doesn't say `archived` is unreadable.
    func archive(chat session: String, of taf: String) async throws {
        try await chatMove("/v1/tafs/\(Self.escaped(taf))/chats/\(Self.escaped(session))/archive")
    }

    /// The chats archived, to open one or put it back, as the iPad's `archivedChats`
    /// (TafsCloud.swift:1567-1572).
    func archivedChats(of taf: String) async throws -> [CoachChat] { try await archivedChatsRead(of: taf).chats }

    /// The archived chats, with what tafs cloud sends beside them.
    func archivedChatsRead(of taf: String) async throws -> CoachChatsRead {
        try await get("/v1/tafs/\(Self.escaped(taf))/chats/archived")
    }

    /// Deletes one of the person's own chats for good (`DELETE /v1/tafs/{id}/chats/{session}`, kiff/tafs#2095): its
    /// messages and the files they added, on every device. Unsigned, with the session's token, as Archive. tafs cloud
    /// decides whose it is: 404 for one that isn't theirs or is already gone, 409 while its run works or waits on a card.
    func deleteChat(_ session: String, of taf: String) async throws {
        _ = try await delete("/v1/tafs/\(Self.escaped(taf))/chats/\(Self.escaped(session))")
    }

    /// Puts an archived chat back in the list, as the iPad's `unarchiveChat`
    /// (TafsCloud.swift:1574-1578).
    func putBack(chat session: String, of taf: String) async throws {
        try await chatMove("/v1/tafs/\(Self.escaped(taf))/chats/\(Self.escaped(session))/unarchive")
    }

    /// One of the two moves, answered `{"archived": …}` as the iPad decodes it.
    private func chatMove(_ path: String) async throws {
        struct Answer: Decodable { let archived: Bool }
        let body = try await post(path, [:])
        guard (try? JSONDecoder().decode(Answer.self, from: body)) != nil else { throw KIFFError.unreadable }
    }
}

/// A chat message refused for want of a plan (`no_plan`), as Android's no-plan prompt (kiff/tafs#2193, #2198): tafs
/// cloud's words stay as a prompt above the box, with Solo's line, Choose a plan and Not now, until the person chooses
/// or sends again. Every other refusal is said as before.
enum PlanPrompt {
    /// tafs cloud's code for a chat refused because the account has no plan.
    static let code = "no_plan"
    /// Solo's line, already Plan & usage's under Solo, in every language (`billing.tafs_kiff_one_person_every`).
    static let soloKey = "billing.tafs_kiff_one_person_every"

    /// tafs cloud's words for a refusal that needs a plan, else nil: its `words`, else its `error`, else the app's line.
    static func words(_ error: Error, say: Words) -> String? {
        guard let refusal = error as? CloudRefusal, refusal.code == code || refusal.error == code else { return nil }
        return refusal.why(say)
    }
}

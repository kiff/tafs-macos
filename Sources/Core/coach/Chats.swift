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
    func chats(of taf: String) async throws -> [CoachChat] {
        struct Answer: Decodable { let chats: [CoachChat] }
        let answer: Answer = try await get("/v1/tafs/\(Self.escaped(taf))/chats")
        return answer.chats
    }
}

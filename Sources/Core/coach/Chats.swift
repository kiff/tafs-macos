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
        enum CodingKeys: String, CodingKey { case text, session, newChat = "new_chat", newChatAfterHandover = "new_chat_after_handover" }

        init(_ text: String, _ target: ChatTarget) {
            self.text = text
            session = target.session
            newChat = target.newChat ? true : nil
            newChatAfterHandover = target.newChatAfterHandover ? true : nil
        }
    }
}

extension CloudClient {
    /// The taf's chats, newest first.
    func chats(of taf: String) async throws -> [CoachChat] {
        struct Answer: Decodable { let chats: [CoachChat] }
        let answer: Answer = try await get("/v1/tafs/\(Self.escaped(taf))/chats")
        return answer.chats
    }
}

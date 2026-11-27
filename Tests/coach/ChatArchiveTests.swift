import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

private func cloud(_ answers: [(Int, String)]) -> (CloudClient, CannedTransport) {
    let transport = CannedTransport(answers)
    return (CloudClient(transport: transport, session: session), transport)
}

let coachArchiveTests: [Test] = [
    Test("archiving, the archived list and putting back go to the iPad's routes, each id escaped", awaiting: {
        let archived = #"{"chats":[{"session":"s 1","started":"2026-11-13T09:00:00Z","updated":"2026-11-13T10:00:00Z","title":"Refunds"}]}"#
        let (client, transport) = cloud([(200, #"{"archived":true}"#), (200, archived), (200, #"{"archived":false}"#)])
        try await client.archive(chat: "s 1", of: "taf/coach")
        let read = try await client.archivedChats(of: "taf/coach")
        try expectEqual(read.map(\.session), ["s 1"])
        try expectEqual(read[0].title, "Refunds")
        try await client.putBack(chat: "s 1", of: "taf/coach")
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, [
            "POST /v1/tafs/taf%2Fcoach/chats/s%201/archive",
            "GET /v1/tafs/taf%2Fcoach/chats/archived",
            "POST /v1/tafs/taf%2Fcoach/chats/s%201/unarchive",
        ])
    }),
    Test("an archive tafs cloud refuses, or answers without saying archived, isn't taken", awaiting: {
        let (client, _) = cloud([(409, #"{"error":"busy"}"#), (200, #"{"ok":true}"#), (200, "not json")])
        do { try await client.archive(chat: "s1", of: "taf-coach"); throw Failure(description: "a refusal was taken") }
        catch let refusal as CloudRefusal { try expectEqual(refusal.status, 409) }
        do { try await client.archive(chat: "s1", of: "taf-coach"); throw Failure(description: "no archived was taken") }
        catch KIFFError.unreadable {}
        do { try await client.putBack(chat: "s1", of: "taf-coach"); throw Failure(description: "not JSON was taken") }
        catch KIFFError.unreadable {}
    }),
    Test("deleting a conversation: tafs cloud's five words come with either list, and a DELETE to its route, escaped", awaiting: {
        let words = #""delete":{"item":"Delete conversation","confirm_title":"Delete this conversation?","confirm_body":"Its messages go.","confirm_button":"Delete","failed":"It wasn't deleted."}"#
        let chat = #"{"session":"s 1","started":"2026-11-13T09:00:00Z","updated":"2026-11-13T10:00:00Z","title":"Refunds"}"#
        let (client, transport) = cloud([(200, "{\"chats\":[\(chat)],\(words)}"), (200, "{\"chats\":[],\(words)}"), (200, #"{"deleted":true}"#)])
        let read = try await client.chatsRead(of: "taf/coach")
        try expectEqual(read.chats.map(\.session), ["s 1"])
        try expectEqual(read.delete?.item, "Delete conversation")
        try expectEqual(read.delete?.confirmButton, "Delete")
        let archived = try await client.archivedChatsRead(of: "taf/coach")
        try expectEqual(archived.delete?.failed, "It wasn't deleted.")
        try await client.deleteChat("s 1", of: "taf/coach")
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, [
            "GET /v1/tafs/taf%2Fcoach/chats",
            "GET /v1/tafs/taf%2Fcoach/chats/archived",
            "DELETE /v1/tafs/taf%2Fcoach/chats/s%201",
        ])
    }),
    Test("no Delete without all five words: none sent, one blank, or words that don't read, and the list still reads", awaiting: {
        let chat = #"{"session":"s1","started":"2026-11-13T09:00:00Z","updated":"2026-11-13T10:00:00Z","title":"Refunds"}"#
        let blank = #""delete":{"item":"Delete conversation","confirm_title":" ","confirm_body":"b","confirm_button":"Delete","failed":"f"}"#
        let missing = #""delete":{"item":"Delete conversation","confirm_title":"t","confirm_body":"b","confirm_button":"Delete"}"#
        let (client, _) = cloud([(200, "{\"chats\":[\(chat)]}"), (200, "{\"chats\":[\(chat)],\(blank)}"),
                                 (200, "{\"chats\":[\(chat)],\(missing)}"), (200, "{\"chats\":[\(chat)],\"delete\":\"yes\"}")])
        for _ in 0..<4 {
            let read = try await client.chatsRead(of: "taf-coach")
            try expectEqual(read.chats.count, 1)
            try expect(read.delete == nil, "Delete was offered without all five words")
        }
    }),
    Test("a delete's outcome: through or 404 is gone, 409 keeps it with its own words, anything else with tafs cloud's failed") {
        let words = ChatDeleteWords(item: "Delete conversation", confirmTitle: "t", confirmBody: "b", confirmButton: "Delete", failed: "It wasn't deleted.")
        let say = Words(language: "en", lines: [:])
        try expectEqual(ChatDelete.outcome(nil, words: words, say: say), .gone)
        try expectEqual(ChatDelete.outcome(CloudRefusal(status: 404, body: Data(#"{"error":"not_found"}"#.utf8)), words: words, say: say), .gone)
        let busy = CloudRefusal(status: 409, body: Data(#"{"error":"busy","words":"This conversation is still working."}"#.utf8))
        try expectEqual(ChatDelete.outcome(busy, words: words, say: say), .kept("This conversation is still working."))
        try expectEqual(ChatDelete.outcome(CloudRefusal(status: 503, body: Data()), words: words, say: say), .kept("It wasn't deleted."))
        try expectEqual(ChatDelete.outcome(URLError(.notConnectedToInternet), words: words, say: say), .kept("It wasn't deleted."))
    },
    Test("an archived list whose chat lacks its times doesn't read", awaiting: {
        let (client, _) = cloud([(200, #"{"chats":[{"session":"s1","title":"No times"}]}"#)])
        let read = try? await client.archivedChats(of: "taf-coach")
        try expect(read == nil, "a chat without its times was read")
    }),
]

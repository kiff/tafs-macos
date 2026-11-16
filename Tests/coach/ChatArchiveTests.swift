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
    Test("an archived list whose chat lacks its times doesn't read", awaiting: {
        let (client, _) = cloud([(200, #"{"chats":[{"session":"s1","title":"No times"}]}"#)])
        let read = try? await client.archivedChats(of: "taf-coach")
        try expect(read == nil, "a chat without its times was read")
    }),
]

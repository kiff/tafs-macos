import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

let setupAnswer = #"{"setup":{"id":"taf-coach","name":"Coach","job":"setup","status":"active","next_run":null,"last_run":null},"tools":{"state":"given"}}"#
let threadAnswer = #"""
{"messages":[],"components":[],"working":true,"items":[
  {"type":"message","message":{"id":"m1","at":"2026-11-14T18:00:00.000Z","from":"owner","kind":"message","text":"Connect Qonto for my refunds taf","session":"s1"}},
  {"type":"message","message":{"id":"m2","at":"2026-11-14T18:00:20Z","from":"taf","kind":"message","text":"I can connect Qonto. **Approve** its Card to go on.","session":"s1"}},
  {"type":"card","card":{"id":"confirm-1","key":"s1:confirm-1","type":"confirm","waits":"owner"}},
  {"type":"card","card":{"id":"result-1","key":"s1:result-1","type":"result","waits":"service"}},
  {"type":"held","held":{"exception":"exc_1","run":"r1","session":"s1","at":"2026-11-14T18:01:00Z"}},
  {"type":"drive","drive":{"id":"d1"}},
  {"type":"message","message":{"from":"taf"}},
  "noise"
]}
"""#

private func cloud(_ answers: [(Int, String)]) -> (CloudClient, CannedTransport) {
    let transport = CannedTransport(answers)
    return (CloudClient(transport: transport, session: session), transport)
}

let coachThreadTests: [Test] = [
    Test("Coach is the account's, or none before it is started, and reading it sends no time zone", awaiting: {
        let (client, transport) = cloud([(200, setupAnswer), (200, #"{"setup":null,"tools":null}"#)])
        let coach = try await client.coach()
        try expectEqual(coach, Coach(id: "taf-coach", name: "Coach"))
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "GET /v1/setup")
        try expectEqual(transport.sent[0].headers["X-Time-Zone"], nil)
        let none = try await client.coach()
        try expectEqual(none, nil)
    }),
    Test("the thread is drawn in tafs cloud's order, and what doesn't read is left out", awaiting: {
        let (client, transport) = cloud([(200, threadAnswer)])
        let page = try await client.thread(of: "taf-coach")
        try expectEqual(transport.sent[0].path, "/v1/tafs/taf%2Dcoach/conversation")
        try expectEqual(page.working, true)
        try expectEqual(page.items.count, 6)
        guard case .message(let first, _) = page.items[0], case .message(let second, _) = page.items[1] else { throw Failure(description: "two messages first") }
        try expectEqual(first.fromPerson, true)
        try expectEqual(first.text, "Connect Qonto for my refunds taf")
        try expectEqual(second.fromPerson, false)
        try expectEqual(page.items[2], .card(key: "s1:confirm-1", waits: "owner", position: 2))
        try expectEqual(page.items[3], .card(key: "s1:result-1", waits: "service", position: 3))
        try expectEqual(page.items[4], .held(exception: "exc_1", position: 4))
        try expectEqual(page.items[5], .other(type: "drive", position: 5))
        try expectEqual(page.waitsForPerson, true)
    }),
    Test("a card is known by its key, never only by the name the model gave it") {
        let both = #"{"items":[{"type":"card","card":{"id":"confirm-1","key":"s2:confirm-1","waits":"owner"}},{"type":"card","card":{"id":"confirm-1","key":"s3:confirm-1"}}]}"#
        let page = try JSONDecoder().decode(Thread.Page.self, from: Data(both.utf8))
        try expectEqual(page.items, [.card(key: "s2:confirm-1", waits: "owner", position: 0), .card(key: "s3:confirm-1", waits: nil, position: 1)])
    },
    Test("an answer with no ordered list is unreadable, never an empty chat", awaiting: {
        for body in ["{}", #"{"messages":[]}"#, "<html>"] {
            do { _ = try await cloud([(200, body)]).0.thread(of: "t"); throw Failure(description: "\(body) was read") } catch let error as KIFFError { try expectEqual(error, .unreadable) }
        }
        let empty = try await cloud([(200, #"{"items":[]}"#)]).0.thread(of: "t")
        try expectEqual(empty.items.count, 0)
        try expectEqual(empty.waitsForPerson, false)
    }),
]

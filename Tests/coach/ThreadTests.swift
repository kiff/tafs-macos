import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

let setupAnswer = #"{"setup":{"id":"taf-coach","name":"Coach","job":"setup","status":"active","next_run":null,"last_run":null},"tools":{"state":"given"}}"#
/// Coach has no chats listed yet: it reads its thread as before.
let noChats = #"{"chats":[]}"#
let threadAnswer = #"""
{"messages":[],"components":[],"working":true,"items":[
  {"type":"message","message":{"id":"m1","at":"2026-11-14T18:00:00.000Z","from":"owner","kind":"message","text":"Connect Qonto for my refunds taf","session":"s1"}},
  {"type":"message","message":{"id":"m2","at":"2026-11-14T18:00:20Z","from":"taf","kind":"message","text":"I can connect Qonto. **Approve** its Card to go on.","session":"s1"}},
  {"type":"card","card":{"key":"s1:confirm-1","component":{"id":"confirm-1","type":"confirm","waits":"owner"}}},
  {"type":"card","card":{"key":"s1:result-1","component":{"id":"result-1","type":"result","waits":"service"}}},
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
        try expectEqual(transport.sent[0].path, "/v1/tafs/taf-coach/conversation")
        try expectEqual(page.working, true)
        try expectEqual(page.items.count, 6)
        guard case .message(let first, _) = page.items[0], case .message(let second, _) = page.items[1] else { throw Failure(description: "two messages first") }
        try expectEqual(first.fromPerson, true)
        try expectEqual(first.text, "Connect Qonto for my refunds taf")
        try expectEqual(second.fromPerson, false)
        guard case .card(let confirm, _) = page.items[2], case .card(let result, _) = page.items[3] else { throw Failure(description: "two cards") }
        try expectEqual(confirm.key, "s1:confirm-1")
        try expectEqual(confirm.id, "confirm-1")
        try expectEqual(confirm.waitsForPerson, true)
        try expectEqual(result.waits, "service")
        try expectEqual(result.waitsForPerson, false)
        try expectEqual(page.items[4], .held(exception: "exc_1", position: 4))
        try expectEqual(page.items[5], .other(type: "drive", position: 5))
        try expectEqual(page.waitsForPerson, true)
    }),
    Test("a taf's words carry tafs cloud's run lines and a refused connection's lines, as written; none on the person's or a kickoff") {
        let json = #"""
        {"items":[
          {"type":"message","message":{"from":"taf","kind":"message","text":"Done.","delivered":" Sent to Google Sheets · Refunds 2026 ","counted":"From the record: 5 done · 1 refused",
            "refused":{"words":"Coach couldn't connect Shippo yet","why":"  ","next":"Ask Coach to try again."}}},
          {"type":"message","message":{"from":"taf","kind":"message","text":"Nothing new.","delivered":"  ","refused":{"words":" ","next":""}}},
          {"type":"message","message":{"from":"owner","kind":"message","text":"Go","delivered":"x","counted":"y","refused":{"words":"z","next":"w"}}},
          {"type":"message","message":{"from":"taf","kind":"kickoff","text":"Run","counted":"y"}}
        ]}
        """#
        let messages: [Thread.Message] = try JSONDecoder().decode(Thread.Page.self, from: Data(json.utf8)).items.compactMap {
            if case .message(let m, _) = $0 { return m } else { return nil }
        }
        try expectEqual(messages.count, 4)
        try expectEqual(messages[0].runLines.above, "Sent to Google Sheets · Refunds 2026")
        try expectEqual(messages[0].runLines.under, "From the record: 5 done · 1 refused")
        try expectEqual(messages[0].refusedLines?.lines, ["Coach couldn't connect Shippo yet", "Ask Coach to try again."])
        try expectEqual(messages[0].refusedLines?.why, nil)
        // Blank lines are none.
        try expectEqual(messages[1].runLines.above, nil)
        try expectEqual(messages[1].refusedLines, nil)
        // The person's message and a run's kickoff carry none, whatever is sent.
        for m in messages[2...] {
            try expectEqual(m.runLines.above, nil)
            try expectEqual(m.runLines.under, nil)
            try expectEqual(m.refusedLines, nil)
        }
    },
    Test("a card is known by its key, never only by the name the model gave it") {
        let both = #"{"items":[{"type":"card","card":{"key":"s2:confirm-1","component":{"id":"confirm-1","waits":"owner"}}},{"type":"card","card":{"key":"s3:confirm-1","component":{"id":"confirm-1"}}}]}"#
        let page = try JSONDecoder().decode(Thread.Page.self, from: Data(both.utf8))
        let keys: [String] = page.items.compactMap { if case .card(let card, _) = $0 { return card.key } else { return nil } }
        try expectEqual(keys, ["s2:confirm-1", "s3:confirm-1"])
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

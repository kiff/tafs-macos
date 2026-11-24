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
    Test("a door card (Coach's taf_door_api) is read with its taf and its draft, as the iPad's SetupComponent; without either it's no door") {
        let page = { (component: String) in
            try JSONDecoder().decode(Thread.Page.self, from: Data(#"{"working":false,"items":[{"type":"card","card":{"key":"s1#door-1","session":"s1","component":\#(component)}}]}"#.utf8))
        }
        let door = { (p: Thread.Page) -> (String, String)? in
            for item in p.items { if case .card(let card, _) = item, let d = card.door { return (d.taf, d.draft) } }
            return nil
        }
        let read = try page(#"{"type":"taf_door_api","id":"door-1","taf_id":"taf-1","draft_id":"dd-1"}"#)
        try expect(door(read).map { $0 == ("taf-1", "dd-1") } == true, "its taf and draft")
        try expect(door(try page(#"{"type":"taf_door_api","id":"door-1","taf_id":"taf-1"}"#)) == nil, "no draft, no door")
        try expect(door(try page(#"{"type":"notice","id":"n","taf_id":"taf-1","draft_id":"dd-1"}"#)) == nil, "another kind is no door")
    },
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
    Test("a taf's chat places the Record's outcomes and the door's knocks among its items by time, as the iPad's chatItems") {
        let at = { (s: Int) in Date(timeIntervalSince1970: 1_800_000_000 + TimeInterval(s)) }
        // Items at 10 and 30, one with no time after the first; extras at 5, 20, 20 and 40.
        let placed = TafChatTimeline.placed(items: [at(10), nil, at(30)], extras: [at(40), at(20), at(5), at(20)])
        try expectEqual(placed, [.extra(2), .item(0), .item(1), .extra(1), .extra(3), .item(2), .extra(0)])
        // A tie goes to the thread's own first.
        try expectEqual(TafChatTimeline.placed(items: [at(10)], extras: [at(10)]), [.item(0), .extra(0)])
        // No extras: the thread as it came.
        try expectEqual(TafChatTimeline.placed(items: [at(1), nil], extras: []), [.item(0), .item(1)])
    },
    Test("a taf's chat shows the calls the owner answered, from the Record, since its first message, in the iPad's words") {
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        func entry(_ kind: String, _ at: String, call: String = "{}") throws -> Record.Entry {
            let json = #"{"id":"e-\#(kind)-\#(at)","at":"\#(at)","kind":"\#(kind)","title":"Refund","detail":"Stripe refused","time":"18:30","taf":{"id":"taf_1","name":"Refunds"},"call":\#(call)}"#
            return try AccountClient.decoder.decode(Record.Entry.self, from: Data(json.utf8))
        }
        let first = ISO8601DateFormatter().date(from: "2026-11-14T17:00:00Z")
        let approved = try entry("approved", "2026-11-14T17:30:00Z")
        let refused = try entry("refused", "2026-11-14T17:31:00Z")
        let done = try entry("done", "2026-11-14T17:32:00Z")
        let notDoneAfterYes = try entry("not_done", "2026-11-14T17:33:00Z", call: #"{"outcome":"allowed","held":true}"#)
        let notDoneAlone = try entry("not_done", "2026-11-14T17:34:00Z")
        let before = try entry("approved", "2026-11-14T16:59:00Z")
        let shown = TafChatTimeline.outcomes([approved, refused, done, notDoneAfterYes, notDoneAlone, before], since: first)
        try expectEqual(shown.map(\.id), [approved.id, refused.id, notDoneAfterYes.id])
        // A chat with no message yet shows none.
        try expectEqual(TafChatTimeline.outcomes([approved], since: nil), [])
        try expectEqual(TafChatTimeline.text(refused, words), words("chat.outcome.refused", ["title": "Refund"]))
        try expectEqual(TafChatTimeline.text(notDoneAfterYes, words), words("chat.outcome.not_done", ["title": "Refund", "detail": "Stripe refused"]))
        try expectEqual(TafChatTimeline.text(approved, words), words("chat.outcome.approved_done", ["title": "Refund"]))
        let mine = try entry("approved", "2026-11-14T17:35:00Z", call: #"{"answer":{"decision":"approved_once","you":true}}"#)
        try expectEqual(TafChatTimeline.text(mine, words), words("chat.outcome.approved", ["title": "Refund"]))
        try expectEqual([approved, refused, notDoneAfterYes].map { TafChatTimeline.tone($0.kind) }, [.ok, .dim, .no])
        try expectEqual(TafChatTimeline.mark("sending"), "clock.fill")
    },
]

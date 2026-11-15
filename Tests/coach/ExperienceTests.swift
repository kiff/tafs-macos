import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

let experienceThread = #"""
{"working":false,"items":[
  {"type":"card","card":{"id":"plan","key":"s1:plan","type":"steps","title":"New instructions","steps":[{"label":"Connect Gmail","status":"done"},{"label":"Approve its Card","status":"active"},{"label":"Set it up","status":"pending"},{"status":"done"}]}},
  {"type":"message","message":{"id":"m1","at":"2026-11-15T00:30:00Z","from":"owner","text":"Set up a taf that lists my unanswered emails. Read only."}},
  {"type":"message","message":{"id":"m2","at":"2026-11-15T00:30:32Z","from":"taf","text":"Waiting for your approval of the taf's **read-only** Gmail access.",
    "work":{"ms":32400,"steps":[{"tool":"planque_catalog","words":"Looking up your connections"},{"tool":"secret_tool"},{"tool":"planque_connect","words":"Working on the connection","failed":true,"why":"Why: managed sign-in isn't set up for this app"},{"tool":"t","words":"Choosing the tools","not_made":true}]}}},
  {"type":"card","card":{"id":"approval-1","key":"s1:approval-1","type":"approval","session":"s1","text":"Connect Gmail for Unanswered emails with the sign-in you already have there.","waits":"owner"}},
  {"type":"card","card":{"id":"approval-0","key":"s1:approval-0","type":"approval","title":"Unanswered emails' Card","answer":{"state":"answered","words":"Approved"},"connection":{"done":true,"words":"Gmail is connected (read only)"}}},
  {"type":"card","card":{"id":"notice-1","key":"s1:notice-1","type":"notice","text":"Its check couldn't read the work list: no run started.","tone":"warning"}},
  {"type":"card","card":{"id":"result-1","key":"s1:result-1","type":"result","text":"Unanswered emails reads your Gmail inbox every weekday at 9.","taf":{"agent":"agent_1","name":"Unanswered emails"},"taf_id":"taf-1","tools":["List inbox conversations","Read my Gmail address",""]}}
]}
"""#

private func page() throws -> Thread.Page { try JSONDecoder().decode(Thread.Page.self, from: Data(experienceThread.utf8)) }
private func cards() throws -> [Thread.Card] { try page().items.compactMap { if case .card(let card, _) = $0 { return card } else { return nil } } }

let coachExperienceTests: [Test] = [
    Test("a message carries its run's work: how long, and the steps in tafs cloud's words, never a tool's name") {
        guard case .message(let answer, _) = try page().items[2], let work = answer.work else { throw Failure(description: "no work") }
        try expectEqual(work.took, "32 s")
        try expectEqual(work.steps.map(\.words), ["Looking up your connections", "Working on the connection", "Choosing the tools"])
        try expectEqual(work.steps[1].failed, true)
        try expectEqual(work.steps[1].why, "Why: managed sign-in isn't set up for this app")
        try expectEqual(work.steps[2].notMade, true)
        try expectEqual(Thread.Work(ms: 400, steps: []).took, "1 s")
        try expectEqual(Thread.Work(ms: 119_400, steps: []).took, "119 s")
        try expectEqual(Thread.Work(ms: 245_000, steps: []).took, "4 min")
    },
    Test("each kind of card is read with what it draws: a plan, an approval, a notice, a hand-over") {
        let all = try cards()
        try expectEqual(all.map(\.type), ["steps", "approval", "approval", "notice", "result"])
        try expectEqual(all[0].isPlan, true)
        try expectEqual(all[0].plan.map(\.label), ["Connect Gmail", "Approve its Card", "Set it up"])
        try expectEqual(all[0].planDone, 1)
        try expectEqual(all[1].grants, true)
        try expectEqual(all[1].waitsForPerson, true)
        try expectEqual(all[2].answered, "Approved")
        try expectEqual(all[2].connectionWords, "Gmail is connected (read only)")
        try expectEqual(all[3].tone, "warning")
        try expectEqual(all[4].isHandOver, true)
        try expectEqual(all[4].tafName, "Unanswered emails")
        try expectEqual(all[4].tafID, "taf-1")
        try expectEqual(all[4].tools, ["List inbox conversations", "Read my Gmail address"])
    },
    Test("declining sends only \"declined\" to an approval and \"not now\" to a sign-in, and nothing to any other card", awaiting: {
        let all = try cards()
        let transport = CannedTransport([(200, "{}"), (200, "{}")])
        let client = CloudClient(transport: transport, session: session)
        try await client.decline(all[1], in: "taf-coach")
        try expectEqual(transport.sent[0].path, "/v1/tafs/taf%2Dcoach/components/approval%2D1/answer")
        try expectEqual(try JSONDecoder().decode([String: String].self, from: transport.sent[0].body), ["answer": "declined", "session": "s1"])
        let signIn = try JSONDecoder().decode(Thread.Page.self, from: Data(#"{"items":[{"type":"card","card":{"id":"s","type":"sign_in","waits":"owner"}}]}"#.utf8))
        guard case .card(let card, _) = signIn.items[0] else { throw Failure(description: "no card") }
        try await client.decline(card, in: "taf-coach")
        try expectEqual(try JSONDecoder().decode([String: String].self, from: transport.sent[1].body), ["answer": "not now"])
        for other in [all[0], all[3], all[4]] {
            do { try await client.decline(other, in: "taf-coach"); throw Failure(description: "\(other.type) was declined") } catch let refusal as CloudRefusal {
                try expectEqual(refusal.code, "not_this_cards_answer")
            }
        }
        try expectEqual(transport.sent.count, 2)
    }),
    Test("the live steps are listed as they come, each checked when it ends, without the trailing dots") {
        var live = LiveAnswer()
        _ = live.take(.activity(words: "Working on the connection…"))
        try expectEqual(live.steps, [.init(words: "Working on the connection")])
        _ = live.take(.step(failed: false, why: nil))
        _ = live.take(.activity(words: nil))
        _ = live.take(.activity(words: "Choosing the tools..."))
        _ = live.take(.step(failed: true, why: "Why: no"))
        try expectEqual(live.steps, [.init(words: "Working on the connection", done: true), .init(words: "Choosing the tools", done: true, failed: true)])
        // A step that ends with nothing open changes nothing.
        _ = live.take(.step(failed: false, why: nil))
        try expectEqual(live.steps.count, 2)
    },
    Test("only bold and list items are read from the model's words; everything else stays as written") {
        try expectEqual(Rich.blocks("I can connect Qonto. **Approve** its Card."),
                        [.paragraph([.init(text: "I can connect Qonto. ", bold: false), .init(text: "Approve", bold: true), .init(text: " its Card.", bold: false)])])
        try expectEqual(Rich.blocks("What I do:\n- **Weekday check:** each weekday\n• Report\n\n* On request"), [
            .paragraph([.init(text: "What I do:", bold: false)]),
            .bullet([.init(text: "Weekday check:", bold: true), .init(text: " each weekday", bold: false)]),
            .bullet([.init(text: "Report", bold: false)]),
            .bullet([.init(text: "On request", bold: false)]),
        ])
        // An unpaired mark, a link, HTML and a heading are not read: they stay text.
        for plain in ["2 ** 3 is 8", "[Approve](https://evil.example)", "<b>Approve</b> <a href=\"x\">here</a>", "# Approve", "![x](y)", "-not a list", "-"] {
            try expectEqual(Rich.blocks(plain), [.paragraph([.init(text: plain, bold: false)])])
        }
        try expectEqual(Rich.blocks(String(repeating: "**a** ", count: 5000)).count, 1)
    },
]

import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

let experienceThread = #"""
{"working":false,"items":[
  {"type":"card","card":{"key":"s1:plan","component":{"id":"plan","type":"steps","title":"New instructions","steps":[{"label":"Connect Mail","status":"done"},{"label":"Approve its Card","status":"active"},{"label":"Set it up","status":"pending"},{"status":"done"}],"line":"Step 2 of 3: Approve its Card"}}},
  {"type":"message","message":{"id":"m1","at":"2026-11-15T00:30:00Z","from":"owner","text":"Set up a taf that lists my unanswered emails. Read only."}},
  {"type":"message","message":{"id":"m2","at":"2026-11-15T00:30:32Z","from":"taf","text":"Waiting for your approval of the taf's **read-only** Mail access.",
    "work":{"ms":32400,"steps":[{"tool":"planque_catalog","words":"Looking up your connections"},{"tool":"secret_tool"},{"tool":"planque_connect","words":"Working on the connection","failed":true,"why":"Why: managed sign-in isn't set up for this app"},{"tool":"t","words":"Choosing the tools","not_made":true}]}}},
  {"type":"card","card":{"key":"s1:approval-1","session":"s1","component":{"id":"approval-1","type":"approval","text":"Connect Mail for Unanswered emails with the sign-in you already have there.","waits":"owner"}}},
  {"type":"card","card":{"key":"s1:approval-0","answer":{"state":"answered","words":"Approved"},"component":{"id":"approval-0","type":"approval","title":"Unanswered emails' Card","connection":{"done":true,"words":"Mail is connected (read only)"}}}},
  {"type":"card","card":{"key":"s1:notice-1","component":{"id":"notice-1","type":"notice","text":"Its check couldn't read the work list: no run started.","tone":"warning"}}},
  {"type":"card","card":{"key":"s1:result-1","answer":{"state":"answered","words":"Set up","at":"2026-11-15T00:31:00Z","by":"tafs","outcome":{"taf_id":"taf-1"}},"component":{"id":"result-1","type":"result","text":"Unanswered emails reads your Mail inbox every weekday at 9.","taf":{"agent":"agent_1","name":"Unanswered emails"},"taf_id":"taf-dial","tools":["List inbox conversations","Read my Mail address",""]}}},
  {"type":"card","card":{"key":"s1:confirm-2","answer":{"state":"wrote","words":"Make it hourly","at":"2026-11-15T00:32:00Z"},"component":{"id":"confirm-2","type":"confirm","options":[{"label":"Agree","value":"agree"}],"waits":"owner"}}},
  {"type":"card","card":{"key":"s1:confirm-3","answer":{"state":"no_answer","words":"","at":"2026-11-15T00:33:00Z"},"component":{"id":"confirm-3","type":"confirm","waits":"owner"}}}
]}
"""#

private func page() throws -> Thread.Page { try JSONDecoder().decode(Thread.Page.self, from: Data(experienceThread.utf8)) }
private func cards() throws -> [Thread.Card] { try page().items.compactMap { if case .card(let card, _) = $0 { return card } else { return nil } } }

let coachExperienceTests: [Test] = [
    Test("a message carries its run's work: how long, and the steps in tafs cloud's words, never a tool's name") {
        guard case .message(let answer, _) = try page().items[2], let work = answer.work else { throw Failure(description: "no work") }
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        try expectEqual(work.took(words), "32 s")
        try expectEqual(work.steps.map(\.words), ["Looking up your connections", "Working on the connection", "Choosing the tools"])
        try expectEqual(work.steps[1].failed, true)
        try expectEqual(work.steps[1].why, "Why: managed sign-in isn't set up for this app")
        try expectEqual(work.steps[2].notMade, true)
        // The iPad's rule, in the shared words: seconds under a minute, else minutes and seconds.
        try expectEqual(Thread.Work(ms: 400, steps: []).took(words), "1 s")
        try expectEqual(Thread.Work(ms: 59_400, steps: []).took(words), "59 s")
        try expectEqual(Thread.Work(ms: 119_400, steps: []).took(words), "1 min 59 s")
        try expectEqual(Thread.Work(ms: 245_000, steps: []).took(words), "4 min 5 s")
    },
    Test("each kind of card is read with what it draws: a plan, an approval, a notice, a hand-over") {
        let all = try cards()
        try expectEqual(all.map(\.type), ["steps", "approval", "approval", "notice", "result", "confirm", "confirm"])
        try expectEqual(all[0].isPlan, true)
        try expectEqual(all[0].plan.map(\.label), ["Connect Mail", "Approve its Card", "Set it up"])
        try expectEqual(all[0].planDone, 1)
        try expectEqual(all[0].planLine, "Step 2 of 3: Approve its Card")
        try expectEqual(all[1].grants, true)
        try expectEqual(all[1].waitsForPerson, true)
        try expectEqual(all[2].answered, "Approved")
        try expectEqual(all[2].connectionWords, "Mail is connected (read only)")
        try expectEqual(all[3].tone, "warning")
        try expectEqual(all[4].isHandOver, true)
        try expectEqual(all[4].tafName, "Unanswered emails")
        // The hand-over is about its taf's agent, and what came of it is tafs cloud's outcome,
        // never the component's own taf_id (a dial card's).
        try expectEqual(all[4].tafAgent, "agent_1")
        try expectEqual(all[4].outcome, Thread.Card.Outcome(tafID: "taf-1"))
        // Answered only when the person chose: one they wrote past, or that stopped waiting,
        // waits no more and shows no answer.
        try expectEqual(all[5].answered, nil)
        try expectEqual(all[5].waitsForPerson, false)
        try expectEqual(all[6].answered, nil)
        try expectEqual(all[6].waitsForPerson, false)
        try expectEqual(all[4].tools, ["List inbox conversations", "Read my Mail address"])
    },
    Test("declining sends only \"declined\" to an approval and \"not now\" to a sign-in, and nothing to any other card", awaiting: {
        let all = try cards()
        let transport = CannedTransport([(200, "{}"), (200, "{}")])
        let client = CloudClient(transport: transport, session: session)
        try await client.decline(all[1], in: "taf-coach")
        try expectEqual(transport.sent[0].path, "/v1/tafs/taf%2Dcoach/components/approval%2D1/answer")
        try expectEqual(try JSONDecoder().decode([String: String].self, from: transport.sent[0].body), ["answer": "declined", "session": "s1"])
        let signIn = try JSONDecoder().decode(Thread.Page.self, from: Data(#"{"items":[{"type":"card","card":{"component":{"id":"s","type":"sign_in","waits":"owner"}}}]}"#.utf8))
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
    Test("the live steps are ended by their call, overlapping or not, and one refused unmade isn't done") {
        var live = LiveAnswer()
        _ = live.take(.activity(words: "Working on the connection…", call: "c1"))
        try expectEqual(live.steps, [.init(words: "Working on the connection", call: "c1")])
        // A second call starts before the first ends; a step with no words isn't listed.
        _ = live.take(.activity(words: "Choosing the tools...", call: "c2"))
        _ = live.take(.activity(words: nil, call: "c3"))
        // The unlisted one ends: nothing listed changes.
        _ = live.take(.step(call: "c3", status: "done", why: nil))
        try expectEqual(live.steps.map(\.done), [false, false])
        // The first call ends after the second began: it is the first that is done.
        _ = live.take(.step(call: "c1", status: "done", why: nil))
        _ = live.take(.step(call: "c2", status: "not_made", why: nil))
        try expectEqual(live.steps, [.init(words: "Working on the connection", call: "c1", done: true),
                                     .init(words: "Choosing the tools", call: "c2", notMade: true)])
        _ = live.take(.activity(words: "Drafting the Card…", call: "c4"))
        _ = live.take(.step(call: "c4", status: "error", why: "Why: no"))
        try expectEqual(live.steps[2], .init(words: "Drafting the Card", call: "c4", done: true, failed: true))
        try expectEqual(live.trouble, "Why: no")
        // A step that ends with nothing open, or a call never begun, changes nothing.
        _ = live.take(.step(call: "c9", status: "done", why: nil))
        _ = live.take(.step(call: nil, status: "done", why: nil))
        try expectEqual(live.steps.count, 3)
        // The stream's own lines, an older tafs cloud's too.
        try expectEqual(StreamEvent.read("activity", #"{"tool":"t","step":"Reading…","call_id":"c1"}"#), .activity(words: "Reading…", call: "c1"))
        try expectEqual(StreamEvent.read("step", #"{"call_id":"c1","status":"not_made"}"#), .step(call: "c1", status: "not_made", why: nil))
        try expectEqual(StreamEvent.read("step", #"{"failed":true,"why":"Why: no"}"#), .step(call: nil, status: "error", why: "Why: no"))
    },
    Test("Coach's Markdown is read as the iPad reads it, so no mark shows; a link is its label only") {
        try expectEqual(Rich.blocks("I can connect Qonto. **Approve** its Card."),
                        [.paragraph([.init(text: "I can connect Qonto. "), .init(text: "Approve", bold: true), .init(text: " its Card.")])])
        try expectEqual(Rich.blocks("## What I'll do\n1. Connect *Mail* daily\n2) Read `inbox`\n- **Weekday check:** each weekday\n• Report\n\n* On request"), [
            .heading([.init(text: "What I'll do")]),
            .numbered("1.", [.init(text: "Connect "), .init(text: "Mail", italic: true), .init(text: " daily")]),
            .numbered("2.", [.init(text: "Read "), .init(text: "inbox", code: true)]),
            .bullet([.init(text: "Weekday check:", bold: true), .init(text: " each weekday")]),
            .bullet([.init(text: "Report")]),
            .bullet([.init(text: "On request")]),
        ])
        // A link or an image is drawn as its words, and leads nowhere.
        try expectEqual(Rich.blocks("See [the Card](https://evil.example) and ![a chart](x.png)"),
                        [.paragraph([.init(text: "See the Card and a chart")])])
        // HTML, a mark with no partner, snake_case, and lines that only look like items stay as written.
        for plain in ["2 ** 3 is 8", "<b>Approve</b> <a href=\"x\">here</a>", "planque_connect_tool", "2 * 3 * 4", "#Approve", "-not a list", "-", "1.5 percent", "`"] {
            try expectEqual(Rich.blocks(plain), [.paragraph([.init(text: plain)])])
        }
        try expectEqual(Rich.blocks(String(repeating: "**a** ", count: 5000)).count, 1)
    },
    Test("a fenced code block is its lines as written, no mark read inside; one never closed is code to the end") {
        try expectEqual(Rich.blocks("Run this:\n```swift\nlet **total** = [a](b)\n\n  indented\n```\nDone."), [
            .paragraph([.init(text: "Run this:")]),
            .code("let **total** = [a](b)\n\n  indented"),
            .paragraph([.init(text: "Done.")]),
        ])
        // While an answer streams, an open fence is code until it closes.
        try expectEqual(Rich.blocks("Here:\n```\nstep 1\r\nstep 2"), [.paragraph([.init(text: "Here:")]), .code("step 1\nstep 2")])
        try expectEqual(Rich.blocks("```\n```"), [.code("")])
    },
]

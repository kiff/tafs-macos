import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let words = try! Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))

/// Cards read as tafs cloud sends them, each `{key, at?, answer?, component}`.
private func page(_ cards: [String]) throws -> Thread.Page {
    let items = cards.map { #"{"type":"card","card":"# + $0 + "}" }.joined(separator: ",")
    return try JSONDecoder().decode(Thread.Page.self, from: Data((#"{"items":["# + items + "]}").utf8))
}

private func card(_ json: String) throws -> Thread.Card {
    guard let card = try page([json]).cards.first else { throw Failure(description: "no card read") }
    return card
}

/// An approval for `grant`, with `answer` (a card's `answer` object) and more in its component.
private func approval(_ id: String, grant: String? = "g_stripe", at: String? = nil, answer: String? = nil, _ more: String = "") -> String {
    let g = grant.map { #","grant":"\#($0)""# } ?? ""
    let when = at.map { #","at":"\#($0)""# } ?? ""
    let answered = answer.map { #","answer":"# + $0 } ?? ""
    return #"{"key":"s1#\#(id)","session":"s1"\#(when)\#(answered),"component":{"id":"\#(id)","type":"approval","title":"Connect Stripe","waits":"owner"\#(g)\#(more)}}"#
}

/// KIFF's draft as `GET /v1/me/agent-drafts/{id}` answers it.
let approvalDraftAnswer = #"""
{"id":"drf_s1","agent_id":"refunds-acme","status":"draft","version":"v3","label":"Refunds assistant","future_field":{"anything":1},
 "cards":[{"grants":[
   {"action":"stripe__create_refund","title":"Refund a payment","per_action_max":[{"quantity":"sum(amount)","max":10000,"unit":"EUR","scale":2}]},
   {"action":"stripe__list_charges"}],
  "aggregates":[{"quantity":"sum(amount)","limit":100000,"window":"calendar_day","unit":"EUR","scale":2},
                {"quantity":"count","limit":20,"window":"calendar_day"}]}]}
"""#

private func draft(_ json: String) throws -> AccountClient.Draft {
    try AccountClient.decoder.decode(AccountClient.Draft.self, from: Data(json.utf8))
}

private func grant(_ json: String) throws -> AppConnections.Grant {
    try AccountClient.decoder.decode(AppConnections.Grant.self, from: Data(json.utf8))
}

let coachApprovalTests: [Test] = [
    Test("an approval's grant, draft, signs and settled answer read as tafs cloud sends them, leniently", awaiting: {
        let fixture = try Data(contentsOf: URL(fileURLWithPath: ".shared/contracts/coach-conversation.json"))
        guard let root = try JSONSerialization.jsonObject(with: fixture) as? [String: Any], let answer = root["answer"] else {
            throw Failure(description: "coach-conversation.json has no answer")
        }
        let read = try JSONDecoder().decode(Thread.Page.self, from: try JSONSerialization.data(withJSONObject: answer))
        let connect = read.cards.first { $0.type == "approval" }
        try expectEqual(connect?.grant, "grt_1")
        try expectEqual(connect.flatMap { ApprovalLines.answer($0) }, .approved)
        let marked = try card(approval("a1", answer: #"{"state":"answered","words":"Approved","answer":"connected"}"#,
                                       #","draft":"drf_s1","signs":{"card":false,"words":"Its Card: you approve it next","takes":"tap"}"#))
        try expectEqual(marked.draft, "drf_s1")
        try expectEqual(marked.signs, Thread.Card.Signs(card: false, words: "Its Card: you approve it next", takes: "tap"))
        try expectEqual(marked.stored, "connected")
        // A mark of another shape is no mark, never the card unread.
        let odd = try card(approval("a2", #","signs":{"card":"yes","words":7},"draft":3"#))
        try expectEqual(odd.signs, Thread.Card.Signs(card: nil, words: nil, takes: nil))
        try expectEqual(odd.draft, nil)
        let unmarked = try card(approval("a3", grant: nil, #","signs":"tap""#))
        try expectEqual(unmarked.signs, nil)
        try expectEqual(unmarked.grant, nil)
    }),
    Test("a refused or failed approval never reads approved: tafs cloud's settled answer first, else its exact English", awaiting: {
        func read(_ answer: String) throws -> ApprovalLines.Answer? { ApprovalLines.answer(try card(approval("a", answer: answer))) }
        try expectEqual(try read(#"{"state":"answered","words":"Approved","answer":"approved"}"#), .approved)
        try expectEqual(try read(#"{"state":"answered","words":"Approved","answer":"connected"}"#), .approved)
        try expectEqual(try read(#"{"state":"answered","words":"Already approved","answer":"already approved: signed before"}"#), .alreadyApproved)
        try expectEqual(try read(#"{"state":"answered","words":"Declined","answer":"declined"}"#), .declined)
        // tafs cloud's line for the owner, whole, when its settled answer says it failed.
        try expectEqual(try read(#"{"state":"answered","words":"Stripe refused this request: the tool name is taken.","answer":"failed: tool_name_taken"}"#),
                        .failed(refused: "Stripe refused this request: the tool name is taken."))
        // Words that say approved never outweigh a settled failure, nor an answer this build doesn't know.
        try expectEqual(try read(#"{"state":"answered","words":"Approved","answer":"failed: no"}"#), .failed(refused: "Approved"))
        try expectEqual(try read(#"{"state":"answered","words":"Approved","answer":"maybe"}"#), .failed(refused: nil))
        // Words alone: only tafs cloud's exact English.
        try expectEqual(try read(#"{"state":"answered","words":"Approved"}"#), .approved)
        try expectEqual(try read(#"{"state":"answered","words":"Declined"}"#), .declined)
        try expectEqual(try read(#"{"state":"answered","words":"Approuvé"}"#), .failed(refused: nil))
        try expectEqual(try read(#"{"state":"answered","words":"Approved · it didn't go through: Stripe said no"}"#), .failed(refused: nil))
        // Written past, or no answer: none.
        try expectEqual(try read(#"{"state":"wrote","words":"Approved"}"#), nil)
        try expectEqual(ApprovalLines.answer(try card(approval("a"))), nil)
    }),
    Test("where an approval stands: its answer, else planque's state for its grant, in planque's words; then its eyebrow", awaiting: {
        let waiting = try card(approval("a"))
        try expectEqual(ApprovalLines.state(waiting, grant: nil), .needsYou)
        let failed = try grant(#"{"id":"g_stripe","status":"failed","status_words":"Stripe refused the tool name","request":{"server":"mcp.stripe.com","agent":"a"}}"#)
        try expectEqual(ApprovalLines.state(waiting, grant: failed), .failed("Stripe refused the tool name"))
        try expectEqual(ApprovalLines.failedLine(waiting, .failed("Stripe refused the tool name"), words), "It didn't go through: Stripe refused the tool name")
        try expectEqual(ApprovalLines.failedLine(waiting, .failed(nil), words), "It didn't go through. Nothing was connected.")
        try expectEqual(ApprovalLines.requestRefused(.failed(nil), grant: failed), true)
        try expectEqual(ApprovalLines.requestRefused(.needsYou, grant: failed), false)
        let approved = try card(approval("a", answer: #"{"state":"answered","words":"Approved","answer":"approved"}"#))
        try expectEqual(ApprovalLines.state(approved, grant: failed), .failed("Stripe refused the tool name"))
        try expectEqual(ApprovalLines.state(approved, grant: nil), .done)
        // Decline as the iPad's: waiting or failed, answered too, but not replaced or refused by planque.
        let disconnected = try grant(#"{"id":"g_stripe","status":"disconnected","request":{"server":"mcp.stripe.com","agent":"a"}}"#)
        try expectEqual(ApprovalLines.declinable(approved, ApprovalLines.state(approved, grant: disconnected), replaced: false, grant: disconnected), true)
        try expectEqual(ApprovalLines.declinable(approved, ApprovalLines.state(approved, grant: failed), replaced: false, grant: failed), false)
        try expectEqual(ApprovalLines.declinable(approved, .done, replaced: false, grant: nil), false)
        try expectEqual(ApprovalLines.declinable(waiting, .needsYou, replaced: false, grant: nil), true)
        try expectEqual(ApprovalLines.declinable(waiting, .needsYou, replaced: true, grant: nil), false)
        try expectEqual(ApprovalLines.eyebrow(.done, replaced: false, words).0, "Approved")
        try expectEqual(ApprovalLines.eyebrow(.needsYou, replaced: false, words).1, .amber)
        try expectEqual(ApprovalLines.eyebrow(.failed(nil), replaced: false, words).1, .no)
        try expectEqual(ApprovalLines.eyebrow(.done, replaced: true, words).1, .dim)
    }),
    Test("a newer request for the same connection replaces an earlier one, which folds as history", awaiting: {
        let thread = try page([
            approval("a1", at: "2026-11-20T10:00:00Z", answer: #"{"state":"answered","words":"Approved","answer":"approved"}"#),
            approval("a0", at: "2026-11-20T09:00:00Z"),
            #"{"key":"s1#in","session":"s1","at":"2026-11-20T12:00:00Z","component":{"id":"in","type":"sign_in","grant":"g_stripe","waits":"owner"}}"#,
            approval("a2", at: "2026-11-20T11:00:00Z"),
            approval("other", grant: "g_qonto", at: "2026-11-20T08:00:00Z"),
            approval("bare", grant: nil, at: "2026-11-20T07:00:00Z"),
        ])
        let cards = thread.cards
        try expectEqual(cards.map { thread.replaced($0) }, [true, true, false, false, false, false])
        try expectEqual(ApprovalLines.replacedLine(cards[0], words), "Approved · Setup asked for more below")
        try expectEqual(ApprovalLines.replacedLine(cards[1], words), "Setup changed this request: see below")
        let declined = try card(approval("d", answer: #"{"state":"answered","words":"Declined"}"#))
        try expectEqual(ApprovalLines.replacedLine(declined, words), "Declined · Setup asked again below")
        // With no time, the later place in the chat is the newer.
        let untimed = try page([approval("u1"), approval("u2")])
        try expectEqual(untimed.cards.map { untimed.replaced($0) }, [true, false])
    }),
    Test("KIFF's draft reads with its lines and title, as the iPad's DraftCard words it", awaiting: {
        let d = try draft(approvalDraftAnswer)
        try expectEqual(d.confirmed, false)
        try expectEqual(d.signed, false)
        try expectEqual(d.cardTitle(words), "Refunds assistant's Card")
        try expectEqual(d.lines(words), ["Refund a payment: up to €100 each", "list charges", "€1,000 in total a day", "20 calls a day"])
        let own = try draft(#"{"id":"d","agent_id":"a","status":"claimed","version":"1","cards":[{"lines":["Refund up to €50"],"grants":[{"action":"x"}]}]}"#)
        try expectEqual(own.signed, true)
        try expectEqual(own.lines(words), ["Refund up to €50"])
        let asks = try draft(#"""
        {"id":"d","agent_id":"a","status":"confirmed","version":"1","cards":[{"on_exceed":"owner",
          "grants":[{"action":"pay","title":"Pay","per_action_max":[{"quantity":"count","max":3}]}],
          "aggregates":[{"quantity":"count","limit":0,"window":"calendar_day"},{"quantity":"count","limit":5,"window":"rolling_1h"},
                        {"quantity":"sum(amount)","limit":3000,"window":"lifetime"}]}]}
        """#)
        try expectEqual(asks.lines(words), ["Pay: up to 3 each; more asks you first", "Each call asks you first", "5 calls in any hour, then it asks you",
                                            "3,000 (no currency) in total, then it asks you"])
        let alike = try draft(#"""
        {"id":"d","agent_id":"a","status":"draft","version":"1","label":"  ","cards":[
          {"grants":[{"action":"stripe__write_refunds","title":"Write Stripe API data"}]},
          {"grants":[{"action":"stripe__write_customers","title":"write stripe api data"}]}]}
        """#)
        try expectEqual(alike.lines(words), ["Write Stripe API data · write refunds", "write stripe api data · write customers"])
        try expectEqual(alike.cardTitle(words), "The taf's Card")
    }),
    Test("an approval's draft is read as the session, never signed: GET /v1/me/agent-drafts/{id}, its id escaped", awaiting: {
        let transport = CannedTransport([(200, approvalDraftAnswer), (404, #"{"error":"not_found"}"#)])
        let client = AccountClient(transport: transport, session: session)
        let read = try await client.draft(id: "drf s/1")
        try expectEqual(read.id, "drf_s1")
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "GET /v1/me/agent-drafts/drf%20s%2F1")
        try expectEqual(transport.sent[0].headers["Authorization"], "Bearer tok")
        try expectEqual(transport.sent[0].headers["KIFF-Device-Signature"], nil)
        try expect(transport.sent[0].body.isEmpty, "a read has no body")
        let gone = try? await client.draft(id: "drf_gone")
        try expect(gone == nil, "a draft KIFF doesn't give is not read")
    }),
    Test("an approval's Card is drawn where it's read; a Card next is said only where it comes next", awaiting: {
        let d = try draft(approvalDraftAnswer)
        let signsNow = try card(approval("a", #","draft":"drf_s1","signs":{"card":true}"#))
        try expectEqual(ApprovalLines.drawsDraft(signsNow, d), true)
        try expectEqual(ApprovalLines.drawsDraft(signsNow, nil), false)
        let nextNoWords = try card(approval("a", #","draft":"drf_s1","signs":{"card":false}"#))
        try expectEqual(ApprovalLines.drawsDraft(nextNoWords, d), false)
        // An app's first sign-in has no draft: tafs cloud's words for the Card next, and only then.
        let first = try card(approval("a", #","signs":{"card":false,"words":"Its Card: you approve it next"}"#))
        let read = try grant(#"{"id":"g_stripe","status":"pending","request":{"server":"mcp.stripe.com","agent":"a"}}"#)
        try expectEqual(ApprovalLines.cardNextWords(first, grant: read), "Its Card: you approve it next")
        // Not until planque's grant for it is read, as the iPad's `grant != nil`.
        try expectEqual(ApprovalLines.cardNextWords(first, grant: nil), nil)
        try expectEqual(ApprovalLines.cardNextWords(try card(approval("a", #","signs":{"card":true,"words":"Its Card"}"#)), grant: read), nil)
        try expectEqual(ApprovalLines.cardNextWords(try card(approval("a", #","draft":"d","signs":{"card":false,"words":"Its Card"}"#)), grant: read), nil)
        try expectEqual(ApprovalLines.cardNextWords(try card(approval("a", #","connection":{"done":true,"words":"Stripe is connected"},"signs":{"words":"Its Card"}"#)), grant: read), nil)
    }),
    Test("an answered approval reads as one line: the Card it signed, else Coach's title, else the vendor", awaiting: {
        let confirmed = try draft(approvalDraftAnswer.replacingOccurrences(of: #""status":"draft""#, with: #""status":"confirmed""#))
        let approved = try card(approval("a", answer: #"{"state":"answered","words":"Approved","answer":"approved"}"#, #","draft":"drf_s1""#))
        try expectEqual(ApprovalLines.outcome(approved, .done, grant: nil, draft: confirmed, words), "Approved · Refunds assistant's Card")
        try expectEqual(ApprovalLines.signedLines(.done, draft: confirmed, words).first, "Refund a payment: up to €100 each")
        try expectEqual(ApprovalLines.outcome(approved, .done, grant: nil, draft: nil, words), "Approved · Connect Stripe")
        let already = try card(approval("a", answer: #"{"state":"answered","words":"Already approved","answer":"already approved"}"#))
        try expectEqual(ApprovalLines.outcome(already, .done, grant: nil, draft: nil, words), "Already approved · Connect Stripe")
        let declined = try card(approval("a", answer: #"{"state":"answered","words":"Declined"}"#))
        try expectEqual(ApprovalLines.outcome(declined, .declined, grant: nil, draft: confirmed, words), "Declined · Connect Stripe")
        try expectEqual(ApprovalLines.signedLines(.declined, draft: confirmed, words), [])
        // No title: the Card drafted, else the vendor as people say it.
        let untitled = try card(#"{"key":"k","answer":{"state":"answered","words":"Approved"},"component":{"id":"a","type":"approval","service":"mcp.stripe.com","grant":"g"}}"#)
        try expectEqual(ApprovalLines.outcome(untitled, .done, grant: nil, draft: nil, words), "Approved · signed in to Stripe")
        let connected = try grant(#"{"id":"g","status":"connected","vendor":"Stripe","request":{"server":"mcp.stripe.com","agent":"a"}}"#)
        try expectEqual(ApprovalLines.outcome(untitled, .done, grant: connected, draft: nil, words), "Approved · Stripe is connected")
        try expectEqual(ApprovalLines.connectionLine(untitled, grant: connected, words), "Stripe is connected")
        let listed = try grant(#"{"id":"g","status":"listed","vendor":"Stripe","request":{"server":"mcp.stripe.com","agent":"a"}}"#)
        try expectEqual(ApprovalLines.connectionLine(untitled, grant: listed, words), "Signed in at Stripe · reading what it offers")
        try expectEqual(ApprovalLines.connectionLine(untitled, grant: nil, words), nil)
    }),
    Test("this Mac never builds an approval's answer: Decline is the only one, and a drive's card is never declined or drawn as a question", awaiting: {
        let transport = CannedTransport([(200, "{}")])
        let client = CloudClient(transport: transport, session: session)
        try await client.decline(try card(approval("a")), in: "taf-coach")
        try expectEqual(try JSONDecoder().decode([String: String].self, from: transport.sent[0].body), ["answer": "declined", "session": "s1"])
        let drive = try card(#"{"key":"s1#d","session":"s1","component":{"id":"d","type":"drive","text":"Open your refunds and approve the first one","waits":"owner"}}"#)
        try expectEqual(drive.waitsForPerson, true)
        try expectEqual(drive.drawsAsChoice, false)
        try expectEqual(drive.grants, false)
        let declinedDrive: Void? = try? await client.decline(drive, in: "taf-coach")
        try expect(declinedDrive == nil, "a drive's card is never answered here")
        try expectEqual(transport.sent.count, 1)
        let confirm = try card(#"{"key":"s1#c","component":{"id":"c","type":"confirm","title":"Go on?","waits":"owner"}}"#)
        try expectEqual(confirm.drawsAsChoice, true)
    }),
    Test("KIFF's own Card lines and the Card's label are drawn through visible: a direction override can't reorder a cap", awaiting: {
        let d = try draft(#"{"id":"d","agent_id":"a","status":"draft","version":"1","label":"Refunds\u202e","cards":[{"lines":["Refund up to \u202e05€ each"],"grants":[{"action":"x"}]}]}"#)
        try expectEqual(d.lines(words), ["Refund up to 05€ each"])
        try expect(!d.cardTitle(words).unicodeScalars.contains { $0.value == 0x202E }, "the label's override is gone")
    }),
]

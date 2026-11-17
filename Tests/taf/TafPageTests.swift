import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

private func cloud(_ answers: [(Int, String)]) -> (CloudClient, CannedTransport) {
    let transport = CannedTransport(answers)
    return (CloudClient(transport: transport, session: session), transport)
}

private func english() throws -> Words { try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings")) }

/// What a taf's page reads for its Card and Setup tabs, as the iPad's.
let tafPageTests: [Test] = [
    Test("a taf's time zone words are tafs cloud's, as sent, and none when it sends none or blank") {
        func taf(_ fields: String) throws -> Home.Taf {
            try AccountClient.decoder.decode(Home.Taf.self, from: Data((#"{"kiff_agent":"a1","name":"Refunds","state":"idle""# + fields + "}").utf8))
        }
        let both = try taf(#","time_zone_words":"Times in Paris time","schedule_time_zone_words":"Its schedule runs on New York time""#)
        try expectEqual(both.timeZoneWords, "Times in Paris time")
        try expectEqual(both.scheduleTimeZoneWords, "Its schedule runs on New York time")
        let none = try taf("")
        try expectEqual(none.timeZoneWords, nil)
        try expectEqual(none.scheduleTimeZoneWords, nil)
        let blank = try taf(#","time_zone_words":"  ","schedule_time_zone_words":7"#)
        try expectEqual(blank.timeZoneWords, nil)
        try expectEqual(blank.scheduleTimeZoneWords, nil)
    },
    Test("a taf's job is tafs cloud's, else the live Cards it works under, as the iPad's") {
        let words = try english()
        let page = try AccountClient.decoder.decode(Home.Page.self, from: Data(tafWithCards.utf8))
        try expectEqual(page.tafs[0].job(words), "Every weekday at 9, lists inbox emails you haven't answered.")
        let bare = try AccountClient.decoder.decode(Home.Taf.self, from: Data(#"{"kiff_agent":"a1","name":"Bare","state":"idle","card":{"cards":[{"id":"c1","title":"A","rules":[]},{"id":"c2","title":"B","active":false,"rules":[]}]}}"#.utf8))
        try expectEqual(bare.job(words), "Works under 1 KIFF Card.")
    },
    Test("who issued the Card: You for whoever manages the taf, else the account's name, else the account") {
        let words = try english()
        try expectEqual(TafCard.issuer(manages: true, account: "Acme", words), "You")
        try expectEqual(TafCard.issuer(manages: false, account: "Acme", words), "Acme")
        try expectEqual(TafCard.issuer(manages: false, account: nil, words), "The account")
    },
    Test("how a Card counts each tool is KIFF's lines under its title; a tool with no title or no line is left out, never the Card") {
        let json = #"""
        {"id":"c1","title":"Refunds","rules":[],"counted":[
          {"tool":"stripe.refund","title":"Refund a payment","lines":["Each refund counts its amount.","  "]},
          {"tool":"stripe.list","title":"","lines":["x"]},
          {"tool":"stripe.read","title":"Read a payment","lines":[]},
          {"title":"no tool","lines":["y"]},
          7
        ]}
        """#
        let card = try AccountClient.decoder.decode(TafCard.self, from: Data(json.utf8))
        try expectEqual(card.counted.map(\.tool), ["stripe.refund"])
        try expectEqual(card.counted[0].title, "Refund a payment")
        try expectEqual(card.counted[0].lines, ["Each refund counts its amount."])
        let none = try AccountClient.decoder.decode(TafCard.self, from: Data(#"{"id":"c2","title":"B","counted":"no"}"#.utf8))
        try expectEqual(none.counted, [])
    },
    Test("the Setup's versions are counted as tafs cloud counts them, beside its title and summary") {
        let json = #"{"versions":{"title":"Changes to how it runs","summary":"v3 live · 2 earlier","live":3,"earlier":2}}"#
        let setup = try JSONDecoder().decode(TafSetup.self, from: Data(json.utf8))
        try expectEqual(setup.versions, TafSetup.Part(title: "Changes to how it runs", summary: "v3 live · 2 earlier"))
        try expectEqual(setup.versionsLive, 3)
        try expectEqual(setup.versionsEarlier, 2)
        let contract = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: ".shared/contracts/taf-setup.json"))) as? [String: Any]
        let answer = try JSONSerialization.data(withJSONObject: contract?["answer"] ?? [:])
        let first = try JSONDecoder().decode(TafSetup.self, from: answer)
        try expectEqual(first.versionsLive, nil)
        try expectEqual(first.versionsEarlier, 0)
        try expectEqual(first.memory?.title, "0 notes")
    },
    Test("an ask_coach card in a taf's thread carries the person's request; another card, or one with no words, carries none", awaiting: {
        let thread = #"""
        {"working":false,"items":[
          {"type":"card","card":{"key":"s1#ask-1","at":"2026-11-16T09:00:00Z","session":"s1","component":{"type":"ask_coach","id":"ask-1","text":"Run it at 8 instead of 9 on weekdays."}}},
          {"type":"card","card":{"key":"s1#ask-2","component":{"type":"ask_coach","id":"ask-2","text":"   "}}},
          {"type":"card","card":{"key":"s1#n","component":{"type":"notice","id":"n","text":"Done."}}}
        ]}
        """#
        let (client, _) = cloud([(200, thread)])
        let page = try await client.thread(of: "taf-1")
        let cards = page.items.compactMap { item -> Thread.Card? in if case .card(let card, _) = item { return card } else { return nil } }
        try expectEqual(cards.map(\.askCoach), ["Run it at 8 instead of 9 on weekdays.", nil, nil])
        try expectEqual(cards[0].id, "ask-1")
        try expect(cards[0].at != nil, "its time, to place it")
    }),
    Test("a taf's credits are tafs cloud's words, its runs read leniently, the next page added after them, and none from a tafs cloud without the read", awaiting: {
        let first = #"{"credits":120,"runs":3,"words":"120 credits this period","items":[{"run":"r1","at":"2026-11-16T09:00:00Z","credits":40,"counted":true,"words":"40 credits · 3 refunds","opens":true},{"run":"r2","at":"2026-11-15T09:00:00Z","credits":0,"counted":false,"why":"trial","words":"Trial · not counted"},{"run":"bad"}],"next":"cur 2"}"#
        let second = #"{"credits":120,"words":"120 credits this period","items":[{"run":"r2","at":"2026-11-15T09:00:00Z","credits":0,"counted":false,"words":"Trial · not counted"},{"run":"r3","at":"2026-11-14T09:00:00Z","credits":80,"counted":true,"words":"80 credits"}],"next":""}"#
        let (client, transport) = cloud([(200, first), (200, second), (404, #"{"error":"not_found"}"#)])
        guard var read = try await client.tafCredits(of: "taf 1") else { throw Failure(description: "not read") }
        try expectEqual(read.words, "120 credits this period")
        try expectEqual(read.items.map(\.run), ["r1", "r2"])
        try expectEqual(read.items[0].opens, true)
        try expectEqual(read.items[1].why, "trial")
        try expectEqual(read.next, "cur 2")
        guard let more = try await client.tafCredits(of: "taf 1", previous: true, after: "cur 2") else { throw Failure(description: "no more") }
        read.append(more)
        try expectEqual(read.items.map(\.run), ["r1", "r2", "r3"])
        try expectEqual(read.next, nil)
        try expectEqual(transport.sent.map(\.method), ["GET", "GET"])
        try expectEqual(transport.sent.map(\.path), ["/v1/usage/credits/tafs/taf%201", "/v1/usage/credits/tafs/taf%201?period=previous&after=cur%202"])
        let none = try await client.tafCredits(of: "taf-1")
        try expectEqual(none, nil)
    }),
    Test("a taf's notes are read, all of them on See all, named by their path; Forget deletes one, unsigned", awaiting: {
        let notes = #"{"notes":[{"id":"n1","path":"/customers/acme-corp.md","content":"Acme pays by card.","updated_at":"2026-11-16T09:00:00.000Z"},{"id":"n2","path":"/how-you-like-it.md","content":"Short replies.","updated_at":"2026-11-15T09:00:00Z"}]}"#
        let (client, transport) = cloud([(200, notes), (200, #"{"forgotten":"n1"}"#), (404, #"{"error":"not_found","words":"Gone."}"#)])
        let read = try await client.memory(of: "taf-1", all: true)
        try expectEqual(read.map(\.id), ["n1", "n2"])
        try expectEqual(read[0].title, "customers · acme corp")
        try expectEqual(read[1].byline("09:00"), "how you like it · 09:00")
        try await client.forget(note: "n1", of: "taf-1")
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["GET /v1/tafs/taf-1/memory?all=true", "DELETE /v1/tafs/taf-1/memory/n1"])
        try expectEqual(transport.sent[1].headers["Planque-Device-Signature"], nil)
        do {
            try await client.forget(note: "n9", of: "taf-1")
            throw Failure(description: "a refusal forgot")
        } catch let refusal as CloudRefusal {
            try expectEqual(refusal.status, 404)
        }
        let gone = TafMemory.without(read[0], in: read)
        try expectEqual(gone.map(\.id), ["n2"])
        try expectEqual(TafMemory.putting(read[0], backInto: gone).map(\.id), ["n1", "n2"])
        try expectEqual(TafMemory.putting(read[1], backInto: read).map(\.id), ["n1", "n2"])
    }),
]

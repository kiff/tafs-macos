import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

private let page = #"""
{"tafs":[],"setting_up":[
  {"name":"Refunds","kiff_agent":"agent_r","color":2,"discard":{"cards":["c1","c2"],"words":{"button":"Discard","title":"Discard Refunds?","text":"Its Cards are revoked.","yes":"Discard","no":"Keep it"}}},
  {"name":"Leads","kiff_agent":"agent_l","color":3,"finish":{"taf":"coach","session":"s1","words":"Finish setting up"}},
  {"name":"No words","kiff_agent":"agent_n","discard":{"cards":[],"words":{"button":" "}}},
  {"kiff_agent":"agent_bad"}
]}
"""#

private func english() throws -> Words { try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings")) }

let settingUpTests: [Test] = [
    Test("Home's tafs being set up read on their own; Discard only for their starter, and only with its button's words") {
        let read = try AccountClient.decoder.decode(Home.Page.self, from: Data(page.utf8))
        try expectEqual(read.settingUp.map(\.kiffAgent), ["agent_r", "agent_l", "agent_n"])
        try expectEqual(read.settingUp[0].discard?.cards, ["c1", "c2"])
        try expectEqual(read.settingUp[0].discard?.words.no, "Keep it")
        try expectEqual(read.settingUp[1].discard, nil)
        try expectEqual(read.settingUp[2].discard, nil)
    },
    Test("Discard is the key's POST to tafs cloud's discard, empty, named in tafs cloud's words") {
        let act = KeyAct.discardSettingUp("agent/r")
        try expectEqual(act.method + " " + act.path, "POST /v1/home/setting-up/agent%2Fr/discard")
        try expectEqual(act.body, Data())
        try expectEqual(act.title(try english(), device: "Discard Refunds?"), "Discard Refunds?")
    },
    Test("Discard signs first, then revokes its Cards and the ones a refusal named, then sends with the key's assertion", awaiting: {
        let read = try AccountClient.decoder.decode(Home.Page.self, from: Data(page.utf8))
        var steps: [String] = []
        let done = await SettingUpDiscard.discard(read.settingUp[0], cardsLeftBefore: ["c3", "c1"], words: try english(),
                                                  sign: { act, title in steps.append("sign \(act.path) \(title)"); return "A" },
                                                  revoke: { steps.append("revoke \($0)") }, send: { steps.append("send \($0)") })
        try expectEqual(steps, ["sign /v1/home/setting-up/agent_r/discard Discard Refunds?", "revoke c1", "revoke c2", "revoke c3", "send A"])
        try expectEqual(done.said, nil)
        try expectEqual(done.cardsLeft, [])
    }),
    Test("a closed sheet changes nothing; Approve on your phone says so; KIFF still holding Cards keeps them for the next try", awaiting: {
        let read = try AccountClient.decoder.decode(Home.Page.self, from: Data(page.utf8))
        let words = try english()
        var sent = 0
        let closed = await SettingUpDiscard.discard(read.settingUp[0], words: words, sign: { _, _ in throw CancellationError() },
                                                    revoke: { _ in sent += 1 }, send: { _ in sent += 1 })
        try expectEqual(closed.said, nil)
        try expectEqual(sent, 0)
        let phone = await SettingUpDiscard.discard(read.settingUp[0], words: words, sign: { _, _ in throw ApproveOnPhone() },
                                                   revoke: { _ in sent += 1 }, send: { _ in sent += 1 })
        try expectEqual(phone.said, words("approval.device_can_not_approve_approve"))
        try expectEqual(sent, 0)
        let held = await SettingUpDiscard.discard(read.settingUp[0], words: words, sign: { _, _ in "A" }, revoke: { _ in },
                                                  send: { _ in throw SettingUpDiscard.CardsInForce(cards: ["c9"]) })
        try expectEqual(held.said, words("card.kiff_did_not_revoke_cards", ["cards_left": "1"]))
        try expectEqual(held.cardsLeft, ["c9"])
    }),
    Test("tafs cloud's discard goes with the key's header and no body; its 409 cards_in_force names the Cards", awaiting: {
        let transport = CannedTransport([(200, #"{"discarded":true}"#), (409, #"{"error":"1 Card still in force","code":"cards_in_force","cards":["c9"]}"#)])
        let cloud = CloudClient(transport: transport, session: session)
        try await cloud.discardSettingUp("agent_r", assertion: "t=1,a=x")
        try expectEqual(transport.sent[0].headers[Passkeys.headerName], "t=1,a=x")
        try expectEqual(transport.sent[0].body, Data())
        do { try await cloud.discardSettingUp("agent_r", assertion: "t=2,a=y"); throw Failure(description: "taken") } catch let left as SettingUpDiscard.CardsInForce {
            try expectEqual(left.cards, ["c9"])
        }
    }),
]

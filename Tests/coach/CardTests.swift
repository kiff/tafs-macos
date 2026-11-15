import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

let cardsThread = #"""
{"working":false,"items":[
  {"type":"card","card":{"key":"s1:plan-1","session":"s1","component":{"id":"plan-1","type":"confirm","title":"Refunds up to €100","text":"It refunds on its own up to €100, and asks you above.","options":[{"label":"Agree","value":"agree"},{"label":"Change something","value":"change"},{"label":"","value":"x"},{"label":"No value"},7],"waits":"owner"}}},
  {"type":"card","card":{"key":"s1:plan-0","answer":{"state":"answered","words":"Agree","at":"2026-11-14T18:00:00Z"},"component":{"id":"plan-0","type":"confirm","options":[{"label":"Agree","value":"agree"}]}}},
  {"type":"card","card":{"key":"s1:approval-1","session":"s1","component":{"id":"approval-1","type":"approval","title":"Connect Qonto","options":[{"label":"Approve","value":"approved"}],"waits":"owner"}}},
  {"type":"card","card":{"key":"s1:signin-1","component":{"id":"signin-1","type":"sign_in","waits":"owner"}}},
  {"type":"card","card":{"component":{"type":"confirm"}}}
]}
"""#

private func cards() throws -> [Thread.Card] {
    try JSONDecoder().decode(Thread.Page.self, from: Data(cardsThread.utf8)).items.compactMap { if case .card(let card, _) = $0 { return card } else { return nil } }
}

private func cloud(_ answers: [(Int, String)]) -> (CloudClient, CannedTransport) {
    let transport = CannedTransport(answers)
    return (CloudClient(transport: transport, session: session), transport)
}

let coachCardTests: [Test] = [
    Test("a card is read with its words and its options, and an option that can't be read or answered is left out") {
        let all = try cards()
        try expectEqual(all.map(\.id), ["plan-1", "plan-0", "approval-1", "signin-1"])
        try expectEqual(all[0].title, "Refunds up to €100")
        try expectEqual(all[0].options, [.init(label: "Agree", value: "agree"), .init(label: "Change something", value: "change")])
        try expectEqual(all[0].waitsForPerson, true)
        try expectEqual(all[0].isChoice, true)
        try expectEqual(all[1].answered, "Agree")
        try expectEqual(all[1].waitsForPerson, false)
    },
    Test("a card whose answer is a signature is never a choice to tap, whatever options it carries") {
        let all = try cards()
        try expectEqual(all[2].grants, true)
        try expectEqual(all[2].isChoice, false)
        try expectEqual(all[3].grants, true)
        try expectEqual(all[3].isChoice, false)
    },
    Test("an answer is one of the card's own options, sent as data to that card in its chat", awaiting: {
        let all = try cards()
        let (client, transport) = cloud([(200, "{}")])
        try await client.answer(all[0], with: all[0].options[0], in: "taf-coach")
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "POST /v1/tafs/taf-coach/components/plan-1/answer")
        try expectEqual(try JSONDecoder().decode([String: String].self, from: transport.sent[0].body), ["answer": "agree", "session": "s1"])
    }),
    Test("nothing is sent for an option that isn't the card's, or for an approval or a sign-in", awaiting: {
        let all = try cards()
        let (client, transport) = cloud([(200, "{}"), (200, "{}"), (200, "{}")])
        let attempts: [(Thread.Card, Thread.Card.Option)] = [
            (all[0], .init(label: "Approve", value: "approved")),
            (all[2], all[2].options[0]),
            (all[3], .init(label: "Signed in", value: "signed in")),
        ]
        for (card, option) in attempts {
            do { try await client.answer(card, with: option, in: "taf-coach"); throw Failure(description: "\(card.id) was answered") } catch let refusal as CloudRefusal {
                try expectEqual(refusal.code, "not_this_cards_answer")
            }
        }
        try expectEqual(transport.sent.count, 0)
    }),
]

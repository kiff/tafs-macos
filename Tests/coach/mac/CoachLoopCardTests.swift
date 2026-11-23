import Foundation

/// The loop card in a taf's own chat (kiff/tafs `docs/chat.md`, "The loop card"; the iPad's `LoopCardView`, tafs#1861;
/// Android's `answerTafCard`): kiff/agents' `confirm` with id `tafs-loop-N` and `loop`, in tafs cloud's words ("Still
/// reading", Read on / Stop here). On this Mac a taf's chat is `CoachModel` on that taf, which draws a choice that waits
/// on the owner and sends its answer to the taf's own route: these tests pin that the loop card is one.
private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

private let loopComponent = #"{"type":"confirm","id":"tafs-loop-12","waits":"owner","loop":{"tool":"list_disputes","pages":10},"title":"Still reading","text":"Read 10 pages of List disputes, and there's more.","options":[{"label":"Read on","value":"tafs_loop_continue"},{"label":"Stop here","value":"tafs_loop_summarise"}]}"#

private let loopThread = #"{"working":false,"items":[{"type":"card","card":{"key":"s1:tafs-loop-12","session":"s1","component":"# + loopComponent + "}}]}"
private let answeredThread = #"{"working":false,"items":[{"type":"card","card":{"key":"s1:tafs-loop-12","session":"s1","answer":{"state":"answered","words":"Stop here","at":"2026-11-23T15:00:00Z"},"component":"# + loopComponent + "}}]}"

@MainActor
private func cards(_ model: CoachModel) -> [Thread.Card] {
    guard case .loaded(_, let page) = model.state else { return [] }
    return page.items.compactMap { if case .card(let card, _) = $0 { return card } else { return nil } }
}

let coachLoopCardMacTests: [Test] = [
    Test("a taf's chat draws the loop card as a choice in tafs cloud's words, and its answer goes to the taf's route once", awaiting: { @MainActor in
        let transport = CannedTransport([(200, loopThread), (200, #"{"session":"s1","run":"r1","status":"running"}"#), (200, answeredThread), (200, answeredThread)])
        let model = CoachModel(cloud: CloudClient(transport: transport, session: session), taf: Coach(id: "taf-1", name: "Refunds"), sleep: { _ in })
        await model.load()
        guard let card = cards(model).first else { throw Failure(description: "the loop card wasn't read") }
        try expect(card.isChoice && card.waitsForPerson && !card.grants, "a choice that waits on the owner, which grants nothing")
        try expectEqual(card.title, "Still reading")
        try expectEqual(card.options.map(\.label), ["Read on", "Stop here"])
        // Stop here: its value, with the card's own chat, to the taf's route.
        await model.answer(card, with: card.options[1])
        let posts = transport.sent.filter { $0.method == "POST" }
        try expectEqual(posts.map(\.path), ["/v1/tafs/taf-1/components/tafs-loop-12/answer"])
        let body = (try? JSONSerialization.jsonObject(with: posts[0].body)) as? [String: String]
        try expectEqual(body, ["answer": "tafs_loop_summarise", "session": "s1"])
        // Answered: it says so, and a second tap sends nothing.
        try expectEqual(cards(model).first?.answered, "Stop here")
        if let again = cards(model).first { await model.answer(again, with: again.options[0]) }
        try expectEqual(transport.sent.filter { $0.method == "POST" }.count, 1)
    }),
    Test("a loop card that no longer waits (409) is read again as it is, with nothing said", awaiting: { @MainActor in
        let transport = CannedTransport([(200, loopThread), (409, #"{"error":"not_waiting"}"#), (200, answeredThread)])
        let model = CoachModel(cloud: CloudClient(transport: transport, session: session), taf: Coach(id: "taf-1", name: "Refunds"), sleep: { _ in })
        await model.load()
        guard let card = cards(model).first else { throw Failure(description: "the loop card wasn't read") }
        await model.answer(card, with: card.options[0])
        try expectEqual(model.notAnswered[card.key], nil)
        try expectEqual(cards(model).first?.answered, "Stop here")
    }),
]

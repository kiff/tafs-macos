import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
/// The same thread once the first card is answered: tafs cloud's answer sits beside the card's
/// component, as `{key, session, answer, component}`.
private let answeredThread = cardsThread.replacingOccurrences(of: #"{"key":"s1:plan-1","session":"s1","component":"#,
                                                              with: #"{"key":"s1:plan-1","session":"s1","answer":{"state":"answered","words":"Agree","at":"2026-11-15T00:30:00Z"},"component":"#)

@MainActor
private func make(_ answers: [(Int, String)]) async -> (CoachModel, CannedTransport) {
    let transport = CannedTransport([(200, setupAnswer), (200, cardsThread)] + answers)
    let model = CoachModel(cloud: CloudClient(transport: transport, session: session), sleep: { _ in })
    await model.load()
    return (model, transport)
}

@MainActor
private func cards(_ model: CoachModel) -> [Thread.Card] {
    guard case .loaded(_, let page) = model.state else { return [] }
    return page.items.compactMap { if case .card(let card, _) = $0 { return card } else { return nil } }
}

private func posts(_ transport: CannedTransport) -> [HTTPRequest] { transport.sent.filter { $0.method == "POST" } }

let coachCardMacTests: [Test] = [
    Test("answering a choice sends it once, and the thread then shows what was answered", awaiting: { @MainActor in
        let (model, transport) = await make([(200, "{}"), (200, answeredThread)])
        let card = cards(model)[0]
        await model.answer(card, with: card.options[0])
        try expectEqual(posts(transport).map(\.path), ["/v1/tafs/taf%2Dcoach/components/plan%2D1/answer"])
        try expectEqual(cards(model)[0].answered, "Agree")
        try expectEqual(model.answering, nil)
    }),
    Test("a card that no longer waits is read again as it is, with no error shown", awaiting: { @MainActor in
        let (model, transport) = await make([(409, #"{"error":"not_waiting"}"#), (200, answeredThread)])
        let card = cards(model)[0]
        await model.answer(card, with: card.options[1])
        try expectEqual(model.notAnswered[card.key], nil)
        try expectEqual(cards(model)[0].answered, "Agree")
        try expectEqual(posts(transport).count, 1)
    }),
    Test("an answer tafs cloud refuses stays on the card with its reason, and the card still waits", awaiting: { @MainActor in
        let (model, _) = await make([(400, #"{"error":"bad_answer","words":"That isn't one of this card's answers."}"#)])
        let card = cards(model)[0]
        await model.answer(card, with: card.options[0])
        try expectEqual(model.notAnswered[card.key], "That isn't one of this card's answers.")
        try expectEqual(cards(model)[0].waitsForPerson, true)
    }),
    Test("an approval, a sign-in and a card already answered are never answered from here", awaiting: { @MainActor in
        let (model, transport) = await make([(200, "{}"), (200, "{}"), (200, "{}")])
        let all = cards(model)
        await model.answer(all[2], with: all[2].options[0])
        await model.answer(all[3], with: .init(label: "Signed in", value: "signed in"))
        await model.answer(all[1], with: all[1].options[0])
        try expectEqual(posts(transport).count, 0)
    }),
    Test("the screenshots: Coach's cards in three languages", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr", "pt"] {
            let (model, _) = await make([])
            let view = CoachView(model: model).environment(\.words, Words.load(folder: strings, preferred: [language]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 620)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("coach-cards-\(language).png"))
        }
    }),
]

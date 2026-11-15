import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
/// The same thread once the questions are answered: tafs cloud's answer beside the card.
private let answeredQuestions = questionsThread.replacingOccurrences(of: #"{"key":"s1:q-1","session":"s1","component":"#,
                                                                      with: #"{"key":"s1:q-1","session":"s1","answer":{"state":"answered","words":"Test mode · Stripe"},"component":"#)

/// Canned answers that can run something while a card's answer is on its way.
private final class AnsweringTransport: Transport, @unchecked Sendable {
    private let canned: CannedTransport
    var whileAnswering: () async -> Void = {}
    init(_ answers: [(Int, String)]) { canned = CannedTransport(answers) }
    var sent: [HTTPRequest] { canned.sent }
    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        if request.path.hasSuffix("/answer") { await whileAnswering() }
        return try await canned.send(request)
    }
}

@MainActor
private func coach(_ answers: [(Int, String)], thread: String = questionsThread) async -> (CoachModel, AnsweringTransport) {
    let transport = AnsweringTransport([(200, setupAnswer), (200, noChats), (200, thread)] + answers)
    let model = CoachModel(cloud: CloudClient(transport: transport, session: session), sleep: { _ in })
    await model.load()
    return (model, transport)
}

@MainActor
private func shown(_ model: CoachModel) -> [Thread.Card] {
    guard case .loaded(_, let page) = model.state else { return [] }
    return page.items.compactMap { if case .card(let card, _) = $0 { return card } else { return nil } }
}

private func posts(_ transport: AnsweringTransport) -> [HTTPRequest] { transport.sent.filter { $0.method == "POST" } }

private let both: [String: QuestionAnswers.Answer] = ["mode": .choice("test"), "apps": .choices(["stripe"])]

let coachQuestionsMacTests: [Test] = [
    Test("answering the questions sends them once, and the thread then shows the answers", awaiting: { @MainActor in
        let (model, transport) = await coach([(200, answeredAnswer), (200, answeredQuestions)])
        let card = shown(model)[0]
        await model.answer(card, questions: both, mayUseCoach: true)
        try expectEqual(posts(transport).map(\.path), ["/v1/tafs/taf-coach/components/q-1/answer"])
        try expectEqual(shown(model)[0].answered, "Test mode · Stripe")
        try expectEqual(model.answering, nil)
    }),
    Test("a questions card that no longer waits is read again as it is; a refusal stays on the card with why", awaiting: { @MainActor in
        let (gone, _) = await coach([(409, #"{"error":"not_waiting"}"#), (200, answeredQuestions)])
        let card = shown(gone)[0]
        await gone.answer(card, questions: both, mayUseCoach: true)
        try expectEqual(gone.notAnswered[card.key], nil)
        try expectEqual(shown(gone)[0].answered, "Test mode · Stripe")
        let (refused, _) = await coach([(400, #"{"error":"bad_answer","words":"That isn't one of this card's answers."}"#)])
        await refused.answer(card, questions: both, mayUseCoach: true)
        try expectEqual(refused.notAnswered[card.key], "That isn't one of this card's answers.")
        try expectEqual(shown(refused)[0].waitsForPerson, true)
    }),
    Test("an answer tafs cloud sends that doesn't read, or a failure that isn't a refusal, says the answer didn't reach Setup", awaiting: { @MainActor in
        let (model, _) = await coach([(200, "{}")])
        let card = shown(model)[0]
        await model.answer(card, questions: both, mayUseCoach: true)
        try expectEqual(model.notAnswered[card.key], Words.app("coach.answer_did_not_reach_setup"))
    }),
    Test("an answer that comes back after sign-out is the session before's: nothing is read or said, as the iPad's accountGeneration", awaiting: { @MainActor in
        let (model, transport) = await coach([(400, #"{"error":"bad_answer","words":"No."}"#), (200, answeredQuestions)])
        transport.whileAnswering = { await MainActor.run { model.signedOut() } }
        let card = shown(model)[0]
        let before = transport.sent.count
        await model.answer(card, questions: both, mayUseCoach: true)
        try expectEqual(transport.sent.count, before + 1)
        try expectEqual(model.notAnswered[card.key], nil)
    }),
    Test("nothing is sent by someone who may not use Coach, from a taf's own chat, with a question unanswered, or to a card answered", awaiting: { @MainActor in
        let (model, transport) = await coach([(200, answeredAnswer), (200, answeredAnswer)])
        let all = shown(model)
        // As the iPad's `mayUseCoach` (Keyboard.swift:70): Coach isn't theirs to answer.
        await model.answer(all[0], questions: both, mayUseCoach: false)
        await model.answer(all[0], questions: ["mode": .choice("test")], mayUseCoach: true)
        await model.answer(all[1], questions: ["mode": .choice("test")], mayUseCoach: true)
        try expectEqual(posts(transport).count, 0)
        // A taf's own chat answers no card, as the iPad's `guard let s = setupTaf` (AppModel.swift:8225).
        let tafTransport = AnsweringTransport([(200, questionsThread), (200, answeredAnswer)])
        let taf = CoachModel(cloud: CloudClient(transport: tafTransport, session: session), taf: Coach(id: "taf-2", name: "Refunds"), sleep: { _ in })
        await taf.load()
        guard let tafCard = shown(taf).first else { throw Failure(description: "no card") }
        await taf.answer(tafCard, questions: both, mayUseCoach: true)
        try expectEqual(posts(tafTransport).count, 0)
    }),
    Test("an answer goes to the card its id names now, as the iPad's cardRef: the one waiting, in its own chat", awaiting: { @MainActor in
        // The same id in two chats: answered in s0, asked again in s1.
        let again = #"""
        {"working":false,"items":[
          {"type":"card","card":{"key":"s0:q-1","session":"s0","answer":{"state":"answered","words":"Live"},"component":{"id":"q-1","type":"questions","questions":[{"id":"mode","text":"Test mode first?","options":[{"value":"test","label":"Test mode"},{"value":"live","label":"Live"}]}]}}},
          {"type":"card","card":{"key":"s1:q-1","session":"s1","component":{"id":"q-1","type":"questions","questions":[{"id":"mode","text":"Test mode first?","options":[{"value":"test","label":"Test mode"},{"value":"live","label":"Live"}]}]}}}
        ]}
        """#
        let (model, transport) = await coach([(400, #"{"error":"bad_answer","words":"No."}"#)], thread: again)
        let older = shown(model)[0]
        try expectEqual(model.refKey(older), "s1:q-1")
        await model.answer(older, questions: ["mode": .choice("test")], mayUseCoach: true)
        try expectEqual(try JSONDecoder().decode([String: AnyDecodable].self, from: posts(transport)[0].body)["session"]?.text, "s1")
        try expectEqual(model.notAnswered["s1:q-1"], "No.")
        try expectEqual(model.notAnswered["s0:q-1"], nil)
    }),
    Test("a questions card with no answer is answered whatever its waits says, as the iPad's QuestionsCard", awaiting: { @MainActor in
        let quiet = questionsThread.replacingOccurrences(of: #""waits":"owner","questions""#, with: #""questions""#)
        let (model, transport) = await coach([(200, answeredAnswer), (200, answeredQuestions)], thread: quiet)
        let card = shown(model)[0]
        try expectEqual(card.waitsForPerson, false)
        await model.answer(card, questions: both, mayUseCoach: true)
        try expectEqual(posts(transport).count, 1)
    }),
    Test("the screenshot: Coach's questions card as it waits", awaiting: { @MainActor in
        let (model, _) = await coach([])
        let card = shown(model)[0]
        let view = QuestionsCard(model: model, card: card, mayUseCoach: true)
            .padding(20).background(Theme.background)
            .environment(\.words, Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"]))
        guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 680, height: 560)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: "build/screenshots"), withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: "build/screenshots/coach-questions-en.png"))
    }),
]

/// A JSON value read as text when it is text, for checking one field of a body.
private struct AnyDecodable: Decodable {
    let text: String?
    init(from decoder: Decoder) throws { text = try? decoder.singleValueContainer().decode(String.self) }
}

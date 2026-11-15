import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

/// A questions card waiting, one answered, and one with a question that doesn't read.
let questionsThread = #"""
{"working":false,"items":[
  {"type":"card","card":{"key":"s1:q-1","session":"s1","component":{"id":"q-1","type":"questions","title":"Refunds","text":"Two things before I set it up.","waits":"owner","questions":[
    {"id":"mode","text":"Test mode first?","options":[{"value":"test","label":"Test mode","description":"Nothing real moves"},{"value":"live","label":"Live"}],"note":"You can switch later."},
    {"id":"apps","text":"Which apps?","multi":true,"options":[{"value":"stripe","label":"Stripe"},{"value":"qonto","label":"Qonto"}]}]}}},
  {"type":"card","card":{"key":"s1:q-0","answer":{"state":"answered","words":"Test mode · Stripe"},"component":{"id":"q-0","type":"questions","questions":[{"id":"mode","text":"Test mode first?","options":[{"value":"test","label":"Test mode"}]}]}}},
  {"type":"card","card":{"key":"s1:q-2","component":{"id":"q-2","type":"questions","waits":"owner","questions":[{"id":"ok","text":"Fine?","options":[{"value":"y","label":"Yes"}]},{"text":"no id","options":[]}]}}}
]}
"""#

private func cards() throws -> [Thread.Card] {
    try JSONDecoder().decode(Thread.Page.self, from: Data(questionsThread.utf8)).items.compactMap { if case .card(let card, _) = $0 { return card } else { return nil } }
}

private func cloud(_ answers: [(Int, String)]) -> (CloudClient, CannedTransport) {
    let transport = CannedTransport(answers)
    return (CloudClient(transport: transport, session: session), transport)
}

let coachQuestionTests: [Test] = [
    Test("a questions card is read with each question as Coach wrote it; one that doesn't read leaves the card none") {
        let all = try cards()
        try expectEqual(all.map(\.id), ["q-1", "q-0", "q-2"])
        try expectEqual(all[0].questions.map(\.id), ["mode", "apps"])
        try expectEqual(all[0].questions[0].options.map(\.label), ["Test mode", "Live"])
        try expectEqual(all[0].questions[0].options[0].description, "Nothing real moves")
        try expectEqual(all[0].questions[0].note, "You can switch later.")
        try expectEqual(all[0].questions[1].multi, true)
        try expectEqual(all[0].isQuestions, true)
        try expectEqual(all[0].isChoice, false)
        try expectEqual(all[1].answered, "Test mode · Stripe")
        // Never answered in part: a card with a question that doesn't read has none to answer.
        try expectEqual(all[2].questions, [])
        try expectEqual(all[2].isQuestions, false)
    },
    Test("a question's answer is a choice, several on a multi question, or the person's own words, never both, as the iPad's QuestionSelection") {
        let q = try cards()[0].questions
        var s = QuestionSelection()
        try expectEqual(s.answers(q), nil)
        s.pick(q[0], "test")
        s.pick(q[0], "live")
        try expectEqual(s.answer(q[0]), .choice("live"))
        s.pick(q[1], "stripe")
        s.pick(q[1], "qonto")
        s.pick(q[1], "stripe")
        try expectEqual(s.answer(q[1]), .choices(["qonto"]))
        // Own words clear the picks; a blank answer is none; picking closes the own field.
        s.toggleOwn(q[0])
        try expectEqual(s.answer(q[0]), nil)
        s.own["mode"] = "  Only on weekdays "
        try expectEqual(s.answer(q[0]), .own("Only on weekdays"))
        try expectEqual(s.answers(q), ["mode": .own("Only on weekdays"), "apps": .choices(["qonto"])])
        s.pick(q[0], "test")
        try expectEqual(s.answer(q[0]), .choice("test"))
        // A multi question's choices are in Coach's order, whatever order they were picked in.
        s.pick(q[1], "stripe")
        try expectEqual(s.answer(q[1]), .choices(["stripe", "qonto"]))
    },
    Test("the answers are sent as data to that card in its chat, each as the iPad's CardAnswerValue", awaiting: {
        let card = try cards()[0]
        let (client, transport) = cloud([(200, "{}")])
        try await client.answer(card, questions: ["mode": .choice("test"), "apps": .choices(["stripe", "qonto"])], in: "taf coach")
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "POST /v1/tafs/taf%20coach/components/q-1/answer")
        try expectEqual(String(decoding: transport.sent[0].body, as: UTF8.self),
                        #"{"answer":{"apps":{"values":["stripe","qonto"]},"mode":{"value":"test"}},"session":"s1"}"#)
        let (other, own) = cloud([(200, "{}")])
        try await other.answer(card, questions: ["mode": .own("Weekdays"), "apps": .choice("stripe")], in: "taf-coach")
        try expectEqual(String(decoding: own.sent[0].body, as: UTF8.self), #"{"answer":{"apps":{"value":"stripe"},"mode":{"own":"Weekdays"}},"session":"s1"}"#)
    }),
    Test("nothing is sent with a question unanswered or one the card doesn't ask, nor to a card that isn't questions", awaiting: {
        let all = try cards()
        let (client, transport) = cloud([(200, "{}"), (200, "{}"), (200, "{}")])
        let attempts: [(Thread.Card, [String: QuestionAnswers.Answer])] = [
            (all[0], ["mode": .choice("test")]),
            (all[0], ["mode": .choice("test"), "apps": .choice("stripe"), "extra": .own("x")]),
            (all[2], ["ok": .choice("y")]),
        ]
        for (card, answers) in attempts {
            do { try await client.answer(card, questions: answers, in: "taf-coach"); throw Failure(description: "\(card.id) was answered") } catch let refusal as CloudRefusal {
                try expectEqual(refusal.code, "not_this_cards_answer")
            }
        }
        try expectEqual(transport.sent.count, 0)
    }),
]

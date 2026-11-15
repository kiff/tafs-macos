import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

/// A questions card waiting, one answered, and one with a question that doesn't read, which
/// isn't read at all.
let questionsThread = #"""
{"working":false,"items":[
  {"type":"card","card":{"key":"s1:q-1","session":"s1","component":{"id":"q-1","type":"questions","title":"Refunds","text":"Two things before I set it up.","waits":"owner","questions":[
    {"id":"mode","text":"Test mode first?","options":[{"value":"test","label":"Test mode","description":"Nothing real moves"},{"value":"live","label":"Live"}],"note":"You can switch later."},
    {"id":"apps","text":"Which apps?","multi":true,"options":[{"value":"stripe","label":"Stripe"},{"value":"qonto","label":"Qonto"}]}]}}},
  {"type":"card","card":{"key":"s1:q-0","answer":{"state":"answered","words":"Test mode · Stripe"},"component":{"id":"q-0","type":"questions","questions":[{"id":"mode","text":"Test mode first?","options":[{"value":"test","label":"Test mode"}]}]}}},
  {"type":"card","card":{"key":"s1:q-2","component":{"id":"q-2","type":"questions","waits":"owner","questions":[{"id":"ok","text":"Fine?","options":[{"value":"y","label":"Yes"}]},{"text":"no id","options":[]}]}}}
]}
"""#

/// tafs cloud's answer to a card's answer: the chat it's in and the run that goes on.
let answeredAnswer = #"{"session":"s2","run":"run_1","status":"running"}"#

private func cards() throws -> [Thread.Card] {
    try JSONDecoder().decode(Thread.Page.self, from: Data(questionsThread.utf8)).items.compactMap { if case .card(let card, _) = $0 { return card } else { return nil } }
}

private func cloud(_ answers: [(Int, String)]) -> (CloudClient, CannedTransport) {
    let transport = CannedTransport(answers)
    return (CloudClient(transport: transport, session: session), transport)
}

let coachQuestionTests: [Test] = [
    Test("a questions card is read with each question as Coach wrote it; one with a question that doesn't read isn't read, as the iPad's LenientShown") {
        let all = try cards()
        try expectEqual(all.map(\.id), ["q-1", "q-0"])
        try expectEqual(all[0].questions.map(\.id), ["mode", "apps"])
        try expectEqual(all[0].questions[0].options.map(\.label), ["Test mode", "Live"])
        try expectEqual(all[0].questions[0].options[0].description, "Nothing real moves")
        try expectEqual(all[0].questions[0].note, "You can switch later.")
        try expectEqual(all[0].questions[1].multi, true)
        try expectEqual(all[0].isQuestions, true)
        try expectEqual(all[0].isChoice, false)
        try expectEqual(all[1].answered, "Test mode · Stripe")
        // `questions` that isn't a list drops the card too; `null` is none, and the card stays.
        let other = #"{"working":false,"items":[{"type":"card","card":{"key":"a","component":{"id":"a","type":"questions","questions":7}}},{"type":"card","card":{"key":"b","component":{"id":"b","type":"questions","questions":null,"waits":"owner"}}},{"type":"card","card":{"key":"c","component":{"id":"c","type":"questions","questions":[{"id":"x","text":"X?","options":[],"multi":"yes"}]}}}]}"#
        let read = try JSONDecoder().decode(Thread.Page.self, from: Data(other.utf8)).items.compactMap { item -> Thread.Card? in if case .card(let card, _) = item { return card } else { return nil } }
        try expectEqual(read.map(\.id), ["b"])
        try expectEqual(read[0].isQuestions, false)
    },
    Test("a recorded answer reads as the iPad's CardAnswer: any of state, words or by that isn't text leaves the card unanswered; no state is answered") {
        func card(_ answer: String) throws -> Thread.Card? {
            let page = #"{"working":false,"items":[{"type":"card","card":{"key":"k","answer":"# + answer + #","component":{"id":"k","type":"confirm","waits":"owner","options":[{"label":"Agree","value":"agree"}]}}}]}"#
            return try JSONDecoder().decode(Thread.Page.self, from: Data(page.utf8)).items.compactMap { item -> Thread.Card? in if case .card(let c, _) = item { return c } else { return nil } }.first
        }
        for bad in [#"{"state":5,"words":"Agree"}"#, #"{"state":"answered","words":7}"#, #"{"state":"answered","words":"Agree","by":5}"#] {
            let c = try card(bad)
            try expectEqual(c?.answerState, nil)
            try expectEqual(c?.answered, nil)
            try expectEqual(c?.waitsForPerson, true)
        }
        let noState = try card(#"{"words":"Agree","by":"you@acme.example"}"#)
        try expectEqual(noState?.answerState, "answered")
        try expectEqual(noState?.answered, "Agree")
        let noWords = try card(#"{"state":"answered"}"#)
        try expectEqual(noWords?.answerState, "answered")
        try expectEqual(noWords?.answered, nil)
        try expectEqual(noWords?.waitsForPerson, false)
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
        let (client, transport) = cloud([(200, answeredAnswer)])
        let answered = try await client.answer(card, questions: ["mode": .choice("test"), "apps": .choices(["stripe", "qonto"])], in: "taf coach")
        try expectEqual(answered, CardAnswered(session: "s2", run: "run_1", status: "running"))
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "POST /v1/tafs/taf%20coach/components/q-1/answer")
        try expectEqual(String(decoding: transport.sent[0].body, as: UTF8.self),
                        #"{"answer":{"apps":{"values":["stripe","qonto"]},"mode":{"value":"test"}},"session":"s1"}"#)
        let (other, own) = cloud([(200, answeredAnswer)])
        _ = try await other.answer(card, questions: ["mode": .own("Weekdays"), "apps": .choice("stripe")], in: "taf-coach")
        try expectEqual(String(decoding: own.sent[0].body, as: UTF8.self), #"{"answer":{"apps":{"value":"stripe"},"mode":{"own":"Weekdays"}},"session":"s1"}"#)
    }),
    Test("an answer tafs cloud sends that isn't CardAnswered is unreadable, as the iPad's strict send", awaiting: {
        let card = try cards()[0]
        for body in ["{}", #"{"session":"s1","run":7,"status":"running"}"#] {
            let (client, _) = cloud([(200, body)])
            do { _ = try await client.answer(card, questions: ["mode": .choice("test"), "apps": .choice("stripe")], in: "taf-coach"); throw Failure(description: "read \(body)") } catch KIFFError.unreadable {}
        }
    }),
    Test("nothing is sent with a question unanswered or one the card doesn't ask, nor to a card that isn't questions", awaiting: {
        let all = try cards()
        let (client, transport) = cloud([(200, answeredAnswer), (200, answeredAnswer), (200, answeredAnswer)])
        let confirm = try JSONDecoder().decode(Thread.Page.self, from: Data(cardsThread.utf8)).items.compactMap { item -> Thread.Card? in if case .card(let c, _) = item { return c } else { return nil } }[0]
        let attempts: [(Thread.Card, [String: QuestionAnswers.Answer])] = [
            (all[0], ["mode": .choice("test")]),
            (all[0], ["mode": .choice("test"), "apps": .choice("stripe"), "extra": .own("x")]),
            (confirm, ["mode": .choice("test")]),
        ]
        for (card, answers) in attempts {
            do { _ = try await client.answer(card, questions: answers, in: "taf-coach"); throw Failure(description: "\(card.id) was answered") } catch let refusal as CloudRefusal {
                try expectEqual(refusal.code, "not_this_cards_answer")
            }
        }
        try expectEqual(transport.sent.count, 0)
    }),
]

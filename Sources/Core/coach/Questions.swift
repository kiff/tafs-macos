import Foundation

extension Thread.Card {
    /// One of several questions Coach asks at once, as the iPad's `SetupComponent.Question`
    /// (`Model/SetupComponent.swift:23-35`): every word is Coach's. The app adds the person's
    /// own answer and "Chat about this" to every card.
    struct Question: Decodable, Equatable, Hashable {
        struct Choice: Decodable, Equatable, Hashable {
            let value: String
            let label: String
            var description: String?
        }
        let id: String
        let text: String
        let options: [Choice]
        /// Several may be picked.
        var multi: Bool?
        var note: String?
    }

    /// A questions card the person can answer here: its questions all read.
    var isQuestions: Bool { type == "questions" && !questions.isEmpty }
}

/// The person's answers to a questions card, as the iPad's `QuestionAnswers`
/// (`Model/QuestionAnswers.swift:7-12`): each a choice of Coach's, several (a multi question),
/// or the person's own words.
enum QuestionAnswers {
    enum Answer: Equatable {
        case choice(String)
        case choices([String])
        case own(String)
    }

    /// One answer as tafs cloud takes it, as the iPad's `CardAnswerValue.QuestionAnswer`
    /// (`KIFF/TafsCloud.swift:1367-1371`): `{"value"}`, `{"values"}` or `{"own"}`.
    struct Sent: Encodable, Equatable {
        var value: String?
        var values: [String]?
        var own: String?
    }

    static func sent(_ answer: Answer) -> Sent {
        switch answer {
        case .choice(let v): return Sent(value: v)
        case .choices(let vs): return Sent(values: vs)
        case .own(let text): return Sent(own: text)
        }
    }
}

/// What the person has picked on a questions card so far, as the iPad's `QuestionSelection`
/// (`Model/QuestionAnswers.swift:62-99`). A question's answer is one of its choices (several,
/// on a multi question) or the person's own words, never both: opening "Something else…"
/// clears the picks, and picking a choice closes the own field.
struct QuestionSelection: Equatable {
    var picked: [String: Set<String>] = [:]
    var own: [String: String] = [:]
    var ownOpen: Set<String> = []

    mutating func toggleOwn(_ q: Thread.Card.Question) {
        if ownOpen.contains(q.id) { ownOpen.remove(q.id) } else { ownOpen.insert(q.id); picked[q.id] = [] }
    }

    mutating func pick(_ q: Thread.Card.Question, _ value: String) {
        if q.multi == true {
            var set = picked[q.id] ?? []
            if set.contains(value) { set.remove(value) } else { set.insert(value) }
            picked[q.id] = set
        } else {
            picked[q.id] = [value]
        }
        ownOpen.remove(q.id)
    }

    /// The question's answer, if it has one.
    func answer(_ q: Thread.Card.Question) -> QuestionAnswers.Answer? {
        if ownOpen.contains(q.id) {
            let words = (own[q.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return words.isEmpty ? nil : .own(words)
        }
        let chosen = q.options.map(\.value).filter { picked[q.id]?.contains($0) == true }
        if chosen.isEmpty { return nil }
        return q.multi == true ? .choices(chosen) : .choice(chosen[0])
    }

    /// Every question's answer, as the iPad's `QuestionsCard.send`: nil until each has one.
    func answers(_ questions: [Thread.Card.Question]) -> [String: QuestionAnswers.Answer]? {
        var answers: [String: QuestionAnswers.Answer] = [:]
        for q in questions { if let a = answer(q) { answers[q.id] = a } }
        return answers.count == questions.count ? answers : nil
    }
}

/// A card's answer as tafs cloud takes it, as the iPad's `CardAnswered` (`KIFF/TafsCloud.swift:1355-1359`):
/// the chat it's in, and the run that waited on it, which goes on.
struct CardAnswered: Decodable, Equatable {
    let session: String
    let run: String
    let status: String
}

extension CloudClient {
    /// Answers a questions card, as data (`POST …/components/{id}/answer`), as the iPad's
    /// `answerCard` with `CardAnswerValue.questions` (`KIFF/TafsCloud.swift:1385-1389`): one
    /// answer for each of its questions, and nothing else. It grants nothing, so it isn't signed.
    /// An answer that isn't `CardAnswered` is unreadable, as the iPad's `send` (`:2834`).
    func answer(_ card: Thread.Card, questions answers: [String: QuestionAnswers.Answer], in taf: String) async throws -> CardAnswered {
        guard card.isQuestions, !card.grants, Set(answers.keys) == Set(card.questions.map(\.id)) else {
            throw CloudRefusal(status: 0, body: Data(#"{"error":"not_this_cards_answer"}"#.utf8))
        }
        struct Body: Encodable { let answer: [String: QuestionAnswers.Sent]; let session: String? }
        let body = try await post("/v1/tafs/\(Self.escaped(taf))/components/\(Self.escaped(card.id))/answer",
                                  body: Body(answer: answers.mapValues(QuestionAnswers.sent), session: card.session))
        guard let answered = try? JSONDecoder().decode(CardAnswered.self, from: body) else { throw KIFFError.unreadable }
        return answered
    }
}

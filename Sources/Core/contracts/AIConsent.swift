import Foundation

/// What tafs cloud answers the apps. Each shape here is read by the `contracts` tests from
/// kiff/tafs's own fixtures at the pin (docs/shared.md), so a changed answer fails in CI.
enum TafsCloud {
    /// The code of a refusal for want of the AI-data consent.
    static let aiConsentRequired = "ai_consent_required"

    /// The AI-data consent: before anything a person writes reaches the model, they allow it
    /// once, on a screen that names the provider, what is sent and what never is. tafs cloud
    /// keeps the answer and writes the words in their language. The app only draws the words
    /// and sends the answer. The same shape as the iPad app's.
    struct AIConsent: Decodable, Equatable, Identifiable {
        struct Words: Decodable, Equatable {
            let title: String
            let lines: [String]
            let allow: String
            let notNow: String
            let withdraw: String
            /// Account's row once it's given.
            let given: String
            enum CodingKeys: String, CodingKey { case title, lines, allow, notNow = "not_now", withdraw, given }
        }
        let given: Bool
        var at: String?
        /// The words' version: a yes is sent with the version it was given to, so an older
        /// screen can't say yes to newer words.
        let version: String
        let words: Words
        var id: String { version }
        /// Drawn only with everything it must say: a title, the lines, Allow and Not now.
        /// Anything less is no screen.
        var drawable: Bool {
            [words.title, words.allow, words.notNow].allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty } && !words.lines.isEmpty
        }
    }

    /// The consent in an answer that carries one (`{"consent": …}`).
    static func consent(in body: Data) -> AIConsent? {
        struct Answer: Decodable { let consent: AIConsent? }
        return (try? JSONDecoder().decode(Answer.self, from: body))?.consent
    }

    /// A refusal: tafs cloud's line for the person, its code, and the consent's words when
    /// the refusal brings that screen up. Each is read on its own, so one that doesn't read
    /// leaves the others.
    struct Refusal: Equatable {
        let status: Int
        var error: String?
        var code: String?
        var consent: AIConsent?

        init(status: Int, body: Data) {
            struct Body: Decodable { let error: String?; let code: String? }
            let read = try? JSONDecoder().decode(Body.self, from: body)
            self.status = status
            error = read?.error
            code = read?.code
            consent = TafsCloud.consent(in: body)
        }
    }
}

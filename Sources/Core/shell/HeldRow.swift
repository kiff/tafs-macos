import Foundation

/// A held call as the sidebar lists it under NEEDS YOU, to the iPad's row: "Taf: what it
/// asks", then KIFF's reason and the time to answer by.
struct HeldRow: Equatable, Identifiable {
    let id: String
    /// The taf's name and the call, or the call alone when the taf isn't in the list.
    let title: String
    /// KIFF's words for why it is held.
    let reason: String?
    let answerBy: Date?

    init(_ call: HeldCall, tafs: [Home.Taf]) {
        id = call.id
        let asks = call.title ?? call.action
        if let taf = tafs.first(where: { $0.kiffAgent == call.subject }) {
            title = taf.name + ": " + asks
        } else {
            title = asks
        }
        reason = call.reasonText
        answerBy = call.expiresAt
    }

    /// The second line: "{why} · answer by {time}" in the shared words, the reason alone with
    /// no time, the time alone with no reason, and nothing with neither.
    func line(_ words: Words, time: (Date) -> String) -> String? {
        switch (reason, answerBy) {
        case let (why?, by?): return words("home.reason_answer_by", ["why": why, "time": time(by)])
        case let (why?, nil): return why
        case let (nil, by?): return words("needs_you.answer_by", ["time": time(by)])
        case (nil, nil): return nil
        }
    }
}

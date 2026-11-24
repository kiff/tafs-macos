import Foundation

/// A held call as the sidebar lists it under NEEDS YOU, to the iPad's row: "Taf: what it
/// asks", then KIFF's reason and the time to answer by.
struct HeldRow: Equatable, Identifiable {
    let id: String
    /// The taf's name and the call, or the call alone when the taf isn't in the list.
    let title: String
    /// The taf's name, when the list has it, and what the call asks, apart: the Overview
    /// writes them "Taf · what it asks".
    let taf: String?
    /// The taf's KIFF agent, when the list has it: the row opens its page, as the iPad's `HomeSelection.held`.
    let agent: String?
    let asks: String
    /// KIFF's words for why it is held.
    let reason: String?
    let answerBy: Date?

    init(_ call: HeldCall, tafs: [Home.Taf]) {
        id = call.id
        // The call as the iPad names it (`proposed.summary`, HomeSplitView.swift:510).
        let asks = call.summary
        let listed = tafs.first(where: { $0.kiffAgent == call.subject })
        let name = listed?.name
        self.asks = asks
        taf = name
        agent = listed?.kiffAgent
        title = name.map { $0 + ": " + asks } ?? asks
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

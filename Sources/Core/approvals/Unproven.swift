import Foundation

/// A money call whose outcome KIFF can't prove, as the iPad's `KIFFClient.Unproven`: its
/// answer was lost, or the vendor refused it with nothing proving no effect. The owner says
/// whether it happened, signed like an approval.
struct Unproven: Decodable, Equatable, Identifiable {
    let proposal: String
    let agent: String?
    let tool: String?
    let title: String
    /// `unknown`, `refused_by_tool`, or `probation` (the first outcomes of an untried money operation).
    let status: String
    /// In minor units of `unit`, at `scale`.
    let amount: Int64?
    let unit: String?
    let scale: Int?
    let at: String?
    /// KIFF's sentence for the call ("Refund a payment: 40.00 EUR."), shown as it is.
    let words: String?
    /// Why KIFF asks, in its words: the answer was lost, the tool refused it, or probation.
    let statusWords: String?

    var id: String { proposal }
    /// Its amount, as the iPad's `money`: two places when KIFF doesn't say.
    var money: TafCard.Amount? { amount.map { TafCard.Amount(minor: $0, unit: unit, scale: scale ?? 2) } }

    enum CodingKeys: String, CodingKey { case proposal, agent, tool, title, status, amount, unit, scale, at, words, statusWords = "status_words" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proposal = try c.decode(String.self, forKey: .proposal)
        agent = try c.decodeIfPresent(String.self, forKey: .agent)
        tool = try c.decodeIfPresent(String.self, forKey: .tool)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        amount = try c.decodeIfPresent(Int64.self, forKey: .amount)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        scale = try c.decodeIfPresent(Int.self, forKey: .scale)
        at = try c.decodeIfPresent(String.self, forKey: .at)
        words = try c.decodeIfPresent(String.self, forKey: .words)
        statusWords = try c.decodeIfPresent(String.self, forKey: .statusWords)
    }
}

extension Me {
    /// Whether this person answers the account's held calls (KIFF's `holds.answer`), as the
    /// iPad's `mayAnswerHolds`. A KIFF that doesn't say leaves it to KIFF.
    var answersHolds: Bool { capabilities.map { $0.contains("holds.answer") } ?? true }
}

extension AccountClient {
    /// "Did this happen?": the money calls waiting for the owner to say, newest first.
    func didThisHappen() async throws -> [Unproven] {
        struct Answer: Decodable { let calls: [Unproven]? }
        let answer: Answer = try read(try await send("GET", "/v1/me/did-this-happen"))
        return answer.calls ?? []
    }
}

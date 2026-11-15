import Foundation

/// Reporting an answer Coach or a taf wrote, as the iPad's (kiff/tafs#421): a person at KIFF
/// reads it, with the answer as it was written.
enum AnswerReport {
    /// What's wrong with it, as the iPad's `TafsCloud.ReportReason`.
    enum Reason: String, CaseIterable, Encodable, Identifiable {
        case offensive, harmful, wrong, other
        var id: String { rawValue }
        /// Its line's key: `report.reason.*`.
        var key: String { "report.reason.\(rawValue)" }
    }

    /// The longest note tafs cloud takes.
    static let noteLimit = 1000

    /// A report tafs cloud keeps; `new` is false when the person had reported this answer already.
    struct Kept: Decodable, Equatable {
        let id: String
        let at: String
        let new: Bool
    }

    /// Whether an answer can be reported, as the iPad's `canReport`: a taf's (or Coach's)
    /// message, never the person's, with words, that tafs cloud has an id for.
    static func can(_ message: Thread.Message) -> Bool {
        message.from == "taf" && message.kind == "message" && !message.text.isEmpty && message.id != nil
    }
}

extension CloudClient {
    /// Reports one of the taf's answers (or Coach's, by Coach's taf id) by its id, with the chat
    /// it's in, as the iPad's `reportAnswer`.
    func report(_ message: String, of taf: String, reason: AnswerReport.Reason, note: String?, session: String?) async throws -> AnswerReport.Kept {
        struct Body: Encodable { let reason: AnswerReport.Reason; let note: String?; let session: String? }
        struct Answer: Decodable { let report: AnswerReport.Kept }
        let body = try await post("/v1/tafs/\(Self.escaped(taf))/messages/\(Self.escaped(message))/report", body: Body(reason: reason, note: note, session: session))
        guard let answer = try? JSONDecoder().decode(Answer.self, from: body) else { throw KIFFError.unreadable }
        return answer.report
    }
}

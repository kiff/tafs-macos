import Foundation

/// A taf's runs and one run's report, for the Overview's Last result, as tafs cloud sends them
/// (`GET /v1/tafs/{id}/runs`, then `GET /v1/tafs/{id}/runs/{session}`).
enum Runs {
    struct Run: Decodable, Equatable {
        /// The chat the run was in; a run with none has no report.
        let session: String?
        let at: Date?
        /// tafs cloud's words for why it stopped; a report never carries them.
        let error: String?

        enum CodingKeys: String, CodingKey { case session, at, error }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func text(_ key: CodingKeys) -> String? {
                guard let value = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil,
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return value
            }
            session = text(.session)
            at = (try? c.decodeIfPresent(Date.self, forKey: .at)) ?? nil
            error = text(.error)
        }
    }

    struct Page: Decodable, Equatable {
        let runs: [Run]
    }

    /// A run's report: how it stands, and its last answer.
    struct Report: Decodable, Equatable {
        /// `idle` (it ended), `running`, or `terminated`.
        let status: String
        let text: String

        enum Keys: String, CodingKey { case report }
        enum ReportKeys: String, CodingKey { case status, text }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self).nestedContainer(keyedBy: ReportKeys.self, forKey: .report)
            status = ((try? c.decodeIfPresent(String.self, forKey: .status)) ?? nil) ?? ""
            text = ((try? c.decodeIfPresent(String.self, forKey: .text)) ?? nil) ?? ""
        }
    }

    /// The run whose report is the last result: the newest with a chat.
    static func latest(_ runs: [Run]) -> Run? { runs.first { $0.session != nil } }

    /// The Last result's line, by the iPad's rule: the report's first line, without its marks;
    /// else why the run stopped; else when it last ran; else "Nothing yet".
    static func line(latest run: Run?, newest: Run?, report: Report?, words: Words, time: (Date) -> String) -> String {
        if let report {
            let first = report.text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
            if let first {
                return first.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        if let error = (run ?? newest)?.error { return error }
        if let at = (run ?? newest)?.at { return words("people.last_ran", ["time": time(at)]) }
        return words("overview.nothing_yet")
    }
}

extension CloudClient {
    func runs(of taf: String) async throws -> [Runs.Run] {
        let page: Runs.Page = try await get("/v1/tafs/\(Self.query(taf))/runs")
        return page.runs
    }

    func report(of taf: String, session: String) async throws -> Runs.Report {
        try await get("/v1/tafs/\(Self.query(taf))/runs/\(Self.query(session))")
    }
}

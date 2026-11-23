import Foundation

/// A run's request as tafs cloud tells it (`GET /v1/tafs/{id}/requests/{run}`), as the iPad's `TafsCloud.RequestDetail`
/// (`KIFF/TafsCloud+Work.swift:245-260`): who it came from, its line, what the taf did step by step, and where the result
/// went. Every word and time is tafs cloud's: the app formats none. Read as strictly as the iPad: a step or a request that
/// doesn't read is no page, and the sheet says why.
struct RequestDetail: Decodable, Equatable {
    struct Step: Decodable, Equatable {
        var label: String
        var line: String?
        var at: String?
        /// `done`, `next`, or anything else (drawn as not done).
        var state: String
    }

    var id: String
    var from: String
    var line: String
    var steps: [Step]
    var deliveries: [TafRuns.Delivery]
}

extension CloudClient {
    /// A run's request, step by step (docs/reliability.md, "The taf's view"). It reads; nothing is signed.
    func request(of taf: String, run: String) async throws -> RequestDetail {
        try await get("/v1/tafs/\(Self.escaped(taf))/requests/\(Self.escaped(run))", saying: true)
    }
}

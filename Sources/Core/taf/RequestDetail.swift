import Foundation

/// One run's request, as tafs cloud tells it (`GET /v1/tafs/{id}/requests/{run}`), as the iPad's
/// `TafsCloud.RequestDetail`: where it came from, its line, what it did step by step, and where its
/// reply went. Every line is tafs cloud's words, drawn as they are.
struct RequestDetail: Decodable, Equatable {
    /// One step: its label, tafs cloud's line for it, and its state (`done`, `next`, or anything
    /// else, which the iPad draws as stopped).
    struct Step: Decodable, Equatable {
        var label: String
        var line: String?
        var at: String?
        var state: String
    }

    var id: String
    var from: String
    var line: String
    var steps: [Step]
    var deliveries: [TafRuns.Delivery]

    /// A step's mark, as the iPad's: a done step's tick, the next one's clock, and anything else
    /// stopped.
    enum Mark: Equatable { case done, next, stopped }

    static func mark(_ step: Step) -> Mark {
        switch step.state {
        case "done": return .done
        case "next": return .next
        default: return .stopped
        }
    }
}

extension CloudClient {
    /// A run's request, what it did step by step, as the iPad's `request(_:run:)`: read only.
    func request(of taf: String, run: String) async throws -> RequestDetail {
        try await get("/v1/tafs/\(Self.escaped(taf))/requests/\(Self.escaped(run))", saying: true)
    }
}

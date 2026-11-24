import Foundation

/// One run of a taf, opened from its line (`GET /v1/tafs/{id}/requests/{run}`), as the iPad's `TafsCloud.RequestDetail`
/// and `KnobRequestDetail` (`TafDialPanel.swift:171-238`): where it came from, its line, its steps and where its result
/// went. Every word is tafs cloud's; the app draws them as sent.
struct TafRequest: Decodable, Equatable {
    /// One step of the run: done, next, or one that didn't go.
    struct Step: Decodable, Equatable {
        var label: String
        var line: String?
        var at: String?
        var state: String

        /// Done, its mark green; waiting next; anything else, a step that didn't go, its mark amber.
        enum Mark: Equatable { case done, next, failed }
        var mark: Mark {
            switch state {
            case "done": return .done
            case "next": return .next
            default: return .failed
            }
        }
    }

    var id: String
    /// Where the run came from, in tafs cloud's words: its heading.
    var from: String
    var line: String
    var steps: [Step]
    var deliveries: [TafRuns.Delivery]

    enum CodingKeys: String, CodingKey { case id, from, line, steps, deliveries }

    /// As the iPad's synthesized reader: each field is needed. A step or a delivery that doesn't read fails the run's read,
    /// never shows a run with a step missing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        from = try c.decode(String.self, forKey: .from)
        line = try c.decode(String.self, forKey: .line)
        steps = try c.decode([Step].self, forKey: .steps)
        deliveries = try c.decode([TafRuns.Delivery].self, forKey: .deliveries)
    }

    /// The deliveries that offer Send again, for whoever manages the taf, as the iPad's `delivery.sendAgain`.
    func sendsAgain(manages: Bool) -> [TafRuns.Delivery] {
        manages ? deliveries.filter(\.sendAgain) : []
    }

    /// The run's Ask Coach, as the iPad's `offersAskCoach`: for someone who may use Coach and manages the taf.
    static func offersAskCoach(mayUseCoach: Bool, manages: Bool) -> Bool { mayUseCoach && manages }
}

extension CloudClient {
    /// One run of a taf, read only. A refusal says tafs cloud's words (`CloudRefusal`).
    func request(of taf: String, run: String) async throws -> TafRequest {
        try await get("/v1/tafs/\(Self.escaped(taf))/requests/\(Self.escaped(run))", saying: true)
    }
}

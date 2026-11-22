import Foundation

/// A halt of one taf or, with none, of every taf (`/v1/tafs/{id}/halt`, `/v1/halt`), ported
/// from the iPad's `TafsCloud.Halt` and `HaltScreen`. Halting is one click, with no key: it only
/// takes authority away. It reads Halted only once kiff/agents, KIFF and planque all hold it,
/// Halting… until then. Resuming gives authority back, so it is signed: on the Mac it waits
/// for the approval key (#16).
struct Halt: Decodable, Equatable {
    enum State: String, Decodable { case running, halting, halted }

    let state: State
    let haltedAt: Date?
    /// Who holds it: kiff/agents (no run starts), KIFF's gateway (it refuses the calls),
    /// planque (it sends nothing to the vendor).
    let runtime: Bool
    let kiff: Bool
    let planque: Bool
    /// Halted because the whole account is, not on its own.
    let account: Bool

    enum CodingKeys: String, CodingKey { case state, runtime, kiff, planque, account, haltedAt = "halted_at" }

    init(state: State, haltedAt: Date? = nil, runtime: Bool = false, kiff: Bool = false, planque: Bool = false, account: Bool = false) {
        self.state = state; self.haltedAt = haltedAt; self.runtime = runtime; self.kiff = kiff; self.planque = planque; self.account = account
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decode(State.self, forKey: .state)
        haltedAt = (try? c.decodeIfPresent(Date.self, forKey: .haltedAt)) ?? nil
        func held(_ key: CodingKeys) -> Bool { ((try? c.decodeIfPresent(Bool.self, forKey: key)) ?? nil) ?? false }
        runtime = held(.runtime); kiff = held(.kiff); planque = held(.planque); account = held(.account)
    }

    static let running = Halt(state: .running)

    /// The screen's headline: Running, Halting…, or Halted.
    func headline(_ words: Words) -> String {
        switch state {
        case .running: return words("taf.now.running")
        case .halting: return words("taf.halt.halting")
        case .halted: return words("taf.state.halted")
        }
    }

    /// What halting does, or where it stands, as the iPad's `HaltScreen.explanation`.
    func explanation(all: Bool, _ words: Words, time: (Date) -> String) -> String {
        switch state {
        case .running:
            return words("halt.halting_stops_no_run_starts", ["who": all ? words("halt.your_tafs_lower") : words("record.on.it")])
        case .halting:
            return words("halt.explain.halting")
        case .halted:
            return haltedAt.map { words("halt.explain.halted_since", ["time": time($0)]) } ?? words("halt.explain.halted")
        }
    }
}

extension CloudClient {
    private static func haltPath(_ taf: String?) -> String { taf.map { "/v1/tafs/\(escaped($0))/halt" } ?? "/v1/halt" }

    /// Where a taf's halt, or the account's with none, stands.
    func halted(_ taf: String?) async throws -> Halt {
        struct Answer: Decodable { let halt: Halt }
        let answer: Answer = try await get(Self.haltPath(taf))
        return answer.halt
    }

    /// Lets kiff/agents run it again once KIFF has resumed it, as the iPad's `releaseHalt`: the taf's halt, or with
    /// none the account's. tafs cloud checks that KIFF resumed it first.
    func releaseHalt(_ taf: String?) async throws -> Halt {
        struct Answer: Decodable { let halt: Halt }
        return (try decoded(try await delete(Self.haltPath(taf))) as Answer).halt
    }

    /// Halts the taf, or with none every taf of the account, in kiff/agents and KIFF at once.
    func halt(_ taf: String?) async throws -> Halt {
        struct Answer: Decodable { let halt: Halt }
        let body = try await post(Self.haltPath(taf), [:])
        guard let answer = try? AccountClient.decoder.decode(Answer.self, from: body) else { throw KIFFError.unreadable }
        return answer.halt
    }
}

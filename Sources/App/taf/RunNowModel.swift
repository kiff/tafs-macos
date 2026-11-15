import Combine
import SwiftUI

/// Run now for every taf, kept by the app as the iPad's `runsInFlight` and `runNowWords`
/// (AppModel.swift:2112-2116, 2565-2581): by taf, so a page opened again still knows a run is
/// on its way, and still says what tafs cloud said.
@MainActor
final class RunNowModel: ObservableObject {
    /// The tafs whose Run now is on its way, so a second click starts nothing.
    @Published private(set) var inFlight: Set<String> = []
    /// A Run now that started no run, by taf: tafs cloud's words for it, until the next one.
    @Published private(set) var words: [String: String] = [:]
    /// Why a Run now didn't start, by taf: where the iPad says it in its error line.
    @Published private(set) var notStarted: [String: String] = [:]

    private let cloud: CloudClient

    init(cloud: CloudClient) { self.cloud = cloud }

    /// Runs a taf now, outside its schedule, as the iPad's `runNow`: the run's session; nil when
    /// it didn't start, or when a run for it is already on its way. Waiting for credits says
    /// tafs cloud's words; any other refusal says the run didn't start, and why.
    func runNow(_ taf: String, words say: Words) async -> String? {
        guard inFlight.insert(taf).inserted else { return nil }
        defer { inFlight.remove(taf) }
        words[taf] = nil
        notStarted[taf] = nil
        do {
            let run = try await cloud.runNow(taf)
            if let said = run.words { words[taf] = said }
            return run.session
        } catch let refusal as CloudRefusal where refusal.status == 409 && refusal.code.map(Self.creditsCodes.contains) == true {
            notStarted[taf] = refusal.why(say)
            return nil
        } catch {
            notStarted[taf] = say("taf.run_not_started", ["why": NeedsYouModel.why(error)])
            return nil
        }
    }

    /// tafs cloud's codes for a refusal because the tafs wait for credits, as the iPad's.
    static let creditsCodes: Set<String> = ["credits_used_up", "limit_reached", "no_plan"]
}

import Foundation

/// "Your brief", in Needs you's place once there is one, as the iPad's `AppModel` brief
/// (AppModel.swift, kiff/tafs#1173: `brief`, `loadBrief`, `filterBrief`, `laterBrief`,
/// `answerBrief`, `startNextMove`). Nothing is signed from here: a decision opens Needs you,
/// where its own answer is given.
@MainActor
final class BriefModel: ObservableObject {
    /// tafs cloud's brief; nil is Needs you, as today.
    @Published private(set) var brief: Brief?
    /// The label the brief is filtered to; nil is All.
    @Published private(set) var label: String?
    /// Decisions put off here, until the next read drops them.
    @Published private(set) var setAside: Set<String> = []
    /// The next move dismissed here.
    @Published private(set) var nextMoveDismissed = false
    /// A Later tafs cloud didn't take: its words, under the cards.
    @Published private(set) var laterRefused: String?
    private let cloud: CloudClient
    /// Set when the session ends: a read or a Later still on its way then keeps nothing.
    private var ended = false

    init(cloud: CloudClient) { self.cloud = cloud }

    /// The tab's name: tafs cloud's ("Your brief") once there's a brief, else Needs you.
    func tabTitle(_ words: Words) -> String {
        guard let tab = brief?.words.tab, !tab.isEmpty else { return words("needs_you.title") }
        return tab
    }

    /// The brief's decisions still to answer here.
    var decisions: [Brief.Decision] { (brief?.decisions ?? []).filter { !setAside.contains($0.id) } }

    /// Reads the brief for the label chosen. The switch is the route itself: until tafs cloud
    /// serves `GET /v1/brief`, it answers 404 and there's no brief, so Needs you is as today. Any
    /// other failure, or a brief with nothing in it, keeps Needs you too: the brief never hides
    /// what waits.
    func load() async {
        let read = try? await cloud.brief(label: label)
        guard !ended, !Task.isCancelled else { return }
        brief = read.flatMap { $0.shown ? $0 : nil }
    }

    func filter(_ label: String?) async {
        self.label = label
        setAside = []
        await load()
    }

    /// "Later": the decision moves to the next brief, set aside only once tafs cloud has moved it;
    /// else it stays, with tafs cloud's words for why. Never for an urgent one, whatever was sent.
    func later(_ decision: Brief.Decision) async {
        guard decision.offersLater != nil else { return }
        laterRefused = nil
        do {
            try await cloud.briefLater(decision.id)
            guard !ended else { return }
            setAside.insert(decision.id)
        } catch let refusal as CloudRefusal {
            guard !ended else { return }
            laterRefused = refusal.words
        } catch {}
    }

    func dismissNextMove() { nextMoveDismissed = true }

    /// What Needs you holds that the brief doesn't show, as the iPad's `briefNeedsYouLine`: held
    /// calls and steps matched by item, never by number, and what the brief can't carry counted.
    func needsYouBeyond(heldIDs: [String], stepIDs: [String], others: Int) -> Int {
        Brief.needsYouBeyond(items: heldIDs.map { "hold:" + $0 } + stepIDs.map { "step:" + $0 }, others: others, shown: decisions)
    }

    /// The mission's log, newest first; nil when it can't be read.
    func missionLog(_ mission: String) async -> MissionLog? { try? await cloud.missionLog(mission) }

    /// The session ended: nothing more is kept or shown.
    func endSession() {
        ended = true
        brief = nil
    }
}

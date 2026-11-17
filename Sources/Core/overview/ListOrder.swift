import Foundation

/// The tafs' order, as the iPad's `listedTafs` (AppModel.swift:546-557, 615-641): a taf waiting on
/// the person first, then the one at work most recently, so the taf just worked with is at the top;
/// tafs with nothing yet keep tafs cloud's order, after the rest. The order is settled when the
/// list's tafs change, not on every read, so it doesn't move while the person looks at it; a taf
/// newly waiting on the person still goes to the top at once.
///
/// The iPad knows "most recently" from KIFF's record of each taf's calls and the latest message in
/// its chat. This Mac reads neither for every taf, so it goes by the list's own `last_run`.
struct ListOrder: Equatable {
    /// The order last settled, by KIFF agent.
    private(set) var order: [String] = []
    /// The tafs waiting on the person when the order was settled: already placed by it.
    private(set) var waitingWhenSettled: Set<String> = []
    /// The tafs the order was settled for.
    private var settledFor: Set<String> = []

    init() {}

    /// The tafs waiting on the person: a call held for an answer, as tafs cloud counts it.
    static func waiting(_ tafs: [Home.Taf]) -> Set<String> {
        Set(tafs.filter { $0.waiting > 0 || $0.state == "waiting" }.map(\.id))
    }

    /// Settles the order when the tafs listed changed, or when there is none yet, as the iPad's
    /// `show` (AppModel.swift:2318-2320).
    mutating func show(_ tafs: [Home.Taf]) {
        let ids = Set(tafs.map(\.id))
        guard ids != settledFor || order.isEmpty else { return }
        settle(tafs)
    }

    /// Settles the order now, as the iPad's `settleListOrder`.
    mutating func settle(_ tafs: [Home.Taf]) {
        order = Self.byRecent(tafs).map(\.id)
        waitingWhenSettled = Self.waiting(tafs)
        settledFor = Set(tafs.map(\.id))
    }

    /// The tafs as listed, as the iPad's `listedTafs`: in the settled order, those it doesn't
    /// know yet after, and those newly waiting on the person first.
    func listed(_ tafs: [Home.Taf]) -> [Home.Taf] {
        let settled = Self.inOrder(tafs, order, fallback: Self.byRecent(tafs))
        return Self.waitingFirst(settled, waiting: Self.waiting(tafs).subtracting(waitingWhenSettled))
    }

    /// The tafs newly waiting on the person first, each part in the order it had.
    static func waitingFirst(_ tafs: [Home.Taf], waiting: Set<String>) -> [Home.Taf] {
        tafs.filter { waiting.contains($0.id) } + tafs.filter { !waiting.contains($0.id) }
    }

    /// tafs in a settled order; a taf the order doesn't know yet comes after, as `fallback` has it.
    static func inOrder(_ tafs: [Home.Taf], _ order: [String], fallback: [Home.Taf]) -> [Home.Taf] {
        guard !order.isEmpty else { return fallback }
        var place: [String: Int] = [:]
        for (index, id) in order.enumerated() where place[id] == nil { place[id] = index }
        let known = tafs.filter { place[$0.id] != nil }.sorted { (place[$0.id] ?? 0) < (place[$1.id] ?? 0) }
        return known + fallback.filter { place[$0.id] == nil }
    }

    /// Waiting first, then the latest at work, then tafs cloud's order, as the iPad's `byRecent`.
    static func byRecent(_ tafs: [Home.Taf]) -> [Home.Taf] {
        let waiting = Self.waiting(tafs)
        return tafs.enumerated().sorted { a, b in
            let wa = waiting.contains(a.element.id), wb = waiting.contains(b.element.id)
            if wa != wb { return wa }
            let la = a.element.lastRun ?? .distantPast, lb = b.element.lastRun ?? .distantPast
            return la != lb ? la > lb : a.offset < b.offset
        }.map(\.element)
    }
}

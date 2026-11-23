import SwiftUI

/// The watch's conversations in Coach, one a day, as the iPad's `WatchDaysModel`: which days there are, and one day's
/// turns. Nothing is kept on this Mac: each is read when shown, and an answer for a day asked before the last is never
/// drawn.
@MainActor
final class WatchDaysModel: ObservableObject {
    enum DayState: Equatable {
        case reading
        case loaded([WatchDays.Turn])
        case failed(String)
    }

    /// The days, newest first; none when tafs cloud has none, doesn't serve them, or its switch is off.
    @Published private(set) var days: [WatchDays.Day] = []
    /// Today in the account's time zone, as tafs cloud says it; nil from one that doesn't, and then this Mac's day.
    @Published private(set) var today: String?
    @Published private(set) var day: DayState = .reading
    private let readDays: () async throws -> WatchDays.List
    private let readDay: (String) async throws -> [WatchDays.Turn]
    private var asked = 0

    init(readDays: @escaping () async throws -> WatchDays.List, readDay: @escaping (String) async throws -> [WatchDays.Turn]) {
        self.readDays = readDays
        self.readDay = readDay
    }

    convenience init(cloud: CloudClient) {
        self.init(readDays: { try await cloud.watchDays() }, readDay: { try await cloud.watchDay($0) })
    }

    /// The days. A read that fails shows none: the section is simply not there.
    func load() async {
        let read = (try? await readDays()) ?? WatchDays.List()
        days = read.days
        today = read.today
    }

    /// One day's turns, oldest first.
    func open(_ date: String) async {
        asked += 1
        let this = asked
        day = .reading
        do {
            let turns = try await readDay(date)
            guard this == asked else { return }
            day = .loaded(turns)
        } catch {
            guard this == asked else { return }
            day = .failed(Words.app("coach.conversation_not_loaded", ["why": NeedsYouModel.why(error)]))
        }
    }

    /// The day left the screen: nothing of it is kept.
    func close() {
        asked += 1
        day = .reading
    }
}

import Foundation

/// Which held calls get a notification: each one once, and none of those already waiting
/// when the window opened, since the person is looking at them.
struct Announced: Equatable {
    private(set) var seen: Set<String>?

    /// The calls to announce now, given KIFF's current list.
    mutating func new(in calls: [HeldCall]) -> [HeldCall] {
        let ids = Set(calls.map(\.id))
        guard let before = seen else {
            seen = ids
            return []
        }
        // A call that left the list and came back (held again) is announced again.
        seen = ids
        return calls.filter { !before.contains($0.id) }
    }
}

/// What a notification says: the app's line as its title, then KIFF's words for the call.
struct Announcement: Equatable {
    let id: String
    let title: String
    let body: String

    init(_ call: HeldCall, words: Words) {
        id = call.id
        title = words("alert.needs_you")
        let said = [call.title, call.reasonText].compactMap { $0 }.joined(separator: " · ")
        body = said.isEmpty ? words("push.open_needs_you") : said
    }
}

import Foundation

/// What the signed-in window reads again while it's open, and when (tafs `docs/scale.md`, item 4): a desktop has no push
/// for tafs cloud yet, so it asks, but each thing on its own schedule, with jitter, and not while it sits in the background.
/// Held calls (Needs you and their alerts) every minute; the lists (Home, the brief, access, the halt) every 5 minutes;
/// nothing once the app has been in the background 10 minutes, and everything once when it's back in front. Replaces one
/// 30-second round of all five. Once the relay carries tafs cloud's changes, it's the fallback.
struct WindowReads: Equatable {
    /// How often held calls are read, and the lists.
    static let heldEvery: TimeInterval = 60
    static let listsEvery: TimeInterval = 300
    /// In the background longer than this, nothing is read until the app is back in front.
    static let idle: TimeInterval = 600
    /// A fraction of each wait, added or taken away at random, so many Macs don't read in step.
    static let jitter = 0.2

    enum Plan: Equatable { case nothing, held, all }

    /// When the lists were last read; nil before the first read.
    private(set) var listsAt: Date?
    /// Since when the app has been in the background; nil while it's in front.
    private(set) var backgroundSince: Date?

    /// What to read on this wake: nothing after 10 minutes in the background, everything once the lists are due (or never
    /// read), else the held calls.
    mutating func plan(now: Date) -> Plan {
        if let since = backgroundSince, now.timeIntervalSince(since) > Self.idle { return .nothing }
        if let at = listsAt, now.timeIntervalSince(at) < Self.listsEvery { return .held }
        listsAt = now
        return .all
    }

    /// The app went to the background, or came back in front: back in front, everything is read once at once.
    mutating func background(_ inBackground: Bool, now: Date) -> Plan {
        if inBackground {
            if backgroundSince == nil { backgroundSince = now }
            return .nothing
        }
        backgroundSince = nil
        listsAt = now
        return .all
    }

    /// The wait before the next wake: a minute, ± the jitter, `random` in 0...1.
    static func wait(random: Double) -> TimeInterval { heldEvery * (1 + jitter * (random * 2 - 1)) }
}

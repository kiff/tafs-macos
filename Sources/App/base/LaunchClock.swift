import Foundation

/// How long the app takes to show itself, written to the system log (Console, or
/// `log stream --predicate 'process == "tafs"'`): the milliseconds from launch to each mark,
/// once each. It holds no account data: a mark's name and a number.
enum LaunchClock {
    static let started = Date()
    private static var marked: Set<String> = []

    /// Writes "tafs: <what> after N ms" the first time `what` happens.
    static func mark(_ what: String, now: Date = Date()) {
        guard !marked.contains(what) else { return }
        marked.insert(what)
        NSLog("tafs: %@ after %d ms", what, Int(now.timeIntervalSince(started) * 1000))
    }
}

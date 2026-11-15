import Foundation

/// The time a signed request carries, as the iPad's `SigningTime`: RFC 3339 with
/// milliseconds, never the same twice in this app. planque and KIFF each refuse a signed
/// request they have already seen, and the time is part of what's signed, so two reads in the
/// same millisecond would look like a replay.
enum SigningTime {
    private static let lock = NSLock()
    private static var last = Date.distantPast
    private static let format: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func next(now: Date = Date()) -> String {
        lock.lock()
        defer { lock.unlock() }
        let ms = (now.timeIntervalSince1970 * 1000).rounded(.down)
        let floor = (last.timeIntervalSince1970 * 1000).rounded(.down) + 1
        last = Date(timeIntervalSince1970: max(ms, floor) / 1000)
        return format.string(from: last)
    }
}

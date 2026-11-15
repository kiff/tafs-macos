import Foundation

/// The time zone a time is drawn in, as the iPad's `AccountTime` (Components.swift:196-222): the
/// KIFF account's, whatever zone this Mac is in. An identifier this Mac doesn't know is UTC,
/// KIFF's own default; no account is this Mac's zone. Times sent to a server stay ISO 8601.
struct AccountTime {
    let zone: TimeZone

    init(_ identifier: String?) {
        zone = identifier.map { TimeZone(identifier: $0) ?? TimeZone(identifier: "UTC")! } ?? .current
    }

    /// The zone's short name after a time (" CET") when the account's zone shows a different
    /// clock from this Mac's at that moment; nothing when the clocks agree.
    func label(at date: Date, here: TimeZone = .current) -> String {
        guard zone.secondsFromGMT(for: date) != here.secondsFromGMT(for: date) else { return "" }
        return " " + (name(at: date) ?? "")
    }

    /// The zone's short name at a moment. KIFF's default, the zone an unknown identifier falls
    /// back to, is the iPad's word for it, "UTC", whatever this Mac calls it: newer macOS names
    /// it "GMT". Any other zone is named as macOS names it ("CET", and "GMT" for London in winter).
    func name(at date: Date) -> String? {
        if AccountTime.utc.contains(zone.identifier) { return "UTC" }
        return zone.abbreviation(for: date)
    }

    /// The identifiers macOS gives KIFF's default zone, by version.
    private static let utc: Set<String> = ["UTC", "GMT", "Etc/UTC", "Etc/GMT"]

    /// The time of day, as 14:05, in the account's zone (the iPad's `shortTime`).
    func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = zone
        return f.string(from: date)
    }

    /// `shortTime`, with the zone's short name when it isn't this Mac's (`zonedShortTime`).
    func zonedShortTime(_ date: Date, here: TimeZone = .current) -> String {
        shortTime(date) + label(at: date, here: here)
    }

    /// A date in a style, in the account's zone, with its short name when it isn't this
    /// Mac's (`zonedShown(date:time:)`).
    func zonedShown(_ date: Date, date dateStyle: Date.FormatStyle.DateStyle, time timeStyle: Date.FormatStyle.TimeStyle,
                    here: TimeZone = .current) -> String {
        var style = Date.FormatStyle(date: dateStyle, time: timeStyle)
        style.timeZone = zone
        return date.formatted(style) + label(at: date, here: here)
    }
}

import Foundation

private let at = ISO8601DateFormatter().date(from: "2026-11-15T22:22:00Z")!

/// A styled format drawn on the clock asked for, in UTC.
private func drawn(_ id: String, date: DateFormatter.Style = .none, time: DateFormatter.Style, twentyFour: Bool) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: id)
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateStyle = date
    f.timeStyle = time
    f.dateFormat = Clock.swapTime(in: f.dateFormat ?? "", style: time, locale: f.locale, twentyFour: twentyFour)
    return f.string(from: at)
}

let shellClockTests: [Test] = [
    Test("a locale's own hour: US English is 12-hour, British English and French are 24-hour") {
        try expectEqual(Clock.twentyFour(Locale(identifier: "en_US")), false)
        try expectEqual(Clock.twentyFour(Locale(identifier: "en_GB")), true)
        try expectEqual(Clock.twentyFour(Locale(identifier: "fr_FR")), true)
    },
    Test("a short time follows the clock asked for, not the language's default, in the language's own pattern") {
        try expectEqual(drawn("en_US", time: .short, twentyFour: true), "22:22")
        try expect(drawn("en_US", time: .short, twentyFour: false).hasPrefix("10:22"), "12-hour US English")
        try expect(drawn("fr_FR", time: .short, twentyFour: false).hasPrefix("10:22"), "12-hour French")
        try expectEqual(drawn("fr_FR", time: .short, twentyFour: true), "22:22")
        // Finnish keeps its own separator on a 24-hour clock.
        try expectEqual(drawn("fi_FI", time: .short, twentyFour: true), "22.22")
    },
    Test("a time already on the clock asked for, and a format with no time, come back as they are") {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeStyle = .short
        try expectEqual(Clock.swapTime(in: f.dateFormat, style: .short, locale: f.locale, twentyFour: true), f.dateFormat)
        try expectEqual(Clock.swapTime(in: "d MMM y", style: .short, locale: Locale(identifier: "en_US"), twentyFour: true), "d MMM y")
        try expectEqual(Clock.swapTime(in: "d MMM y", style: .none, locale: Locale(identifier: "en_US"), twentyFour: true), "d MMM y")
    },
    Test("with a date, only the time part changes: the date and the words joining them stay as the style wrote them") {
        let both = drawn("en_US", date: .medium, time: .short, twentyFour: true)
        try expect(both.hasPrefix("Nov 15, 2026") && both.hasSuffix("22:22"), both)
        try expect(drawn("en_GB", date: .medium, time: .short, twentyFour: false).hasPrefix("15 Nov 2026"), "the British date stays")
    },
    Test("a medium time keeps its seconds on either clock") {
        try expectEqual(drawn("en_US", time: .medium, twentyFour: true), "22:22:00")
        try expect(drawn("en_GB", time: .medium, twentyFour: false).hasPrefix("10:22:00"), "12-hour with seconds")
    },
]

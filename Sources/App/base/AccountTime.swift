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
        return zone.abbreviation(for: date).map { " " + $0 } ?? ""
    }

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

    /// A calendar in the account's zone, for "today" and the day a time falls on (the iPad's
    /// `AccountTime.calendar`).
    var calendar: Calendar {
        var c = Calendar.current
        c.timeZone = zone
        return c
    }

    /// A day's title in the Record, as the iPad's `RecordView.dayTitle` (RecordView.swift:146-151):
    /// "Today · Nov 15", "Yesterday · Nov 14", else "Friday · Nov 13", in the account's zone and
    /// the app's language.
    func dayTitle(_ day: Date, words: Words, now: Date = Date()) -> String {
        // In the app's language, the words' own, never this Mac's: a Spanish Mac showing the app
        // in English reads "Today · Nov 15", as the iPad's formatter in its app language.
        let locale = Locale(identifier: words.language)
        var short = Date.FormatStyle(locale: locale).day().month(.abbreviated)
        short.timeZone = zone
        let date = day.formatted(short)
        let calendar = self.calendar
        if calendar.isDate(day, inSameDayAs: now) { return words("calendar.today_date", ["date": date]) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return words("calendar.yesterday_date", ["date": date])
        }
        var weekday = Date.FormatStyle(locale: locale).weekday(.wide)
        weekday.timeZone = zone
        return day.formatted(weekday) + " · " + date
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

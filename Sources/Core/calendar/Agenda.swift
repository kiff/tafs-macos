import Foundation

/// The tafs' scheduled work still to come (`GET /v1/calendar`). tafs cloud works out every
/// occurrence in the account's zone and gives each its day and time there, so the app
/// places it without converting a zone, and both apps draw the same.
enum Agenda {
    /// One occurrence: a schedule's firing, a follow-up the taf set itself, or a run's next try.
    struct Event: Decodable, Identifiable, Equatable {
        let taf: String
        let name: String
        let color: Int
        /// `schedule`, `follow_up` or `retry`.
        let kind: String
        /// The instant, as tafs cloud wrote it.
        let at: String
        /// Its date (YYYY-MM-DD), time of day and minutes since midnight, in the account's zone.
        let day: String
        let time: String
        let minute: Int
        /// What it is, in tafs cloud's words ("Every day at 09:00", "Try 2 of 3").
        let words: String
        /// How many firings it stands for, when a dense schedule's day is folded into one.
        let count: Int

        var id: String { "\(taf)|\(kind)|\(at)" }

        enum CodingKeys: String, CodingKey { case taf, name, color, kind, at, day, time, minute, words, count }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            taf = try c.decode(String.self, forKey: .taf)
            at = try c.decode(String.self, forKey: .at)
            day = try c.decode(String.self, forKey: .day)
            time = try c.decode(String.self, forKey: .time)
            minute = try c.decode(Int.self, forKey: .minute)
            name = (try? c.decode(String.self, forKey: .name)) ?? ""
            color = (try? c.decode(Int.self, forKey: .color)) ?? 0
            kind = (try? c.decode(String.self, forKey: .kind)) ?? "schedule"
            words = (try? c.decode(String.self, forKey: .words)) ?? ""
            count = max(1, (try? c.decode(Int.self, forKey: .count)) ?? 1)
        }
    }

    struct Page: Decodable, Equatable {
        let timeZone: String
        let events: [Event]
        /// tafs cloud's line for the range ("3 to come", "Halted: nothing runs until it's resumed").
        let words: String
        /// Some events were left out: more than one read answers.
        let more: Bool
        /// The account is halted: nothing runs, so nothing is to come.
        let halted: Bool

        enum CodingKeys: String, CodingKey { case timeZone = "time_zone", events, words, more, halted }
        private struct Lenient: Decodable {
            let event: Event?
            init(from decoder: Decoder) throws { event = try? Event(from: decoder) }
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // The list must be there; one event this app can't read is left out, never the read.
            events = try c.decode([Lenient].self, forKey: .events).compactMap(\.event)
            timeZone = (try? c.decode(String.self, forKey: .timeZone)) ?? "UTC"
            words = (try? c.decode(String.self, forKey: .words)) ?? ""
            more = (try? c.decode(Bool.self, forKey: .more)) ?? false
            halted = (try? c.decode(Bool.self, forKey: .halted)) ?? false
        }

        /// A day's events, by their time of day.
        func events(on day: String) -> [Event] {
            events.filter { $0.day == day }.sorted { ($0.minute, $0.name) < ($1.minute, $1.name) }
        }

        /// A day's events in one hour of its grid, stacked in that hour's cell as the iPad
        /// does, so two at the same time both stay readable.
        func events(on day: String, hour: Int) -> [Event] {
            events(on: day).filter { $0.minute / 60 == hour }
        }

        /// The colours of the tafs with work on a day, at most three, for the month card's dots.
        func marks(on day: String) -> [Int] {
            var seen: [String] = [], colors: [Int] = []
            for event in events(on: day) where !seen.contains(event.taf) {
                seen.append(event.taf)
                colors.append(event.color)
                if colors.count == 3 { break }
            }
            return colors
        }

        /// How many firings a day holds, a folded dense schedule counting each.
        func count(on day: String) -> Int {
            events.filter { $0.day == day }.reduce(0) { $0 + $1.count }
        }

        /// Whether tafs cloud's line goes under the top line: when it halted, or when it cut
        /// the read at its most (`more`), as on the iPad.
        var saysWhy: Bool { (halted || more) && !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// Dates as tafs cloud writes them, `YYYY-MM-DD`, with no zone: a day is a day.
enum Days {
    private static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    static func date(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, day.count == 10 else { return nil }
        let made = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        // A date that isn't one (2026-02-30) would roll over: it is refused.
        guard let made, string(made) == day else { return nil }
        return made
    }

    static func string(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func adding(_ days: Int, to day: String) -> String? {
        date(day).flatMap { calendar.date(byAdding: .day, value: days, to: $0) }.map(string)
    }

    /// The seven days of the week `day` is in, Monday first.
    static func week(of day: String) -> [String] {
        guard let date = date(day) else { return [] }
        let weekday = calendar.component(.weekday, from: date)
        let fromMonday = (weekday + 5) % 7
        return (0..<7).compactMap { adding($0 - fromMonday, to: day) }
    }

    /// The day's parts, and the shared keys' names for its weekday and month.
    static func parts(_ day: String) -> (year: Int, month: Int, day: Int, weekdayKey: String, monthKey: String)? {
        guard let date = date(day) else { return nil }
        let c = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        let weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
        guard let y = c.year, let m = c.month, let d = c.day, let w = c.weekday, (1...12).contains(m), (1...7).contains(w) else { return nil }
        return (y, m, d, weekdays[w - 1], months[m - 1])
    }

    /// The six weeks a month's card shows, Monday first: 42 days around the month `day` is in.
    static func monthGrid(of day: String) -> [String] {
        guard let p = parts(day) else { return [] }
        let first = String(format: "%04d-%02d-01", p.year, p.month)
        guard let start = week(of: first).first else { return [] }
        return (0..<42).compactMap { adding($0, to: start) }
    }

    /// The first day of the month before or after the one `day` is in.
    static func month(_ offset: Int, from day: String) -> String? {
        guard let p = parts(day) else { return nil }
        let index = p.year * 12 + (p.month - 1) + offset
        return String(format: "%04d-%02d-01", index / 12, index % 12 + 1)
    }

    /// A day as a medium date in a language ("Nov 15, 2026"), for the date pill: read in UTC,
    /// since a day has no zone.
    static func medium(_ day: String, language: String) -> String {
        guard let date = date(day) else { return day }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language)
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// The same day a month or more before or after, the last of its month when that month is
    /// shorter (31 January and one month is 28 February), as the iPad's month arrows go.
    static func adding(months: Int, to day: String) -> String? {
        guard let d = date(day), let next = calendar.date(byAdding: .month, value: months, to: d) else { return nil }
        return string(next)
    }

    /// What one read asks for: the six weeks of the month card around `day`, as on the iPad, so
    /// the card can mark each day with work whatever the view, and moving within them reads nothing.
    static func range(of day: String) -> (from: String, to: String)? {
        let grid = monthGrid(of: day)
        guard let from = grid.first, let to = grid.last else { return nil }
        return (from, to)
    }

    /// The days of the month `day` is in, the 1st to the last.
    static func month(of day: String) -> [String] {
        guard let p = parts(day) else { return [] }
        return monthGrid(of: day).filter { parts($0)?.month == p.month }
    }

    /// The hours a day's grid shows: 08:00 to 18:00, wider when an event falls outside.
    static func hours(covering minutes: [Int]) -> ClosedRange<Int> {
        let first = min(8, (minutes.min() ?? 480) / 60)
        let last = max(18, (minutes.max() ?? 1080) / 60)
        return max(0, first)...min(23, last)
    }

    /// Today's date in a zone tafs cloud named, else in the Mac's own.
    static func today(in zone: String, now: Date = Date()) -> String {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = TimeZone(identifier: zone) ?? .current
        let c = local.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

extension CloudClient {
    /// What is to come on those dates, inclusive.
    func calendar(from: String, to: String) async throws -> Agenda.Page {
        try await get("/v1/calendar?from=\(Self.query(from))&to=\(Self.query(to))")
    }
}

/// What a week chip keeps in a narrow column: always a few characters of its taf's name; the
/// dot gives way first, then the ×N. The iPad's chip (CalendarView.swift:393-403) cut the name to
/// "…" first in a narrow week; the name is what tells one taf from another.
enum WeekChip {
    /// The least of the name a chip keeps: a few characters and the ellipsis, at 12 points.
    static let nameRoom: Double = 34
    /// The chip's own padding: 6 each side inside its colour, 2 each side outside.
    static let padding: Double = 16
    /// The dot and the space after it.
    static let dot: Double = 12
    /// The space before the ×N.
    static let gap: Double = 5

    /// Whether the dot and the ×N fit beside the name's least, in a column `width` wide; `count`
    /// is the ×N's own width, nil when the event stands for one firing.
    static func fit(width: Double, count: Double?) -> (dot: Bool, count: Bool) {
        let room = width - padding
        let times = count.map { $0 + gap } ?? 0
        if room >= nameRoom + dot + times { return (true, count != nil) }
        if count != nil, room >= nameRoom + times { return (false, true) }
        return (false, false)
    }
}

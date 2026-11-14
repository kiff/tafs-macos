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

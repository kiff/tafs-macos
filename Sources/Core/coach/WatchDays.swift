import Foundation

/// W11, "From your watch", as the iPad's `TafsCloud+WatchDays` and `WatchDaysModel` (docs/watch-app.md, "W11"): in Coach's
/// Previous conversations, the days the person asked from their watch, newest first, each with how many requests
/// (`GET /v1/watch/days`), and one day's turns, oldest first (`GET /v1/watch/days/{date}`). Only the person's own, read
/// only: a reply goes on in a Coach chat, as any other. A tafs cloud whose switch is off answers 404, and the section
/// isn't drawn.
enum WatchDays {
    /// One day: `YYYY-MM-DD` in the account's time zone, and how many requests.
    struct Day: Decodable, Equatable, Identifiable, Hashable {
        var date: String
        var count: Int
        var id: String { date }
    }

    /// The days, and which is today in the account's time zone, so a Mac on another zone sees "Today" on the right day.
    struct List: Equatable {
        var days: [Day] = []
        var today: String?
    }

    /// One request said from the watch that day, and where it went.
    struct Turn: Decodable, Equatable, Identifiable, Hashable {
        struct Taf: Decodable, Equatable, Hashable {
            var id: String
            var name: String
        }
        var id: String
        /// What the person said, as the watch sent it.
        var said: String
        /// When, RFC 3339, as tafs cloud wrote it.
        var saidAt: String
        /// The taf that took it, once one did.
        var taf: Taf?
        /// `accepted`, `working`, `done`, `no_taf` or `failed`.
        var state: String
        /// What came of it, checked by tafs cloud; none while it's at work.
        var line: String?
        /// The state in tafs cloud's words.
        var words: String
        /// The request this one replies to, shown under it.
        var replyTo: String?
        /// `taf`: a message to a taf the person chose, not a request to Coach. Nil for Coach's.
        var kind: String?

        enum CodingKeys: String, CodingKey {
            case id, said, taf, state, line, words, kind
            case saidAt = "said_at", replyTo = "reply_to"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            said = try c.decode(String.self, forKey: .said)
            saidAt = (try? c.decode(String.self, forKey: .saidAt)) ?? ""
            taf = try? c.decode(Taf.self, forKey: .taf)
            state = (try? c.decode(String.self, forKey: .state)) ?? ""
            line = (try? c.decode(String.self, forKey: .line)).flatMap { $0.isEmpty ? nil : $0 }
            words = (try? c.decode(String.self, forKey: .words)) ?? ""
            replyTo = try? c.decode(String.self, forKey: .replyTo)
            kind = try? c.decode(String.self, forKey: .kind)
        }

        /// What came of it, as the watch shows it: tafs cloud's line when there is one, else its words for the state.
        var outcome: String { line ?? words }
    }

    /// The days from tafs cloud's answer, and its today; a day this app can't read is left out, never the list.
    static func days(decoding data: Data) -> List {
        struct Response: Decodable { let days: [Lenient<Day>]?; let today: String? }
        let read = try? JSONDecoder().decode(Response.self, from: data)
        return List(days: (read?.days ?? []).compactMap(\.value), today: read?.today)
    }

    /// The turns, oldest first as sent; one this app can't read is left out, and so is a message to a taf
    /// (`kind: "taf"`): it's in that taf's own chat, not Coach's.
    static func turns(decoding data: Data) -> [Turn] {
        struct Response: Decodable { let turns: [Lenient<Turn>]? }
        return ((try? JSONDecoder().decode(Response.self, from: data))?.turns ?? []).compactMap(\.value).filter { $0.kind != "taf" }
    }

    /// A day's title: Today for the account's today when tafs cloud gives it (else this Mac's), else its weekday, day and
    /// month in the person's language.
    static func title(_ date: String, today: String?, now: Date = Date(), zone: TimeZone = .current,
                      locale: Locale, words: Words) -> String {
        let parse = DateFormatter()
        parse.calendar = Calendar(identifier: .gregorian)
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.timeZone = zone
        parse.dateFormat = "yyyy-MM-dd"
        guard let day = parse.date(from: date) else { return date }
        if date == (today ?? parse.string(from: now)) { return words("calendar.today") }
        let shown = DateFormatter()
        shown.locale = locale
        shown.timeZone = zone
        shown.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return shown.string(from: day)
    }

    /// When a turn was said, as this Mac writes a short time, in `zone`; nil for one tafs cloud didn't give.
    static func time(_ at: String, zone: TimeZone = .current, locale: Locale) -> String? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = precise.date(from: at) ?? ISO8601DateFormatter().date(from: at) else { return nil }
        let shown = DateFormatter()
        shown.locale = locale
        shown.timeZone = zone
        shown.dateStyle = .none
        shown.timeStyle = .short
        return shown.string(from: date)
    }
}

/// One item read on its own: one that doesn't read is nil, never the whole list.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

extension CloudClient {
    /// The person's watch days, newest first. A switch that's off (404) is no days, never an error.
    func watchDays() async throws -> WatchDays.List {
        do {
            return WatchDays.days(decoding: try await read("/v1/watch/days"))
        } catch KIFFError.refused(status: 404, code: _) {
            return WatchDays.List()
        }
    }

    /// One day's turns, oldest first.
    func watchDay(_ date: String) async throws -> [WatchDays.Turn] {
        WatchDays.turns(decoding: try await read("/v1/watch/days/\(Self.escaped(date))"))
    }
}

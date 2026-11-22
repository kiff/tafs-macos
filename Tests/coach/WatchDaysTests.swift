import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

private let daysAnswer = #"{"days":[{"date":"2026-11-22","count":3},{"date":7},{"date":"2026-11-20","count":1}],"today":"2026-11-22"}"#
private let dayAnswer = #"""
{"turns":[
  {"id":"w1","said":"Refund order 4471","said_at":"2026-11-22T08:05:00Z","taf":{"id":"t9","name":"Refunds"},"state":"done","line":"Refunded €42","words":"Done"},
  {"id":"w2","said":"And the next one?","said_at":"2026-11-22T08:06:00.500Z","state":"working","line":"","words":"Working on it","reply_to":"w1"},
  {"id":"w3","said":"Hi Refunds","said_at":"2026-11-22T08:07:00Z","state":"done","words":"Sent","kind":"taf"},
  {"said":"no id"}
]}
"""#

let coachWatchDaysTests: [Test] = [
    Test("the watch's days read as the iPad's: a day that doesn't read is left out, and tafs cloud's today is kept") {
        let list = WatchDays.days(decoding: Data(daysAnswer.utf8))
        try expectEqual(list.days.map(\.date), ["2026-11-22", "2026-11-20"])
        try expectEqual(list.today, "2026-11-22")
        try expectEqual(WatchDays.days(decoding: Data("not json".utf8)), WatchDays.List())
    },
    Test("a day's turns, oldest first: a message to a taf is that taf's, not Coach's; an empty line is none, so the words show") {
        let turns = WatchDays.turns(decoding: Data(dayAnswer.utf8))
        try expectEqual(turns.map(\.id), ["w1", "w2"])
        try expectEqual(turns[0].outcome, "Refunded €42")
        try expectEqual(turns[0].taf?.name, "Refunds")
        try expectEqual(turns[1].outcome, "Working on it")
        try expectEqual(turns[1].replyTo, "w1")
    },
    Test("a day's title is Today for tafs cloud's today, else its weekday, day and month; a time is this Mac's short one") {
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        let utc = TimeZone(identifier: "UTC")!, en = Locale(identifier: "en_US")
        try expectEqual(WatchDays.title("2026-11-22", today: "2026-11-22", zone: utc, locale: en, words: words), "Today")
        try expectEqual(WatchDays.title("2026-11-20", today: "2026-11-22", zone: utc, locale: en, words: words), "Friday, November 20")
        // Without tafs cloud's today, this Mac's.
        let now = ISO8601DateFormatter().date(from: "2026-11-20T12:00:00Z")!
        try expectEqual(WatchDays.title("2026-11-20", today: nil, now: now, zone: utc, locale: en, words: words), "Today")
        try expectEqual(WatchDays.title("not a date", today: nil, zone: utc, locale: en, words: words), "not a date")
        // Newer macOS puts a narrow no-break space before AM (U+202F), macOS 12 a plain one: either is this Mac's own short time.
        try expectEqual(WatchDays.time("2026-11-22T08:06:00.500Z", zone: utc, locale: en)?.replacingOccurrences(of: "\u{202F}", with: " "), "8:06 AM")
        try expectEqual(WatchDays.time("", zone: utc, locale: en), nil)
    },
    Test("the days and a day are read from tafs cloud; its switch off (404) is no days, never an error", awaiting: {
        let transport = CannedTransport([(200, daysAnswer), (200, dayAnswer), (404, #"{"error":"watch_off"}"#)])
        let cloud = CloudClient(transport: transport, session: session)
        let list = try await cloud.watchDays()
        try expectEqual(list.days.count, 2)
        let turns = try await cloud.watchDay("2026-11-22")
        try expectEqual(turns.count, 2)
        try expectEqual(transport.sent.map(\.path), ["/v1/watch/days", "/v1/watch/days/2026-11-22"])
        let off = try await cloud.watchDays()
        try expectEqual(off, WatchDays.List())
    }),
]

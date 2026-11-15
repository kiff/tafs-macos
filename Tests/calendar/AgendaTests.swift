import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

let agendaPage = #"""
{"time_zone":"Europe/Paris","from":"2026-11-09","to":"2026-11-15","events":[
  {"taf":"taf_1","name":"Refunds","color":1,"kind":"schedule","at":"2026-11-16T08:00:00Z","day":"2026-11-16","time":"09:00","minute":540,"words":"Every day at 09:00","count":1},
  {"taf":"taf_2","name":"Invoices","color":4,"kind":"retry","at":"2026-11-16T07:30:00Z","day":"2026-11-16","time":"08:30","minute":510,"words":"Try 2 of 3"},
  {"taf":"taf_1","name":"Refunds","color":1,"kind":"schedule","at":"2026-11-18T08:00:00Z","day":"2026-11-18","time":"09:00","minute":540,"words":"Every 5 minutes, 09:00 to 18:00","count":108},
  {"taf":"taf_3","name":"No time"}
],"days":["2026-11-16","2026-11-18"],"more":false,"halted":false,"words":"3 to come"}
"""#

let calendarTests: [Test] = [
    Test("the calendar is read as tafs cloud sends it, and an event that doesn't read is left out", awaiting: {
        let transport = CannedTransport([(200, agendaPage)])
        let page = try await CloudClient(transport: transport, session: session).calendar(from: "2026-11-16", to: "2026-11-22")
        try expectEqual(transport.sent[0].path, "/v1/calendar?from=2026%2D11%2D16&to=2026%2D11%2D22")
        try expectEqual(page.events.count, 3)
        try expectEqual(page.words, "3 to come")
        try expectEqual(page.timeZone, "Europe/Paris")
        try expectEqual(page.events(on: "2026-11-16").map(\.name), ["Invoices", "Refunds"])
        try expectEqual(page.events(on: "2026-11-18").first?.count, 108)
        try expectEqual(page.events(on: "2026-11-17").count, 0)
    }),
    Test("an answer with no list of events is unreadable, never an empty week, and a halt is said", awaiting: {
        for body in ["{}", "<html>"] {
            do {
                _ = try await CloudClient(transport: CannedTransport([(200, body)]), session: session).calendar(from: "a", to: "b")
                throw Failure(description: "\(body) was read")
            } catch let error as KIFFError { try expectEqual(error, .unreadable) }
        }
        let halted = #"{"events":[],"halted":true,"words":"Halted: nothing runs until it's resumed"}"#
        let page = try await CloudClient(transport: CannedTransport([(200, halted)]), session: session).calendar(from: "a", to: "b")
        try expectEqual(page.halted, true)
        try expectEqual(page.words, "Halted: nothing runs until it's resumed")
    }),
    Test("a week is seven days from Monday, across a month's and a year's end") {
        try expectEqual(Days.week(of: "2026-11-14"), ["2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14", "2026-11-15"])
        try expectEqual(Days.week(of: "2026-11-09").first, "2026-11-09")
        try expectEqual(Days.week(of: "2026-11-15").first, "2026-11-09")
        try expectEqual(Days.week(of: "2026-12-31"), ["2026-12-28", "2026-12-29", "2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02", "2027-01-03"])
        try expectEqual(Days.adding(7, to: "2026-02-23"), "2026-03-02")
        try expectEqual(Days.adding(-7, to: "2024-03-04"), "2024-02-26")
    },
    Test("a month's card is six weeks from a Monday, and months step across a year") {
        let grid = Days.monthGrid(of: "2026-11-15")
        try expectEqual(grid.count, 42)
        try expectEqual(grid.first, "2026-10-26")
        try expectEqual(grid.last, "2026-12-06")
        try expectEqual(Days.monthGrid(of: "2027-02-10").first, "2027-02-01")
        try expectEqual(Days.month(1, from: "2026-12-31"), "2027-01-01")
        try expectEqual(Days.month(-1, from: "2026-01-15"), "2025-12-01")
        try expectEqual(Days.month(-12, from: "2026-11-15"), "2025-11-01")
        try expectEqual(Days.monthGrid(of: "nope"), [])
    },
    Test("the hour grid is 08:00 to 18:00, and widens for an event outside it") {
        try expectEqual(Days.hours(covering: []), 8...18)
        try expectEqual(Days.hours(covering: [540, 600]), 8...18)
        try expectEqual(Days.hours(covering: [390, 1380]), 6...23)
        try expectEqual(Days.hours(covering: [0, 1439]), 0...23)
    },
    Test("events in the same hour, even at the same minute, are all in that hour's cell") {
        let json = #"{"time_zone":"UTC","events":[{"taf":"a","name":"Refunds","color":1,"kind":"schedule","at":"x","day":"2026-11-16","time":"09:00","minute":540,"words":""},{"taf":"b","name":"Invoices","color":2,"kind":"schedule","at":"y","day":"2026-11-16","time":"09:00","minute":540,"words":""},{"taf":"c","name":"Bills","color":3,"kind":"schedule","at":"z","day":"2026-11-16","time":"09:20","minute":560,"words":""},{"taf":"d","name":"Later","color":3,"kind":"schedule","at":"w","day":"2026-11-16","time":"10:00","minute":600,"words":""}],"more":true,"halted":false,"words":"Some work was left out."}"#
        let page = try JSONDecoder().decode(Agenda.Page.self, from: Data(json.utf8))
        try expectEqual(page.events(on: "2026-11-16", hour: 9).map(\.name), ["Invoices", "Refunds", "Bills"])
        try expectEqual(page.events(on: "2026-11-16", hour: 10).map(\.name), ["Later"])
        try expectEqual(page.events(on: "2026-11-16", hour: 8), [])
        // tafs cloud cut the read: its line is shown; with neither a halt nor a cut, it isn't.
        try expect(page.saysWhy, "more")
        let calm = try JSONDecoder().decode(Agenda.Page.self, from: Data(json.replacingOccurrences(of: #""more":true"#, with: #""more":false"#).utf8))
        try expect(!calm.saysWhy, "no halt, no cut")
    },
    Test("a date that isn't one is refused, never rolled over") {
        for bad in ["2026-02-30", "2026-13-01", "20261114", "2026-1-4", "today", ""] {
            try expect(Days.date(bad) == nil, bad)
            try expectEqual(Days.week(of: bad), [])
        }
    },
    Test("a day's parts name the shared keys for its weekday and month") {
        let parts = Days.parts("2026-11-14")
        try expectEqual(parts?.weekdayKey, "sat")
        try expectEqual(parts?.monthKey, "november")
        try expectEqual(parts?.day, 14)
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        let months = (1...12).map { String(format: "2026-%02d-01", $0) }
        for day in Days.week(of: "2026-11-14") + months {
            guard let p = Days.parts(day) else { throw Failure(description: day) }
            try expect(words("calendar.weekday.\(p.weekdayKey)") != "calendar.weekday.\(p.weekdayKey)", p.weekdayKey)
            try expect(words("calendar.month_name.\(p.monthKey)") != "calendar.month_name.\(p.monthKey)", p.monthKey)
            // The month card's title.
            try expect(words("calendar.month_title.\(p.monthKey)") != "calendar.month_title.\(p.monthKey)", p.monthKey)
        }
    },
    Test("one read is the month card's six weeks; a month on keeps the day, or its month's last") {
        try expectEqual(Days.range(of: "2026-11-16")?.from, "2026-10-26")
        try expectEqual(Days.range(of: "2026-11-16")?.to, "2026-12-06")
        // Every week of the month is in its read, the last one too.
        try expect(Days.monthGrid(of: "2026-11-30").contains("2026-12-06"), "the week of 30 November")
        try expectEqual(Days.month(of: "2026-11-16").count, 30)
        try expectEqual(Days.month(of: "2026-11-16").first, "2026-11-01")
        try expectEqual(Days.adding(months: 1, to: "2026-11-16"), "2026-12-16")
        try expectEqual(Days.adding(months: 1, to: "2027-01-31"), "2027-02-28")
        try expectEqual(Days.adding(months: -1, to: "2026-01-15"), "2025-12-15")
        try expect(Days.range(of: "nope") == nil, "no range for no date")
    },
    Test("a day's dots are its tafs' colours, each taf once and three at most; its count adds folded firings", awaiting: {
        let page = try await CloudClient(transport: CannedTransport([(200, agendaPage)]), session: session).calendar(from: "a", to: "b")
        try expectEqual(page.marks(on: "2026-11-16"), [4, 1])
        try expectEqual(page.marks(on: "2026-11-18"), [1])
        try expectEqual(page.marks(on: "2026-11-17"), [])
        try expectEqual(page.count(on: "2026-11-16"), 2)
        try expectEqual(page.count(on: "2026-11-18"), 108)
        let busy = #"{"events":["# + (1...4).map { #"{"taf":"t\#($0)","color":\#($0),"at":"x\#($0)","day":"2026-11-20","time":"09:00","minute":540}"# }.joined(separator: ",") + "]}"
        let four = try await CloudClient(transport: CannedTransport([(200, busy)]), session: session).calendar(from: "a", to: "b")
        try expectEqual(four.marks(on: "2026-11-20").count, 3)
    }),
    Test("today is the date in the account's zone, not the Mac's") {
        let lateInParis = Date(timeIntervalSince1970: 1_794_697_200) // 2026-11-14T23:00:00Z
        try expectEqual(Days.today(in: "Europe/Paris", now: lateInParis), "2026-11-15")
        try expectEqual(Days.today(in: "America/New_York", now: lateInParis), "2026-11-14")
        try expectEqual(Days.today(in: "UTC", now: lateInParis), "2026-11-14")
    },
]

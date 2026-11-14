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
        for day in Days.week(of: "2026-11-14") + ["2026-01-01", "2026-06-30"] {
            guard let p = Days.parts(day) else { throw Failure(description: day) }
            try expect(words("calendar.weekday.\(p.weekdayKey)") != "calendar.weekday.\(p.weekdayKey)", p.weekdayKey)
            try expect(words("calendar.month_name.\(p.monthKey)") != "calendar.month_name.\(p.monthKey)", p.monthKey)
        }
    },
    Test("today is the date in the account's zone, not the Mac's") {
        let lateInParis = Date(timeIntervalSince1970: 1_794_697_200) // 2026-11-14T23:00:00Z
        try expectEqual(Days.today(in: "Europe/Paris", now: lateInParis), "2026-11-15")
        try expectEqual(Days.today(in: "America/New_York", now: lateInParis), "2026-11-14")
        try expectEqual(Days.today(in: "UTC", now: lateInParis), "2026-11-14")
    },
]

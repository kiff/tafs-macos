import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
/// Monday 16 November 2026, 10:00 in Paris.
private let monday = Date(timeIntervalSince1970: 1_794_819_600)

@MainActor
private func model(_ answers: [(Int, String)]) -> (CalendarModel, CannedTransport) {
    let transport = CannedTransport(answers)
    return (CalendarModel(cloud: CloudClient(transport: transport, session: session), now: { monday }), transport)
}

let calendarMacTests: [Test] = [
    Test("one read is the month card's six weeks; moving within them reads nothing more", awaiting: { @MainActor in
        let (model, transport) = model(Array(repeating: (200, agendaPage), count: 8))
        await model.load()
        try expectEqual(model.today, "2026-11-16")
        try expectEqual(model.days.count, 7)
        try expectEqual(model.days.first, "2026-11-16")
        try expectEqual(transport.sent.last?.path, "/v1/calendar?from=2026%2D10%2D26&to=2026%2D12%2D06")
        try expectEqual(model.showsToday, true)
        await model.move(1)
        try expectEqual(model.days.first, "2026-11-23")
        try expectEqual(transport.sent.count, 1)
        try expectEqual(model.showsToday, false)
        await model.move(2)
        try expectEqual(model.days.first, "2026-12-07")
        try expectEqual(transport.sent.last?.path, "/v1/calendar?from=2026%2D11%2D30&to=2027%2D01%2D10")
        await model.goToToday()
        try expectEqual(model.days.first, "2026-11-16")
        try expectEqual(model.showsToday, true)
        try expectEqual(transport.sent.count, 3)
    }),
    Test("Day shows one day and moves by one; a day picked in the month card is gone to", awaiting: { @MainActor in
        let (model, transport) = model(Array(repeating: (200, agendaPage), count: 8))
        await model.load()
        model.show(.day)
        try expectEqual(model.days, ["2026-11-16"])
        await model.move(1)
        try expectEqual(model.days, ["2026-11-17"])
        try expectEqual(transport.sent.count, 1)
        await model.go(to: "2026-12-03")
        try expectEqual(model.days, ["2026-12-03"])
        let sent = transport.sent.count
        await model.go(to: "2026-02-30")
        try expectEqual(transport.sent.count, sent)
        try expectEqual(model.days, ["2026-12-03"])
    }),
    Test("Month shows the month's days and moves by a month; the card's arrows move the day as on the iPad", awaiting: { @MainActor in
        let (model, transport) = model(Array(repeating: (200, agendaPage), count: 8))
        await model.load()
        model.show(.month)
        try expectEqual(model.days.count, 30)
        try expectEqual(model.days.first, "2026-11-01")
        try expectEqual(transport.sent.count, 1)
        await model.move(1)
        try expectEqual(model.day, "2026-12-16")
        try expectEqual(model.days.count, 31)
        await model.turnMonth(1)
        try expectEqual(model.day, "2027-01-16")
        try expectEqual(transport.sent.last?.path, "/v1/calendar?from=2026%2D12%2D28&to=2027%2D02%2D07")
        model.show(.week)
        try expectEqual(model.days.first, "2027-01-11")
    }),
    Test("a calendar that can't be read says so, never an empty week", awaiting: { @MainActor in
        let (model, _) = model([(400, #"{"error":"bad_range"}"#)])
        await model.load()
        try expectEqual(model.state, .unread(why: "bad_range"))
    }),
    Test("the screenshots: a week of the Calendar in three languages, and its Month", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr", "pt"] {
            let (model, _) = model([(200, agendaPage)])
            await model.load()
            let view = CalendarView(model: model).environment(\.words, Words.load(folder: strings, preferred: [language]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 900)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("calendar-\(language).png"))
        }
        let (month, _) = model([(200, agendaPage)])
        await month.load()
        month.show(.month)
        let view = CalendarView(model: month).environment(\.words, Words.load(folder: strings, preferred: ["en"]))
        guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 900)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
        try png.write(to: folder.appendingPathComponent("calendar-month-en.png"))
    }),
]

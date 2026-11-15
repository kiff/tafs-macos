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
    Test("the week asked for is the seven days shown, and moving asks for the next seven", awaiting: { @MainActor in
        let (model, transport) = model(Array(repeating: (200, agendaPage), count: 8))
        await model.load()
        try expectEqual(model.today, "2026-11-16")
        try expectEqual(model.days.count, 7)
        try expectEqual(model.days.first, "2026-11-16")
        try expectEqual(transport.sent.last?.path, "/v1/calendar?from=2026%2D11%2D16&to=2026%2D11%2D22")
        try expectEqual(model.showsToday, true)
        await model.move(1)
        try expectEqual(transport.sent.last?.path, "/v1/calendar?from=2026%2D11%2D23&to=2026%2D11%2D29")
        try expectEqual(model.showsToday, false)
        await model.goToToday()
        try expectEqual(model.days.first, "2026-11-16")
        try expectEqual(model.showsToday, true)
    }),
    Test("Day shows one day and moves by one; a day picked in the month card is gone to", awaiting: { @MainActor in
        let (model, transport) = model(Array(repeating: (200, agendaPage), count: 8))
        await model.load()
        await model.show(.day)
        try expectEqual(model.days, ["2026-11-16"])
        try expectEqual(transport.sent.last?.path, "/v1/calendar?from=2026%2D11%2D16&to=2026%2D11%2D16")
        await model.move(1)
        try expectEqual(model.days, ["2026-11-17"])
        await model.go(to: "2026-12-03")
        try expectEqual(model.days, ["2026-12-03"])
        try expectEqual(model.monthShown, "2026-12-03")
        let sent = transport.sent.count
        await model.go(to: "2026-02-30")
        try expectEqual(transport.sent.count, sent)
        try expectEqual(model.days, ["2026-12-03"])
    }),
    Test("turning the month card's page reads nothing and keeps the days shown", awaiting: { @MainActor in
        let (model, transport) = model([(200, agendaPage)])
        await model.load()
        let sent = transport.sent.count
        model.turnMonth(1)
        model.turnMonth(1)
        try expectEqual(model.monthShown, "2027-01-01")
        try expectEqual(model.days.first, "2026-11-16")
        try expectEqual(transport.sent.count, sent)
    }),
    Test("a calendar that can't be read says so, never an empty week", awaiting: { @MainActor in
        let (model, _) = model([(400, #"{"error":"bad_range"}"#)])
        await model.load()
        try expectEqual(model.state, .unread(why: "bad_range"))
    }),
    Test("the screenshots: a week of the Calendar in three languages", awaiting: { @MainActor in
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
    }),
]

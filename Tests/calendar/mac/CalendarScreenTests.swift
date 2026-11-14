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
        let (model, transport) = model([(200, agendaPage), (200, agendaPage), (200, agendaPage)])
        await model.load()
        try expectEqual(model.today, "2026-11-16")
        try expectEqual(model.week.count, 7)
        try expectEqual(model.week.first, "2026-11-16")
        try expectEqual(transport.sent[0].path, "/v1/calendar?from=2026%2D11%2D16&to=2026%2D11%2D22")
        try expectEqual(model.showsToday, true)
        await model.move(weeks: 1)
        try expectEqual(transport.sent[1].path, "/v1/calendar?from=2026%2D11%2D23&to=2026%2D11%2D29")
        try expectEqual(model.showsToday, false)
        await model.goToToday()
        try expectEqual(model.week.first, "2026-11-16")
        try expectEqual(model.showsToday, true)
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

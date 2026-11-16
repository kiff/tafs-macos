import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

@MainActor
private func model(_ answers: [(Int, String)]) -> (BriefModel, CannedTransport) {
    let transport = CannedTransport(answers)
    return (BriefModel(cloud: CloudClient(transport: transport, session: session)), transport)
}

let briefMacTests: [Test] = [
    Test("until tafs cloud serves the brief (404), there's none and the tab says Needs you", awaiting: { @MainActor in
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        let (brief, _) = model([(404, #"{"error":"not_found"}"#)])
        await brief.load()
        try expectEqual(brief.brief, nil)
        try expectEqual(brief.tabTitle(words), words("needs_you.title"))
    }),
    Test("the route answers: the brief shows and the tab is tafs cloud's name for it; a failure or an empty brief keeps Needs you", awaiting: { @MainActor in
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        let (brief, _) = model([(200, briefAnswer), (503, ""), (200, #"{"decisions":[],"done":[],"words":{"title":"Your brief"}}"#)])
        await brief.load()
        try expectEqual(brief.brief?.decisions.count, 3)
        try expectEqual(brief.tabTitle(words), "Your brief")
        await brief.load()
        try expectEqual(brief.brief, nil)
        await brief.load()
        try expectEqual(brief.brief, nil)
    }),
    Test("Later posts its route once, and the card is set aside only after tafs cloud moved it", awaiting: { @MainActor in
        let (brief, transport) = model([(200, briefAnswer), (200, #"{"id":"hold:h_1","until":"2026-11-16T17:00:00Z"}"#)])
        await brief.load()
        let hold = brief.decisions[1]
        await brief.later(hold)
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["GET /v1/brief", "POST /v1/brief/decisions/hold:h_1/later"])
        try expectEqual(brief.decisions.map(\.id), ["connection:taf_2:stripe", "step:ho_9"])
    }),
    Test("a Later tafs cloud refuses keeps the card and says why; an urgent decision posts nothing", awaiting: { @MainActor in
        let (brief, transport) = model([(200, briefAnswer), (409, #"{"error":"cant_wait","code":"urgent","words":"This one can't wait."}"#)])
        await brief.load()
        await brief.later(brief.decisions[1])
        try expectEqual(brief.decisions.count, 3)
        try expectEqual(brief.laterRefused, "This one can't wait.")
        await brief.later(brief.decisions[0])
        try expectEqual(transport.sent.count, 2)
    }),
    Test("a label filters the brief and brings back what was set aside", awaiting: { @MainActor in
        let (brief, transport) = model([(200, briefAnswer), (200, #"{}"#), (200, briefAnswer)])
        await brief.load()
        await brief.later(brief.decisions[1])
        await brief.filter("lab_money")
        try expectEqual(transport.sent.last?.path, "/v1/brief?label=lab%5Fmoney")
        try expectEqual(brief.label, "lab_money")
        try expectEqual(brief.decisions.count, 3)
    }),
    Test("Needs you beyond the brief: held calls and steps matched by id, the rest counted", awaiting: { @MainActor in
        let (brief, _) = model([(200, briefAnswer)])
        await brief.load()
        try expectEqual(brief.needsYouBeyond(heldIDs: ["h_1", "h_2"], stepIDs: ["ho_9"], others: 1), 2)
    }),
    Test("a session that ends keeps nothing: the brief goes, and a read on its way is dropped", awaiting: { @MainActor in
        let (brief, _) = model([(200, briefAnswer), (200, briefAnswer)])
        await brief.load()
        brief.endSession()
        try expectEqual(brief.brief, nil)
        await brief.load()
        try expectEqual(brief.brief, nil)
    }),
    Test("the brief's screen only reads: nothing is sent or signed from it, and a held call opens Needs you with no answer chosen", awaiting: { @MainActor in
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        let (brief, transport) = model([(200, briefAnswer)])
        await brief.load()
        let view = BriefScreen(model: brief, needsYou: Text("Needs you"), beyond: 1).environment(\.words, words)
        _ = Snapshot.bitmap(of: view, size: CGSize(width: 1100, height: 900))
        try expectEqual(transport.sent.map(\.method), ["GET"])
        try expectEqual(Brief.destination(of: brief.decisions[1]), .hold("h_1"))
    }),
    Test("the screenshots: the brief in English and French, and a mission's log", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr"] {
            let (brief, _) = model([(200, briefAnswer)])
            await brief.load()
            let view = BriefScreen(model: brief, needsYou: Text("Needs you"), beyond: 1).environment(\.words, Words.load(folder: strings, preferred: [language]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 1100, height: 1000)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("brief-\(language).png"))
        }
        let log = try JSONDecoder().decode(MissionLog.self, from: Data(missionLogAnswer.utf8))
        let view = MissionLogView(title: "Late invoices", zone: "Europe/Paris", load: { log }, close: {})
            .environment(\.words, Words.load(folder: strings, preferred: ["en"]))
        guard let bitmap = Snapshot.settled(of: view, size: CGSize(width: 560, height: 620), tries: 8, until: { _ in false }), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
        try png.write(to: folder.appendingPathComponent("mission-log-en.png"))
    }),
]

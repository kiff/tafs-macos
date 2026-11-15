import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

@MainActor
private func model(_ answers: [(Int, String)]) -> OverviewModel {
    OverviewModel(cloud: CloudClient(transport: CannedTransport(answers), session: session))
}

let overviewMacTests: [Test] = [
    Test("the Overview loads tafs cloud's list, and says so when it can't", awaiting: { @MainActor in
        let loaded = model([(200, homePage)])
        await loaded.load()
        guard case .loaded(let page) = loaded.state else { throw Failure(description: "not loaded") }
        try expectEqual(page.tafs.count, 3)
        let unread = model([(503, "")])
        await unread.load()
        try expectEqual(unread.state, .unread(why: "503"))
    }),
    Test("nobody is told to pick a first taf unless the list was read and is empty", awaiting: { @MainActor in
        let recipes = #"{"home":{"shown":true,"words":"Pick a job for your first taf."}}"#
        // The list can't be read, but the recipes can: no claim that there are no tafs.
        let unread = model([(503, ""), (200, recipes)])
        await unread.load()
        try expectEqual(unread.hasNoTafs, false)
        try expectEqual(unread.noTafsLine, "Pick a job for your first taf.")
        let withTafs = model([(200, homePage), (200, recipes)])
        try expectEqual(withTafs.hasNoTafs, false)
        await withTafs.load()
        try expectEqual(withTafs.hasNoTafs, false)
        let none = model([(200, #"{"tafs":[]}"#), (200, recipes)])
        await none.load()
        try expectEqual(none.hasNoTafs, true)
    }),
    Test("the screenshots: the Overview with tafs, and with none, in three languages, and tafs cloud's own Home", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr", "pt"] {
            for (name, body) in [("tafs", homePage), ("empty", #"{"tafs":[]}"#)] {
                let model = model([(200, body)])
                await model.load()
                // A held call for Refunds, so NEEDS YOU shows a row, and tafs cloud counting one more.
                let calls = #"{"exceptions":[{"id":"e1","subject":"agent_refunds","action":"refund","title":"Refund order #4471","created_at":"2026-11-15T00:17:00Z","expires_at":"2026-11-15T00:27:00Z"}]}"#
                struct Held: Decodable { let exceptions: [HeldCall] }
                let held = ((try? AccountClient.decoder.decode(Held.self, from: Data(calls.utf8)))?.exceptions ?? []).map { HeldRow($0, tafs: model.tafs) }
                let view = OverviewView(model: model, held: name == "tafs" ? held : []).environment(\.words, Words.load(folder: strings, preferred: [language]))
                guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 800)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
                try png.write(to: folder.appendingPathComponent("overview-\(name)-\(language).png"))
            }
        }
        // tafs cloud's own Home (the home.json contract): a taf with its Card, so the Card column
        // shows its line, and its work line as tafs cloud words it.
        let contract = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: ".shared/contracts/home.json"))) as? [String: Any]
        guard let answer = contract?["answer"], let body = String(data: try JSONSerialization.data(withJSONObject: answer), encoding: .utf8) else { throw Failure(description: "no answer in home.json") }
        let model = model([(200, body)])
        await model.load()
        let view = OverviewView(model: model, held: []).environment(\.words, Words.load(folder: strings, preferred: ["en"]))
        guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 800)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
        try png.write(to: folder.appendingPathComponent("overview-contract-en.png"))
    }),
]

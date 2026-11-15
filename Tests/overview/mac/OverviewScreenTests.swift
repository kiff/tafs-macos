import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

@MainActor
private func model(_ answers: [(Int, String)]) -> OverviewModel {
    OverviewModel(cloud: CloudClient(transport: CannedTransport(answers), session: session))
}

private let listedRecipes = #"""
{"categories":[{"id":"money","title":"Money","color":{"light":"#1F7A4D","dark":"#4CC38A"}},{"id":"support","title":"Support"}],
 "recipes":[{"id":"r1","title":"Refunds","category":"money","headline":"Refunds wait days for someone to click","line":"Refunds orders within its limit","say":"Refund orders under €150","card":{"allows":["Refund up to €150"],"holds":["Refunds over €150"]},"apps":[{"name":"Stripe"}]},
            {"id":"r2","title":"Replies","category":"support","headline":"Tickets wait overnight","line":"Answers the easy ones","say":"Answer tickets"}],
 "home":{"shown":true,"words":"Pick a job for your first taf.","own_words":{"title":"Say it in your own words","line":"Coach builds the taf with you."}},
 "labels":{"allows":"Does on its own","holds":"Asks you first","never":"Never does","hand":"Hand it to Coach"}}
"""#

let overviewMacTests: [Test] = [
    Test("the list last read for this account shows in the first frame, and is read again and kept with the first read", awaiting: { @MainActor in
        let name = "tafs.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { throw Failure(description: "no defaults") }
        defer { defaults.removePersistentDomain(forName: name) }
        let first = OverviewModel(cloud: CloudClient(transport: CannedTransport([(200, homePage)]), session: session), remembered: defaults)
        try expectEqual(first.state, .loading)
        await first.load()
        guard case .loaded(let page) = first.state else { throw Failure(description: "not read") }
        // The next launch draws its tafs before any read: the tafs alone are kept.
        let next = OverviewModel(cloud: CloudClient(transport: CannedTransport([]), session: session), remembered: defaults)
        guard case .loaded(let shown) = next.state else { throw Failure(description: "nothing shown") }
        try expectEqual(shown.tafs, page.tafs)
        try expectEqual(shown.headline, nil)
        // Another account's list doesn't show.
        let other = Session(accessToken: "tok", expiresIn: 60, tenant: "t2", subject: "u9", deviceID: nil)
        try expectEqual(OverviewModel(cloud: CloudClient(transport: CannedTransport([]), session: other), remembered: defaults).state, .loading)
    }),
    Test("a list on screen stays when a read fails, as the iPad's; only an empty screen says why", awaiting: { @MainActor in
        let name = "tafs.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { throw Failure(description: "no defaults") }
        defer { defaults.removePersistentDomain(forName: name) }
        RememberedHome.remember(Data(homePage.utf8), tenant: session.tenant, in: defaults)
        let failing = #"{"error":{"code":"internal","message":"x"}}"#
        let next = OverviewModel(cloud: CloudClient(transport: CannedTransport([(500, failing)]), session: session), remembered: defaults)
        guard case .loaded(let shown) = next.state else { throw Failure(description: "nothing shown") }
        await next.load()
        try expectEqual(next.state, .loaded(shown))
        // Nothing on screen: the failed read says why.
        let empty = model([(500, failing)])
        await empty.load()
        guard case .unread = empty.state else { throw Failure(description: "not said") }
    }),
    Test("once the session ends, a read still on its way keeps nothing for the next launch", awaiting: { @MainActor in
        let name = "tafs.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { throw Failure(description: "no defaults") }
        defer { defaults.removePersistentDomain(forName: name) }
        let ending = OverviewModel(cloud: CloudClient(transport: CannedTransport([(200, homePage)]), session: session), remembered: defaults)
        ending.endSession()
        await ending.load()
        try expectEqual(RememberedHome.shown(tenant: session.tenant, in: defaults), nil)
    }),
    Test("the screenshot: the Overview's rows, each cell centred on the row", awaiting: { @MainActor in
        let loaded = model([(200, homePage)])
        await loaded.load()
        let view = OverviewView(model: loaded).environment(\.words, Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"]))
        guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 600)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: "build/screenshots"), withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: "build/screenshots/overview-rows-en.png"))
    }),
    Test("with no taf, tafs cloud's recipes are read with each list read, and a read that fails keeps them, as the iPad's", awaiting: { @MainActor in
        let transport = CannedTransport([(200, #"{"tafs":[]}"#), (200, listedRecipes), (200, #"{"tafs":[]}"#), (500, "")])
        let none = OverviewModel(cloud: CloudClient(transport: transport, session: session))
        await none.load()
        try expectEqual(none.recipes?.homeListsRecipes, true)
        try expectEqual(none.recipes?.byCategory.count, 2)
        try expectEqual(none.noTafsLine, "Pick a job for your first taf.")
        // The next read fails: what was read stays, on Home and in the sidebar.
        await none.load()
        try expectEqual(none.recipes?.homeListsRecipes, true)
        try expectEqual(none.noTafsLine, "Pick a job for your first taf.")
        try expectEqual(transport.sent.map(\.path), ["/v1/home", "/v1/recipes", "/v1/home", "/v1/recipes"])
        // With a taf, they aren't read at all.
        let busy = CannedTransport([(200, homePage)])
        let withTafs = OverviewModel(cloud: CloudClient(transport: busy, session: session))
        await withTafs.load()
        try expectEqual(withTafs.recipes, nil)
        try expectEqual(busy.sent.map(\.path), ["/v1/home"])
    }),
    Test("the screenshots: the Overview with no taf, listing tafs cloud's recipes", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let none = model([(200, #"{"tafs":[]}"#), (200, listedRecipes)])
        await none.load()
        let view = OverviewView(model: none, mayUseCoach: true).environment(\.words, Words.load(folder: strings, preferred: ["en"]))
        guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 800)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
        try png.write(to: folder.appendingPathComponent("overview-recipes-en.png"))
    }),
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
        // As the iPad's `refresh`: the recipes are read only once the list is read and empty.
        try expectEqual(unread.noTafsLine, nil)
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

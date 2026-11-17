import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let groups = #"{"groups":[{"id":"g1","name":"Support","members":[{"subject":"u1","role":"manager"},{"subject":"u2","role":"member"},{"subject":"u3","role":"member"}],"agents":["a_new"]}]}"#
private let members = #"{"members":[{"subject":"u4","role":"member","status":"active","email":"ana@acme.com"}]}"#

@MainActor
private func loaded(_ answers: [(Int, String)]) async -> (OverviewModel, CannedTransport) {
    let transport = CannedTransport(answers)
    let model = OverviewModel(cloud: CloudClient(transport: transport, session: session))
    await model.load()
    return (model, transport)
}

let overviewParityScreenTests: [Test] = [
    Test("the Overview and the sidebar list the tafs in the iPad's order: waiting first, then the latest at work", awaiting: { @MainActor in
        let (model, _) = await loaded([(200, orderedHome)])
        try expectEqual(model.listedTafs.map(\.name), ["Deploys", "Refunds", "Invoices", "Payroll"])
        // tafs cloud's own order stays the list's, for what looks a taf up.
        try expectEqual(model.tafs.map(\.name), ["Invoices", "Payroll", "Refunds", "Deploys"])
    }),
    Test("Last result says the list's last_run before its runs are read, \"Nothing yet\" with none, and \"–\" only for an agent tafs doesn't run", awaiting: { @MainActor in
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        let (model, _) = await loaded([(200, orderedHome)])
        let byName = Dictionary(uniqueKeysWithValues: model.tafs.map { ($0.name, $0) })
        guard let payroll = byName["Payroll"], let refunds = byName["Refunds"] else { throw Failure(description: "no tafs") }
        try expectEqual(model.lastResult(payroll, words: words, time: { _ in "08:00" }), "Nothing yet")
        try expectEqual(model.lastResult(refunds, words: words, time: { _ in "08:00" }), "Last ran at 08:00")
        let agent = try AccountClient.decoder.decode(Home.Taf.self, from: Data(#"{"kiff_agent":"a_x","name":"Old agent","state":"idle"}"#.utf8))
        try expectEqual(model.lastResult(agent, words: words, time: { _ in "08:00" }), "–")
    }),
    Test("runs that can't be read say so in Last result, as the iPad's loadReport, and are read once", awaiting: { @MainActor in
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        let one = #"{"tafs":[{"id":"taf-1","name":"Refunds","kiff_agent":"a1","state":"working"}]}"#
        let (model, transport) = await loaded([(200, one), (200, #"{"categories":[],"recipes":[]}"#), (500, "")])
        await model.loadLastResults(words: words)
        try expectEqual(model.lastResults["taf-1"], "Its runs couldn't be loaded. 500")
        await model.loadLastResults(words: words)
        try expectEqual(transport.sent.filter { $0.path.contains("/runs") }.map(\.path), ["/v1/tafs/taf-1/runs"])
    }),
    Test("who uses each taf is read only for the tafs this person manages, by KIFF agent", awaiting: { @MainActor in
        let (model, _) = await loaded([(200, orderedHome)])
        var asked: [String] = []
        await model.loadShares(agents: ["a_new", "a_wait"]) { agent in
            asked.append(agent)
            if agent == "a_wait" { throw KIFFError.unreadable }
            return [Shares.Share(group: "g1")]
        }
        try expectEqual(asked, ["a_new", "a_wait"])
        try expectEqual(model.shares["a_new"], [Shares.Share(group: "g1")])
        // One that can't be read shows no line.
        try expectEqual(model.shares["a_wait"], nil)
    }),
    Test("the screenshots: the Overview's rows with who uses each taf and its Last result, in the iPad's order, light and dark", awaiting: { @MainActor in
        let (model, _) = await loaded([(200, orderedHome)])
        await model.loadShares(agents: ["a_new", "a_old", "a_wait"]) { agent in
            switch agent {
            case "a_new": return [Shares.Share(group: "g1"), Shares.Share(subject: "u4")]
            case "a_old": return []
            default: return [Shares.Share(subject: "u4")]
            }
        }
        let people = PeopleModel(account: AccountClient(transport: CannedTransport([(200, groups), (200, members)]), session: session))
        await people.load()
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for dark in [false, true] {
            let view = OverviewView(model: model, needsCount: 3, needsWords: "3 need you.", people: people, manages: { $0.kiffAgent != "a_never" })
                .environment(\.words, Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 700), dark: dark), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("overview-parity-en\(dark ? "-dark" : "").png"))
        }
    }),
]

import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let second = #"{"entries":[\#(recordEntry("e3"))],"groups":[{"id":"today","title":"Today","entries":[\#(recordEntry("e3"))]}],"end_words":"That's everything."}"#

@MainActor
private func model(_ answers: [(Int, String)]) -> (RecordModel, CannedTransport) {
    let transport = CannedTransport(answers)
    return (RecordModel(cloud: CloudClient(transport: transport, session: session)), transport)
}

let recordMacTests: [Test] = [
    Test("the next page joins its group, and the end's words show only at the end", awaiting: { @MainActor in
        let (model, transport) = model([(200, recordPage), (200, second)])
        await model.load()
        try expectEqual(model.canContinue, true)
        try expectEqual(model.endWords, nil)
        await model.more()
        try expectEqual(transport.sent[1].path, "/v1/record?q=&cursor=c2")
        try expectEqual(model.groups.map(\.id), ["today"])
        try expectEqual(model.groups[0].entries.map(\.id), ["e1", "e2", "e3"])
        try expectEqual(model.canContinue, false)
        try expectEqual(model.endWords, "That's everything.")
    }),
    Test("a cursor tafs cloud no longer takes starts the search again, from its first page", awaiting: { @MainActor in
        let (model, transport) = model([(200, recordPage), (409, #"{"error":"search_again"}"#), (200, second)])
        await model.load()
        await model.more()
        try expectEqual(transport.sent.map(\.path), ["/v1/record?q=", "/v1/record?q=&cursor=c2", "/v1/record?q="])
        try expectEqual(model.groups[0].entries.map(\.id), ["e3"])
    }),
    Test("a Record that can't be read says so, and keeps tafs cloud's words when nothing matched", awaiting: { @MainActor in
        let (unread, _) = model([(500, "")])
        await unread.load()
        try expectEqual(unread.state, .unread(why: "500"))
        let (none, _) = model([(200, #"{"entries":[],"none_words":"Nothing matched."}"#)])
        none.search = "zzz"
        await none.load()
        try expectEqual(none.noneWords, "Nothing matched.")
    }),
    Test("a taf's chip keeps that taf's calls, and All tafs every taf's", awaiting: { @MainActor in
        let (model, _) = model([(200, recordPage)])
        await model.load()
        let all = model.shown.flatMap(\.entries).count
        model.taf = "taf_1"
        try expect(model.shown.flatMap(\.entries).allSatisfy { $0.taf.id == "taf_1" }, "only Refunds")
        model.taf = "nobody"
        try expectEqual(model.shown, [])
        model.taf = nil
        try expectEqual(model.shown.flatMap(\.entries).count, all)
    }),
    Test("the screenshots: the Record in three languages", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr", "pt"] {
            let (model, _) = model([(200, recordPage.replacingOccurrences(of: #","next_cursor":"c2""#, with: ""))])
            await model.load()
            // Two tafs, so the taf chips show; Refunds is the fixture's own taf, by its id at tafs cloud.
            let home = #"{"tafs":[{"id":"taf_1","name":"Refunds","kiff_agent":"a1","color":1,"state":"working"},{"id":"taf_2","name":"Invoices","kiff_agent":"a2","color":4,"state":"idle"}]}"#
            let tafs = (try? JSONDecoder().decode(Home.Page.self, from: Data(home.utf8)))?.tafs ?? []
            let view = RecordView(model: model, tafs: tafs).environment(\.words, Words.load(folder: strings, preferred: [language]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 800)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("record-\(language).png"))
        }
    }),
]

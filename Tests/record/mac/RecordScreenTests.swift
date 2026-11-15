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
        await none.find("zzz")
        try expectEqual(none.found?.pages.last?.noneWords, "Nothing matched.")
        try expectEqual(none.found?.pages.allSatisfy(\.isEmpty), true)
    }),
    Test("a search reads its next page only on More, and keeps each page as tafs cloud sent it", awaiting: { @MainActor in
        let (model, transport) = model([(200, recordPage), (200, second)])
        await model.find("refund")
        try expectEqual(transport.sent.count, 1)
        try expectEqual(model.found?.nextCursor, "c2")
        await model.find("refund", more: true)
        try expectEqual(transport.sent[1].path, "/v1/record?q=refund&cursor=c2")
        // "today" on both pages stays two groups, each as sent.
        try expectEqual(model.found?.pages.map { $0.shown.map(\.id) }, [["today"], ["today"]])
        try expectEqual(model.found?.pages[1].shown[0].entries.map(\.id), ["e3"])
        try expectEqual(model.found?.nextCursor, nil)
        try expectEqual(model.found?.pages.last?.endWords, "That's everything.")
        await model.find("refund", more: true)
        try expectEqual(transport.sent.count, 2)
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
    Test("what's typed is searched once the person pauses, once; Return searches at once", awaiting: { @MainActor in
        let (model, transport) = model([(200, recordPage), (200, recordPage), (200, recordPage)])
        model.typingPause = 50_000_000
        await model.load()
        try expectEqual(model.searched, "")
        model.search = "o"; model.typed()
        model.search = "or"; model.typed()
        model.search = "order 4471"; model.typed()
        try await Task.sleep(nanoseconds: 300_000_000)
        try expectEqual(transport.sent.map(\.path), ["/v1/record?q=", "/v1/record?q=order%204471"])
        try expectEqual(model.searched, "order 4471")
        // The same words again aren't searched again; Return searches at once.
        model.typed()
        try await Task.sleep(nanoseconds: 150_000_000)
        try expectEqual(transport.sent.count, 2)
        await model.submitted()
        try expectEqual(transport.sent.count, 3)
    }),
    Test("an emptied box shows the list already read at once, with nothing read", awaiting: { @MainActor in
        let (model, transport) = model([(200, recordPage), (200, recordPage)])
        await model.load()
        await model.find("order")
        try expect(model.found != nil, "a search shown")
        model.search = "  "
        model.typed()
        try expectEqual(model.found, nil)
        try expectEqual(transport.sent.count, 2)
    }),
    Test("a search shows what tafs cloud found, never narrowed by a taf or a filter chosen in the list", awaiting: { @MainActor in
        let (model, _) = model([(200, recordPage), (200, recordPage)])
        await model.load()
        model.taf = "nobody"
        model.filter = .stopped
        try expectEqual(model.shown, [])
        await model.find("refund")
        try expectEqual(model.found?.pages.flatMap(\.shown).flatMap(\.entries).map(\.id), ["e1", "e2"])
    }),
    Test("the same words typed while they're being searched aren't asked for twice", awaiting: { @MainActor in
        let transport = CannedTransport([(200, recordPage)])
        let model = RecordModel(cloud: CloudClient(transport: transport, session: session))
        model.typingPause = 10_000_000
        model.search = "refund"
        async let first: Void = model.submitted()
        // Until the search has started, however the tasks are scheduled; then its words are
        // the search's at once.
        for _ in 0..<10_000 where model.found == nil { await Task.yield() }
        try expectEqual(model.found?.q, "refund")
        model.typed()
        try await Task.sleep(nanoseconds: 100_000_000)
        await first
        try expectEqual(transport.sent.count, 1)
    }),
    Test("a search or a case that tafs cloud refuses says its words first, else its code", awaiting: { @MainActor in
        let (model, _) = model([(503, #"{"error":"busy","words":"The Record is busy. Try again in a moment."}"#), (404, #"{"error":"not_found"}"#)])
        await model.find("refund")
        try expectEqual(model.found?.error, "The Record is busy. Try again in a moment.")
        await model.open(case: "Order 9")
        try expectEqual(model.caseError, "not_found")
    }),
    Test("a case opens from a search with its calls and the step that failed, and closes", awaiting: { @MainActor in
        let found = #"{"about":"Order 4471","steps":[\#(recordEntry("e1"))],"failed":{"id":"e1","words":"The refund didn't go through"}}"#
        let (model, transport) = model([(200, found), (404, #"{"error":"not_found"}"#)])
        await model.open(case: "Order 4471")
        try expectEqual(transport.sent.last?.path, "/v1/record/cases/Order%204471")
        try expectEqual(model.caseAbout, "Order 4471")
        try expectEqual(model.openCase?.steps.map(\.id), ["e1"])
        try expectEqual(model.openCase?.failed?.words, "The refund didn't go through")
        await model.open(case: "Order 9")
        try expectEqual(model.openCase, nil)
        try expect(model.caseError != nil, "why it couldn't be read")
        model.closeCase()
        try expectEqual(model.caseAbout, nil)
        await model.open(case: "  ")
        try expectEqual(transport.sent.count, 2)
    }),
    Test("the screenshots: a search shown in the list's place", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let (model, _) = model([(200, recordPage), (200, recordPage)])
        await model.load()
        model.search = "refund"
        await model.find("refund")
        let view = RecordView(model: model).environment(\.words, Words.load(folder: strings, preferred: ["en"]))
        guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 760)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
        try png.write(to: folder.appendingPathComponent("record-search-en.png"))
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

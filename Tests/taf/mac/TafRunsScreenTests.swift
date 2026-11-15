import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

@MainActor
private func model(_ answers: [(Int, String, String?)]) -> (TafPagesModel, TaggedTransport) {
    let transport = TaggedTransport(answers)
    return (TafPagesModel(cloud: CloudClient(transport: transport, session: session), taf: "taf-1"), transport)
}

private func taf(_ fields: String) throws -> Home.Taf {
    let json = #"{"tafs":[{"id":"taf-1","name":"Refunds","kiff_agent":"a1","color":0,"#  + fields + "}]}"
    return try AccountClient.decoder.decode(Home.Page.self, from: Data(json.utf8)).tafs[0]
}

let tafRunsMacTests: [Test] = [
    Test("the panel reads three runs, all of them twenty a page; a 304 keeps what was read; a failed read says why", awaiting: { @MainActor in
        let (pages, transport) = model([(200, runsPageAnswer, "\"v1\""), (304, "", nil), (200, runsPageAnswer, nil), (503, #"{"error":"down"}"#, nil)])
        await pages.loadRunPage()
        try expectEqual(transport.sent[0].path, "/v1/tafs/taf-1/work/runs?limit=3")
        try expectEqual(pages.runPages[false]?.pages.count, 1)
        await pages.loadRunPage()
        try expectEqual(transport.sent[1].headers["If-None-Match"], "\"v1\"")
        try expectEqual(pages.runPages[false]?.pages.count, 1)
        await pages.loadRunPage(all: true)
        try expectEqual(transport.sent[2].path, "/v1/tafs/taf-1/work/runs?limit=20")
        await pages.loadRunPage(all: true, more: true)
        try expectEqual(transport.sent[3].path, "/v1/tafs/taf-1/work/runs?limit=20&cursor=c2")
        try expectEqual(pages.runPages[true]?.pages.count, 1)
        try expectEqual(pages.runPages[true]?.error, "down")
        try expectEqual(pages.runPages[true]?.loading, false)
    }),
    Test("Run now sends once; tafs cloud's words when it started no run; credits and other refusals say why", awaiting: { @MainActor in
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        let (pages, transport) = model([(200, #"{"session":null,"words":"It ran 2 minutes ago."}"#, nil),
                                        (409, #"{"error":"No credits left.","code":"credits_used_up"}"#, nil),
                                        (500, #"{"error":"internal"}"#, nil),
                                        (200, #"{"session":"s9"}"#, nil)])
        let none = await pages.runNow(words: words)
        try expectEqual(none, nil)
        try expectEqual(pages.runNowWords, "It ran 2 minutes ago.")
        _ = await pages.runNow(words: words)
        try expectEqual(pages.runNowWords, nil)
        try expectEqual(pages.runNotStarted, "No credits left.")
        _ = await pages.runNow(words: words)
        try expectEqual(pages.runNotStarted, "The run didn't start. internal")
        let started = await pages.runNow(words: words)
        try expectEqual(started, "s9")
        try expectEqual(pages.runNotStarted, nil)
        try expectEqual(pages.runInFlight, false)
        try expectEqual(transport.sent.filter { $0.method == "POST" }.count, 4)
    }),
    Test("the runs panel says paused, tafs cloud's next run, the app's time, or its schedule; or that it works from its chat") {
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        try expectEqual(RunsPanel.next(try taf(#""state":"paused","next_run_words":"Next run Mon 09:00""#), words: words), "Paused")
        try expectEqual(RunsPanel.next(try taf(#""state":"idle","next_run_words":"Next run Mon 09:00""#), words: words), "Next run Mon 09:00")
        try expectEqual(RunsPanel.next(try taf(#""state":"idle","next_run":"2026-11-15T14:05:00Z""#), words: words).hasPrefix("Next run at "), true)
        try expectEqual(RunsPanel.shortTime(ISO8601DateFormatter().date(from: "2026-11-15T14:05:00Z")!, zone: TimeZone(identifier: "UTC")!), "14:05")
        try expectEqual(RunsPanel.next(try taf(#""state":"idle""#), words: words), "On its schedule")
        try expectEqual(try taf(#""state":"idle","unscheduled":true"#).unscheduled, true)
    },
    Test("the screenshot: a taf's runs and the runs it kept", awaiting: { @MainActor in
        let (pages, _) = model([(200, runsPageAnswer, nil)])
        await pages.loadRunPage()
        let view = VStack(spacing: 14) {
            RunsPanel(model: pages, taf: try taf(#""state":"idle","next_run_words":"Next run Mon 09:00""#))
            RetainedRuns(model: pages)
        }
        .padding(20).frame(width: 520).background(Theme.background)
        .environment(\.words, Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"]))
        guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 520, height: 520)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: "build/screenshots"), withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: "build/screenshots/taf-runs-en.png"))
    }),
]

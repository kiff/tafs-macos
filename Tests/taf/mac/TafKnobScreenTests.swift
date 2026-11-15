import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let strings = URL(fileURLWithPath: ".shared/app/strings")

@MainActor
private func model(_ answers: [(Int, String)]) -> (TafKnobModel, CannedTransport) {
    let transport = CannedTransport(answers)
    return (TafKnobModel(cloud: CloudClient(transport: transport, session: session), taf: "taf-1"), transport)
}

private func taf(_ json: String = #"{"kiff_agent":"a","id":"taf-1","name":"Refunds","state":"working","next_run":"2026-11-16T07:00:00Z","next_run_words":"Next run Mon 08:00","results":["app"]}"#) throws -> Home.Taf {
    try AccountClient.decoder.decode(Home.Page.self, from: Data(#"{"tafs":[\#(json)]}"#.utf8)).tafs[0]
}

let tafKnobMacTests: [Test] = [
    Test("a dial with a change waiting is read at that version; one installed meanwhile is read as it is now", awaiting: { @MainActor in
        let words = Words.load(folder: strings, preferred: ["en"])
        let pending = #"{"version":3,"pending":{"version":4,"changes":1}}"#
        let (m, transport) = model([(200, pending), (404, #"{"error":"not_found"}"#), (200, knobAnswer)])
        await m.load(words: words)
        try expectEqual(transport.sent.map(\.path), ["/v1/tafs/taf%2D1/knob", "/v1/tafs/taf%2D1/knob?version=4", "/v1/tafs/taf%2D1/knob"])
        try expectEqual(m.knob?.version, 3)
        try expectEqual(m.lastError, nil)
        let (unread, _) = model([(500, "")])
        await unread.load(words: words)
        try expectEqual(unread.lastError, "The dial couldn't be read: 500")
    }),
    Test("a size moves only for whoever manages the taf: the setting sent whole, its version kept until it's live", awaiting: { @MainActor in
        let words = Words.load(folder: strings, preferred: ["en"])
        let (m, transport) = model([(200, knobAnswer), (200, #"{"version":4,"words":[]}"#), (200, knobAnswer)])
        await m.load(words: words)
        guard let schedule = m.knob?.wakes.first else { throw Failure(description: "no schedule") }
        let notMine = await m.adjust(schedule, 1, manages: false, words: words)
        try expectEqual(notMine, false)
        try expectEqual(transport.sent.count, 1)
        let moved = await m.adjust(schedule, 1, manages: true, words: words)
        try expectEqual(moved, true)
        try expectEqual(transport.sent.map { $0.method }, ["GET", "PUT", "GET"])
        try expectEqual(m.change?.version, 4)
        // Waiting for version 4, a choice on version 3's dial isn't offered.
        try expectEqual(m.canMove(schedule, -1), false)
    }),
    Test("tafs' own places: the live taf's, the last one can't go, and a change reads the tafs again", awaiting: { @MainActor in
        let words = Words.load(folder: strings, preferred: ["en"])
        let knob = try JSONDecoder().decode(Knob.self, from: Data(knobAnswer.utf8))
        try expectEqual(ResultsGoToView.liveBuiltIns([.string("app"), .string("door_reply")], knob: knob), ["door_reply", "app"])
        try expectEqual(ResultsGoToView.liveBuiltIns(nil, knob: knob), ["app"])
        try expectEqual(ResultsGoToView.places(["app"], switching: "app", on: false), nil)
        try expectEqual(ResultsGoToView.places(["app"], switching: "owner_email", on: true), ["app", "owner_email"])
        try expectEqual(ResultsGoToView.toggled(knob.results[1])?.label, "On")
        try expectEqual(ResultsGoToView.toggled(knob.results[0])?.label, nil)
        let (m, transport) = model([(200, #"{"taf":{}}"#), (200, knobAnswer)])
        var refreshed = 0
        let done = await m.setResultPlaces(["door_reply", "app"], manages: true, words: words, refreshed: { refreshed += 1 })
        try expectEqual(done, true)
        try expectEqual(refreshed, 1)
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["PUT /v1/tafs/taf%2D1/results", "GET /v1/tafs/taf%2D1/knob"])
    }),
    Test("pausing says tafs cloud's words, or that not every start could be paused", awaiting: { @MainActor in
        let words = Words.load(folder: strings, preferred: ["en"])
        let (m, _) = model([(502, ""), (409, #"{"error":"halted","words":"Halted: nothing runs until it's resumed."}"#)])
        var refreshed = 0
        await m.setPaused(true, words: words, refreshed: { refreshed += 1 })
        try expectEqual(m.lastError, "Not every start could be paused. Try again.")
        await m.setPaused(false, words: words, refreshed: { refreshed += 1 })
        try expectEqual(m.lastError, "Halted: nothing runs until it's resumed.")
        try expectEqual(refreshed, 0)
    }),
    Test("the screenshot: Starts when and Results go to, with an approval made on another device", awaiting: { @MainActor in
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let (m, _) = model([(200, knobAnswer), (200, knobAnswer)])
        let words = Words.load(folder: strings, preferred: ["en"])
        await m.load(words: words)
        let refunds = try taf()
        let starts = StartsWhenView(model: m, taf: refunds, manages: true, timeZone: "Europe/Paris", close: {}).environment(\.words, words)
        guard let one = Snapshot.bitmap(of: starts, size: CGSize(width: 520, height: 600)), let png = Snapshot.png(one) else { throw Failure(description: "no PNG") }
        try png.write(to: folder.appendingPathComponent("knob-en.png"))
        let results = ResultsGoToView(model: m, taf: refunds, manages: true, email: "you@example.com", close: {}).environment(\.words, words)
        guard let two = Snapshot.bitmap(of: results, size: CGSize(width: 520, height: 600)), let png2 = Snapshot.png(two) else { throw Failure(description: "no PNG") }
        try png2.write(to: folder.appendingPathComponent("knob-results-en.png"))
    }),
]

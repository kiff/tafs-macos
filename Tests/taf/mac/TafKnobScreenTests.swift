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
        try expectEqual(transport.sent.map(\.path), ["/v1/tafs/taf-1/knob", "/v1/tafs/taf-1/knob?version=4", "/v1/tafs/taf-1/knob"])
        try expectEqual(m.knob?.version, 3)
        try expectEqual(m.lastError, nil)
        let (unread, _) = model([(500, ""), (403, #"{"error":"not_allowed","words":"Only whoever manages the taf can read its dial."}"#)])
        await unread.load(words: words)
        // tafs cloud's line for its status, as the iPad's `CloudError`; its words when it sends some.
        try expectEqual(unread.lastError, "The dial couldn't be read: tafs cloud answered 500")
        await unread.load(words: words)
        try expectEqual(unread.lastError, "The dial couldn't be read: Only whoever manages the taf can read its dial.")
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
    Test("tafs' own places: the live taf's, the last one can't go, and the taf a change answers is the one drawn", awaiting: { @MainActor in
        let words = Words.load(folder: strings, preferred: ["en"])
        let knob = try JSONDecoder().decode(Knob.self, from: Data(knobAnswer.utf8))
        try expectEqual(ResultsGoToView.liveBuiltIns([.string("app"), .string("door_reply")], knob: knob), ["door_reply", "app"])
        try expectEqual(ResultsGoToView.liveBuiltIns(nil, knob: knob), ["app"])
        try expectEqual(ResultsGoToView.places(["app"], switching: "app", on: false), nil)
        try expectEqual(ResultsGoToView.places(["app"], switching: "owner_email", on: true), ["app", "owner_email"])
        try expectEqual(ResultsGoToView.toggled(knob.results[1])?.label, "On")
        try expectEqual(ResultsGoToView.toggled(knob.results[0])?.label, nil)
        let (m, transport) = model([(200, tafAnswer), (200, knobAnswer), (200, #"{"taf":{}}"#)])
        let done = await m.setResultPlaces(["door_reply", "app"], manages: true, words: words)
        try expectEqual(done, true)
        try expectEqual(m.updated?.results, [.string("app")])
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["PUT /v1/tafs/taf-1/results", "GET /v1/tafs/taf-1/knob"])
        // An answer that isn't the taf isn't a change.
        let again = await m.setResultPlaces(["app"], manages: true, words: words)
        try expectEqual(again, false)
        try expect(m.lastError?.hasPrefix("Where its results go didn't change: ") == true, "says it wasn't changed")
        m.homeRead()
        try expectEqual(m.updated, nil)
    }),
    Test("pausing says tafs cloud's words, or that not every start could be paused", awaiting: { @MainActor in
        let words = Words.load(folder: strings, preferred: ["en"])
        let (m, _) = model([(502, ""), (409, #"{"error":"halted","words":"Halted: nothing runs until it's resumed."}"#), (200, tafAnswer)])
        var refreshed = 0
        await m.setPaused(true, words: words, refreshed: { refreshed += 1 })
        try expectEqual(m.lastError, "Not every start could be paused. Try again.")
        await m.setPaused(false, words: words, refreshed: { refreshed += 1 })
        try expectEqual(m.lastError, "Halted: nothing runs until it's resumed.")
        try expectEqual(refreshed, 0)
        // The taf it answers is the one drawn: paused, as tafs cloud says it.
        await m.setPaused(true, words: words, refreshed: { refreshed += 1 })
        try expectEqual(m.updated?.paused, true)
        try expectEqual(refreshed, 1)
        try expectEqual(m.lastError, nil)
    }),
    Test("an error set elsewhere isn't the dial read's: the next good read leaves it, as the iPad's lastErrorFrom", awaiting: { @MainActor in
        let words = Words.load(folder: strings, preferred: ["en"])
        let (m, _) = model([(500, ""), (409, #"{"error":"gone","words":"That follow-up already fired."}"#), (200, knobAnswer)])
        await m.load(words: words)
        try expect(m.lastError != nil, "the dial's read failed")
        // A follow-up refused: its own error, which the read after it doesn't wipe.
        await m.removeFollowUp("fu-1", manages: true, words: words)
        try expectEqual(m.lastError, "The follow-up wasn't removed: That follow-up already fired.")
    }),
    Test("times are the account's, as the iPad's AccountTime: HH:mm, its zone named when it isn't this Mac's, UTC for a zone unknown") {
        let at = Date(timeIntervalSince1970: 1_794_812_400) // 2026-11-16T07:00:00Z
        let paris = AccountTime("Europe/Paris")
        try expectEqual(paris.shortTime(at), "08:00")
        try expectEqual(paris.zonedShortTime(at, here: TimeZone(identifier: "Europe/Paris")!), "08:00")
        try expectEqual(paris.zonedShortTime(at, here: TimeZone(identifier: "America/New_York")!).hasPrefix("08:00 "), true)
        // UTC, by its offset: macOS names that zone "GMT" as often as "UTC".
        try expectEqual(AccountTime("Nowhere/Else").zone.secondsFromGMT(), 0)
        try expectEqual(AccountTime(nil).zone, TimeZone.current)
    },
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

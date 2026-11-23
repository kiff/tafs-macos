import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

/// tafs cloud's answer to a change to the taf: the taf, as the iPad's `CloudTaf` reads it.
let tafAnswer = #"{"taf":{"id":"taf-1","name":"Refunds","job":"refunds","status":"paused","results":["app"],"next_run":"2026-11-16T07:00:00Z"}}"#

/// A dial as tafs cloud sends it: a schedule with sizes, an app event to approve, one
/// listening, a follow-up, tafs' own places and one in an app, and its live setting.
let knobAnswer = #"""
{"version":3,"can_pause":true,"why":"Answer refunds","does":{"label":"Refunds","line":"Answers refund requests"},
 "wakes":[
  {"id":"s1","kind":"schedule","label":"Every morning","words":"Every weekday at 08:00","trigger":{"cron":"0 8 * * 1-5"},
   "size":{"label":"How often","index":1,"choices":[{"label":"Once a day","setting":{"wakes":[{"cron":"0 8 * * *"}],"when":{"busy":"skip"},"results":["app"]}},{"label":"Weekdays","setting":{"wakes":[{"cron":"0 8 * * 1-5"}],"when":{"busy":"skip"},"results":["app"]}},{"label":"Twice a day","setting":{"wakes":[{"cron":"0 8,16 * * 1-5"}],"when":{"busy":"skip"},"results":["app"]}}]}},
  {"id":"e1","kind":"app_event","label":"New Stripe dispute","words":"When a dispute opens","ok":"approve","on":false,
   "approval":{"state":"needed","grant":"g1","event":"dispute.created","config":{"limit":3}}},
  {"id":"e2","kind":"app_event","label":"New email","words":"","on":true,"trigger":{"event":"mail"}},
  {"id":"f1","kind":"follow_up","label":"Check back","words":"Check the refund on Friday","follow_up":"fu-1","expires":"2026-11-20T09:00:00.000Z"}],
 "results":[{"id":"r1","place":"app","label":"Alert our phones","words":"","on":true},
  {"id":"r2","place":"notion","label":"Notion page","words":"Writes a line","on":false,
   "size":{"label":"Notion","index":0,"choices":[{"label":"Off","setting":{"wakes":[],"when":{"busy":"skip"},"results":["app"]}},{"label":"On","setting":{"wakes":[],"when":{"busy":"skip"},"results":["app",{"place":"notion","page":"p1"}]}}]}}],
 "rim":{"done":2,"needs_you":1},
 "setting":{"wakes":[{"cron":"0 8 * * 1-5"},{"event":"mail"}],"when":{"busy":"skip"},"results":["app",{"place":"notion","page":"p1"}]}}
"""#

private func client(_ answers: [(Int, String)]) -> (CloudClient, CannedTransport) {
    let transport = CannedTransport(answers)
    return (CloudClient(transport: transport, session: session), transport)
}

let tafKnobTests: [Test] = [
    Test("a dial reads as the iPad's: its stops, sizes, approvals and setting, and what isn't said takes the iPad's defaults") {
        let knob = try JSONDecoder().decode(Knob.self, from: Data(knobAnswer.utf8))
        try expectEqual(knob.version, 3)
        try expectEqual(knob.wakes.map(\.id), ["s1", "e1", "e2", "f1"])
        try expectEqual(knob.wakes[0].size?.choices.map(\.label), ["Once a day", "Weekdays", "Twice a day"])
        try expectEqual(knob.wakes[0].size?.choice(moving: 1)?.label, "Twice a day")
        try expectEqual(knob.wakes[0].size?.choice(moving: 2)?.label, nil)
        try expectEqual(knob.wakes[1].approval?.state, "needed")
        try expectEqual(knob.wakes[3].followUp, "fu-1")
        try expectEqual(knob.rim.total, 3)
        try expectEqual(knob.setting?.busy, "skip")
        try expectEqual(knob.setting?.sends(to: "notion"), true)
        try expectEqual(knob.setting?.sends(to: "owner_email"), false)
        // A stop that doesn't say is on; no can_pause is the older servers' yes.
        let bare = try JSONDecoder().decode(Knob.self, from: Data(#"{"wakes":[{"id":"x"}]}"#.utf8))
        try expectEqual(bare.wakes[0].on, true)
        try expectEqual(bare.wakes[0].label, "")
        try expectEqual(bare.canPause, true)
        // Where the iPad is strict, so is this: a stop without its id, or a size that isn't one.
        try expect((try? JSONDecoder().decode(Knob.self, from: Data(#"{"wakes":[{"label":"no id"}]}"#.utf8))) == nil, "no id")
        try expect((try? JSONDecoder().decode(Knob.self, from: Data(#"{"wakes":[{"id":"x","size":7}]}"#.utf8))) == nil, "no size")
    },
    Test("a choice can be made only on the newest version known here, as the iPad's acceptsChoices") {
        var knob = try JSONDecoder().decode(Knob.self, from: Data(knobAnswer.utf8))
        try expectEqual(knob.acceptsChoices(), true)
        try expectEqual(knob.acceptsChoices(waitingFor: 4), false)
        knob = try JSONDecoder().decode(Knob.self, from: Data(#"{"version":3,"pending":{"version":4,"changes":1},"shown":4}"#.utf8))
        try expectEqual(knob.acceptsChoices(), true)
        knob = try JSONDecoder().decode(Knob.self, from: Data(#"{"version":3,"pending":{"version":4,"changes":1}}"#.utf8))
        try expectEqual(knob.acceptsChoices(), false)
    },
    Test("a setting is sent whole as PUT …/knob takes it, busy under when, and a change answers its version", awaiting: {
        let (cloud, transport) = client([(200, #"{"version":4,"words":["Runs twice a day"]}"#)])
        let knob = try JSONDecoder().decode(Knob.self, from: Data(knobAnswer.utf8))
        guard var setting = knob.setting else { throw Failure(description: "no setting") }
        setting.busy = "latest"
        let change = try await cloud.putKnob(of: "taf-1", setting)
        try expectEqual(change, Knob.Change(version: 4, words: ["Runs twice a day"]))
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "PUT /v1/tafs/taf-1/knob")
        try expectEqual(String(decoding: transport.sent[0].body, as: UTF8.self),
                        #"{"results":["app",{"page":"p1","place":"notion"}],"wakes":[{"cron":"0 8 * * 1-5"},{"event":"mail"}],"when":{"busy":"latest"}}"#)
    }),
    Test("the dial, its waiting version, tafs' own places, a follow-up and a pause each have their route", awaiting: {
        let (cloud, transport) = client([(200, knobAnswer), (200, knobAnswer), (200, tafAnswer), (200, #"{"removed":"fu-1"}"#), (200, tafAnswer), (200, tafAnswer)])
        _ = try await cloud.knob(of: "taf-1")
        _ = try await cloud.knob(of: "taf-1", version: 4)
        let placed = try await cloud.putResults(of: "taf-1", places: ["door_reply", "app"])
        try expectEqual(placed.results, [.string("app")])
        try await cloud.removeFollowUp(of: "taf-1", "fu 1")
        let paused = try await cloud.setPaused("taf-1", true)
        try expectEqual(paused.paused, true)
        _ = try await cloud.setPaused("taf-1", false)
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, [
            "GET /v1/tafs/taf-1/knob", "GET /v1/tafs/taf-1/knob?version=4", "PUT /v1/tafs/taf-1/results",
            "DELETE /v1/tafs/taf-1/follow-ups/fu%201", "POST /v1/tafs/taf-1/pause", "POST /v1/tafs/taf-1/resume",
        ])
        try expectEqual(String(decoding: transport.sent[2].body, as: UTF8.self), #"{"places":["door_reply","app"]}"#)
        try expectEqual(transport.sent[3].body, Data())
        try expectEqual(transport.sent[3].headers["Content-Type"], nil)
    }),
    Test("a change to the taf answers the taf as the iPad's CloudTaf, or it isn't a change; the dial read refuses with tafs cloud's words", awaiting: {
        let (cloud, _) = client([(200, #"{"taf":{}}"#), (200, #"{"taf":{"id":"taf-1","name":"Refunds","job":"refunds"}}"#), (200, "{}"),
                                 (403, #"{"error":"not_allowed","words":"Only whoever manages the taf can read its dial."}"#)])
        for _ in 0..<2 {
            do { _ = try await cloud.setPaused("taf-1", true); throw Failure(description: "read") } catch let error as KIFFError {
                try expectEqual(error, .unreadable)
            }
        }
        do { _ = try await cloud.putResults(of: "taf-1", places: ["app"]); throw Failure(description: "read") } catch let error as KIFFError {
            try expectEqual(error, .unreadable)
        }
        do { _ = try await cloud.knob(of: "taf-1"); throw Failure(description: "read") } catch let refusal as CloudRefusal {
            try expectEqual(refusal.words, "Only whoever manages the taf can read its dial.")
        }
    }),
    Test("a removed follow-up must say so, and a refusal says tafs cloud's words", awaiting: {
        let (cloud, _) = client([(200, "{}"), (409, #"{"error":"not_found","words":"That follow-up already fired."}"#)])
        do { try await cloud.removeFollowUp(of: "taf-1", "fu-1"); throw Failure(description: "read") } catch let error as KIFFError {
            try expectEqual(error, .unreadable)
        }
        do { try await cloud.removeFollowUp(of: "taf-1", "fu-1"); throw Failure(description: "sent") } catch let refusal as CloudRefusal {
            try expectEqual(refusal.words, "That follow-up already fired.")
        }
    }),
    Test("Home's taf keeps where its results go, and the account's time zone is KIFF's") {
        let page = try AccountClient.decoder.decode(Home.Page.self, from: Data(#"{"tafs":[{"kiff_agent":"a","id":"taf-1","name":"Rae","state":"working","results":["door_reply",{"place":"notion"}]},{"kiff_agent":"b","name":"Ben","state":"working"}]}"#.utf8))
        try expectEqual(page.tafs[0].results, [.string("door_reply"), .object(["place": .string("notion")])])
        try expectEqual(page.tafs[1].results, nil)
        let me = try AccountClient.decoder.decode(Me.self, from: Data(#"{"time_zone":"Europe/Paris"}"#.utf8))
        try expectEqual(me.timeZone, "Europe/Paris")
    },
    Test("an app event's filters read as the iPad's sheet shows them before signing: the whole config, sorted, slashes as written") {
        let approval = try JSONDecoder().decode(Knob.Item.Approval.self, from: Data(#"{"state":"needed","grant":"g1","event":"issue.created","config":{"repo":"acme/api","labels":["bug"]}}"#.utf8))
        try expectEqual(Knob.filtersText(approval), "{\n  \"labels\" : [\n    \"bug\"\n  ],\n  \"repo\" : \"acme/api\"\n}")
        try expectEqual(Knob.filtersText(nil), nil)
        let empty = try JSONDecoder().decode(Knob.Item.Approval.self, from: Data(#"{"state":"needed","grant":"g1","event":"e","config":{}}"#.utf8))
        try expectEqual(Knob.filtersText(empty), nil)
    },
]

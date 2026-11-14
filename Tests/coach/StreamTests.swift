import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

let streamLines = [
    "event: session", #"data: {"session":"s1","new_session":false,"run":"r9","message":{"id":"m9","at":"2026-11-14T18:00:01Z"}}"#, "",
    "event: thinking", #"data: {"text":"The person wants Qonto."}"#, "",
    "event: state", #"data: {"state":"working","words":"Looking at Qonto…"}"#, "",
    "event: activity", #"data: {"tool":"planque_connect","step":"Asking KIFF: connect Qonto…","call_id":"c1"}"#, "",
    "event: step", #"data: {"call_id":"c1","status":"error","failed":true,"why":"Why: managed sign-in isn't set up for this app"}"#, "",
    "event: text", #"data: {"text":"I can connect "}"#, "",
    "event: text", #"data: {"text":"Qonto with its key."}"#, "",
    "event: held", #"data: {"exception":"exc_1","invocation":"i1"}"#, "",
    ": keep-alive", "",
    "event: end", #"data: {"status":"DONE","stop":"end_turn"}"#, "",
]

let coachStreamTests: [Test] = [
    Test("the stream's lines are read as tafs cloud's events, and thinking is never one") {
        var reader = EventReader()
        let events = streamLines.compactMap { reader.read($0) }
        try expectEqual(events, [
            .session(message: "m9"),
            .state(words: "Looking at Qonto…"),
            .activity(words: "Asking KIFF: connect Qonto…"),
            .step(failed: true, why: "Why: managed sign-in isn't set up for this app"),
            .text("I can connect "), .text("Qonto with its key."),
            .threadChanged,
            .end(words: nil),
        ])
    },
    Test("the answer grows as it is written, with one line for where the run is") {
        var reader = EventReader()
        var live = LiveAnswer()
        var reloads = 0
        try expectEqual(live.line, nil)
        for line in streamLines {
            if let event = reader.read(line), live.take(event) { reloads += 1 }
        }
        try expectEqual(live.text, "I can connect Qonto with its key.")
        try expectEqual(live.line, "Asking KIFF: connect Qonto…")
        try expectEqual(live.trouble, "Why: managed sign-in isn't set up for this app")
        try expectEqual(reloads, 1)
    },
    Test("an event that isn't what the docs say is dropped, never drawn as words") {
        var reader = EventReader()
        let lines = ["event: text", "data: not json", "event: text", #"data: {"text":7}"#, "event: surprise", #"data: {"text":"hello"}"#,
                     "data: {\"text\":\"still surprise\"}", "event: end", #"data: {"status":"ERROR","code":"ai_unavailable","words":"The AI isn't answering just now. None of your credits were used."}"#,
                     "event: error", #"data: {"error":"upstream"}"#]
        try expectEqual(lines.compactMap { reader.read($0) },
                        [.end(words: "The AI isn't answering just now. None of your credits were used."), .broke])
    },
    Test("a step with no words clears the line, and a state with none keeps it") {
        var live = LiveAnswer()
        _ = live.take(.activity(words: "Drafting the Card…"))
        _ = live.take(.state(words: nil))
        try expectEqual(live.line, "Drafting the Card…")
        _ = live.take(.activity(words: nil))
        try expectEqual(live.line, nil)
    },
    Test("the stream's request is the same message, asked for as events") {
        let client = CloudClient(transport: CannedTransport([]), session: session, language: "pt")
        let request = client.streamRequest("  Connect Qonto ", to: "taf-coach")
        try expectEqual(request?.method, "POST")
        try expectEqual(request?.path, "/v1/tafs/taf%2Dcoach/messages/stream")
        try expectEqual(request?.headers["Accept"], "text/event-stream")
        try expectEqual(request?.headers["Authorization"], "Bearer tok")
        try expectEqual(request.flatMap { try? JSONDecoder().decode([String: String].self, from: $0.body) }, ["text": "Connect Qonto"])
        try expect(client.streamRequest("   ", to: "taf-coach") == nil, "nothing to send")
        try expect(client.streamRequest(String(repeating: "x", count: 2001), to: "taf-coach") == nil, "too long")
    },
]

import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

/// A transport that answers an `ETag`, as tafs cloud does on the runs.
final class TaggedTransport: Transport, @unchecked Sendable {
    var answers: [(Int, String, String?)]
    private(set) var sent: [HTTPRequest] = []
    init(_ answers: [(Int, String, String?)]) { self.answers = answers }
    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        let (status, body, _) = try await exchange(request)
        return (status, body)
    }
    func exchange(_ request: HTTPRequest) async throws -> (status: Int, body: Data, etag: String?) {
        sent.append(request)
        let (status, body, tag) = answers.isEmpty ? (500, "", nil) : answers.removeFirst()
        return (status, Data(body.utf8), tag)
    }
}

let runsPageAnswer = #"""
{"requests":[
  {"id":"r2","at":"2026-11-15T09:00:00Z","state":"done","line":"Refunded order 4471","credits":{"credits":34,"counted":true,"words":" 34 credits "},
   "deliveries":[{"place":"door_reply","state":"sent","line":"Replied to ana@acme.com"},{"place":7}]},
  {"id":"r1","at":"2026-11-15T07:00:00.250Z","state":7,"line":"Checked the inbox","credits":{"credits":"many"}}
 ],
 "skipped":[{"due":"2026-11-15T08:00:00Z","why":"busy","words":"Skipped 08:00: still busy"},{"due":"2026-11-15T09:00:00Z","why":"missed","words":"Skipped 09:00: missed"}],
 "next_cursor":"c2","title":"Its work","more_title":"See all its work","end_words":"That's all."}
"""#

let tafRunsTests: [Test] = [
    Test("a request that waits on a step its taf handed the owner carries that step (your_step), as the iPad's TafWork.Request") {
        let request = { (step: String) in
            try AccountClient.decoder.decode(TafRuns.Request.self, from: Data((#"{"id":"r1","at":"2026-11-15T09:00:00Z","state":"needs_you","line":"Waits for your step","your_step":"# + step + "}").utf8))
        }
        let waiting = try request(#"{"handoff":"h1","taf":{"id":"t1","name":"Refunds"},"what":"Approve the transfer in Qonto","why":"Over the Card's limit","words":{"title":"Your step","done":"Done","skip":"Skip it"}}"#)
        try expectEqual(waiting.yourStep?.handoff, "h1")
        try expectEqual(waiting.yourStep?.what, "Approve the transfer in Qonto")
        try expectEqual(waiting.yourStep?.words.done, "Done")
        try expectEqual(waiting.line, "Waits for your step")
        // A step that doesn't read is none, and the request is still read, with its line.
        let odd = try request("7")
        try expectEqual(odd.yourStep, nil)
        try expectEqual(odd.line, "Waits for your step")
        try expectEqual(try AccountClient.decoder.decode(TafRuns.Request.self, from: Data(#"{"id":"r2","at":"2026-11-15T09:00:00Z"}"#.utf8)).yourStep, nil)
    },
    Test("the runs a taf kept read as the iPad's RunsPage: each run's words, what it used, where its result went") {
        let page = try AccountClient.decoder.decode(TafRuns.Page.self, from: Data(runsPageAnswer.utf8))
        try expectEqual(page.requests.map(\.id), ["r2", "r1"])
        try expectEqual(page.requests[0].creditsLine, "34 credits")
        try expectEqual(page.requests[0].deliveries.map(\.line), ["Replied to ana@acme.com", ""])
        try expectEqual(page.requests[0].deliveries[1].place, "door_reply")
        // A state that isn't words is none, and a figure that can't be read is no line.
        try expectEqual(page.requests[1].state, "")
        try expectEqual(page.requests[1].credits, nil)
        try expectEqual(page.nextCursor, "c2")
        try expectEqual(page.moreTitle, "See all its work")
        try expectEqual(page.endWords, "That's all.")
    },
    Test("a page without its heading, a run without its id or time, or a skipped firing without its words doesn't read") {
        let decode = { (json: String) in try? AccountClient.decoder.decode(TafRuns.Page.self, from: Data(json.utf8)) }
        try expect(decode(#"{"requests":[],"more_title":"See all"}"#) == nil, "no title")
        try expect(decode(#"{"requests":[],"title":"Its work"}"#) == nil, "no more_title")
        try expect(decode(#"{"requests":[{"at":"2026-11-15T09:00:00Z"}],"title":"T","more_title":"M"}"#) == nil, "a run without its id")
        try expect(decode(#"{"requests":[{"id":"r1"}],"title":"T","more_title":"M"}"#) == nil, "a run without its time")
        try expect(decode(#"{"requests":[],"title":"T","more_title":"M","skipped":[{"due":"2026-11-15T09:00:00Z","why":"busy"}]}"#) == nil, "a skipped firing without its words")
        let bare = decode(#"{"requests":[],"title":"T","more_title":"M"}"#)
        try expectEqual(bare?.nextCursor, nil)
        try expectEqual(bare?.skipped, nil)
    },
    Test("the first page's rows put the skipped firings among the runs, newest first, in the order sent at the same time") {
        let page = try AccountClient.decoder.decode(TafRuns.Page.self, from: Data(runsPageAnswer.utf8))
        let at = { (iso: String) in ISO8601DateFormatter().date(from: iso)!.timeIntervalSince1970 }
        // r2 and the 09:00 firing share a time: the run, sent first, comes first.
        try expectEqual(page.rows(first: true).map(\.id), ["r|r2", "s|\(at("2026-11-15T09:00:00Z"))", "s|\(at("2026-11-15T08:00:00Z"))", "r|r1"])
        try expectEqual(page.rows(first: false).map(\.id), ["r|r2", "r|r1"])
        try expectEqual(TafRuns.limit(all: false), 3)
        try expectEqual(TafRuns.limit(all: true), 20)
    },
    Test("the runs are read by the taf's id with their limit and cursor; asked again with the ETag, a 304 keeps them", awaiting: {
        let transport = TaggedTransport([(200, runsPageAnswer, "\"v1\""), (304, "", nil), (200, runsPageAnswer, nil), (409, #"{"error":"x","words":"Not now."}"#, nil)])
        let cloud = CloudClient(transport: transport, session: session)
        let (first, tag) = try await cloud.runsPage(of: "taf-1", cursor: nil, etag: nil, limit: 3)
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "GET /v1/tafs/taf-1/work/runs?limit=3")
        try expectEqual(transport.sent[0].headers["If-None-Match"], nil)
        try expectEqual(first?.requests.count, 2)
        try expectEqual(tag, "\"v1\"")
        let (same, kept) = try await cloud.runsPage(of: "taf-1", cursor: nil, etag: tag, limit: 3)
        try expectEqual(transport.sent[1].headers["If-None-Match"], "\"v1\"")
        try expectEqual(same, nil)
        try expectEqual(kept, "\"v1\"")
        _ = try await cloud.runsPage(of: "taf-1", cursor: "c 2", etag: nil, limit: 20)
        try expectEqual(transport.sent[2].path, "/v1/tafs/taf-1/work/runs?limit=20&cursor=c%202")
        do { _ = try await cloud.runsPage(of: "taf-1", cursor: nil, etag: nil, limit: 3); throw Failure(description: "read") } catch let refusal as CloudRefusal {
            try expectEqual(refusal.words, "Not now.")
        }
    }),
    Test("Run now posts once, unsigned; tafs cloud's words only when it started no run", awaiting: {
        let transport = CannedTransport([(200, #"{"session":"s9","words":"ignored"}"#), (200, #"{"session":null,"words":"It ran 2 minutes ago."}"#), (200, #"{"words":"   "}"#)])
        let cloud = CloudClient(transport: transport, session: session)
        let started = try await cloud.runNow("taf-1")
        try expectEqual(started, TafRuns.RunNow(session: "s9", words: nil))
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "POST /v1/tafs/taf-1/run")
        try expectEqual(String(decoding: transport.sent[0].body, as: UTF8.self), "{}")
        let none = try await cloud.runNow("taf-1")
        try expectEqual(none, TafRuns.RunNow(session: nil, words: "It ran 2 minutes ago."))
        let blank = try await cloud.runNow("taf-1")
        try expectEqual(blank, TafRuns.RunNow(session: nil, words: nil))
    }),
]

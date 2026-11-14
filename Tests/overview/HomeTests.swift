import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

let homePage = #"""
{"tafs":[
  {"id":"taf_1","name":"Refunds","kiff_agent":"agent_refunds","color":1,"state":"working","waiting":2,
   "job_summary":"Refunds orders within its limit.","work":{"status":"working","line":"Working on 3 refunds","needs_you":2},
   "next_run_words":"Next run Mon 08:00","health":{"level":"healthy","lines":[]},"card":{"ids":["c1"]}},
  {"id":"taf_2","name":"Invoices","kiff_agent":"agent_invoices","color":4,"state":"idle","waiting":0,
   "work":{"status":"idle","line":"  ","attention":true},"next_run_words":"Next run Mon 08:00",
   "health":{"level":"degraded","lines":["Its bank connection needs signing in again.","Second line"]}},
  {"name":"Bare","kiff_agent":"agent_bare","state":"stopped"}
],"headline":{"words":"1 taf working."},"needs_you":{"count":2,"words":"2 need you."},"limits":{"text":4000}}
"""#

private func cloud(_ answers: [(Int, String)]) -> (CloudClient, CannedTransport) {
    let transport = CannedTransport(answers)
    return (CloudClient(transport: transport, session: session, language: "fr"), transport)
}

let overviewTests: [Test] = [
    Test("the list is read as tafs cloud sends it, with its own counts and words", awaiting: {
        let (client, transport) = cloud([(200, homePage)])
        let page = try await client.home()
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "GET /v1/home")
        try expectEqual(transport.sent[0].headers["Accept-Language"], "fr")
        try expectEqual(page.headline, "1 taf working.")
        try expectEqual(page.needsYouCount, 2)
        try expectEqual(page.needsYouWords, "2 need you.")
        try expectEqual(page.tafs.map(\.name), ["Refunds", "Invoices", "Bare"])
        try expectEqual(page.tafs[0].now, "Working on 3 refunds")
        try expectEqual(page.tafs[0].waiting, 2)
        try expectEqual(page.tafs[0].trouble, nil)
    }),
    Test("now is the work's line, else the next run, and never a line the app wrote", awaiting: {
        let page = try await cloud([(200, homePage)]).0.home()
        // A blank work line is no line: the next run's words stand in.
        try expectEqual(page.tafs[1].now, "Next run Mon 08:00")
        try expectEqual(page.tafs[1].attention, true)
        try expectEqual(page.tafs[1].trouble, "Its bank connection needs signing in again.")
        try expectEqual(page.tafs[2].now, nil)
        try expectEqual(page.tafs[2].color, 0)
        try expectEqual(page.tafs[2].health, nil)
    }),
    Test("a list that isn't one is unreadable, never \"no tafs\", and a missing headline is just absent", awaiting: {
        for body in ["{}", "<html>", #"{"tafs":[{"name":"No agent","state":"idle"}]}"#] {
            do { _ = try await cloud([(200, body)]).0.home(); throw Failure(description: "\(body) was read") } catch let error as KIFFError { try expectEqual(error, .unreadable) }
        }
        let bare = try await cloud([(200, #"{"tafs":[],"headline":7,"needs_you":"soon"}"#)]).0.home()
        try expectEqual(bare.tafs.count, 0)
        try expectEqual(bare.headline, nil)
        try expectEqual(bare.needsYouCount, nil)
    }),
]

import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

private let workAnswer = #"""
{"summary":{"status":"idle","line":"Nothing matched, so nothing ran","needs_you":0},
 "requests":[
   {"id":"r1","at":"2026-11-15T07:00:00Z","state":"done","line":"Refunded order 4471","credits":{"credits":34,"counted":true,"words":"34 credits"},
    "deliveries":[{"place":"door_reply","state":"given_up","line":"The reply wasn't delivered","send_again":true},
                  {"place":"action","key":"slack-post","state":"not_sent","line":"Not posted to Slack","send_again":true}]},
   {"id":"r2","at":"2026-11-15T09:00:00Z","state":"needs_you","line":"Waiting for you"}
 ],
 "skipped":[{"due":"2026-11-15T08:00:00Z","why":"busy","words":"Skipped 08:00: still busy"}],
 "health":{"level":"at_risk","lines":["Nothing matched, so nothing ran. Narrow it with Coach."]},
 "oldest_waiting":{"since":"2026-11-15T04:00:00Z","words":"Oldest case waiting 5 h","late":true},
 "promise":{"hours":4}}
"""#

let tafWorkTests: [Test] = [
    Test("a run's request reads as the iPad's RequestDetail, from its own path, and each step's mark is the iPad's", awaiting: {
        let answer = #"{"id":"r1","from":"From the website door","line":"Refund order 4471","steps":[{"label":"Read the order","state":"done"},{"label":"Refund it","line":"Waiting on Stripe","state":"next"},{"label":"Reply","state":"failed"}],"deliveries":[{"place":"door_reply","state":"given_up","send_again":true}]}"#
        let transport = CannedTransport([(200, answer)])
        let detail = try await CloudClient(transport: transport, session: session).request(of: "taf 1", run: "r/1")
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "GET /v1/tafs/taf%201/requests/r%2F1")
        try expectEqual(detail.from, "From the website door")
        try expectEqual(detail.steps.map(RequestDetail.mark), [.done, .next, .stopped])
        try expectEqual(detail.steps[1].line, "Waiting on Stripe")
        try expectEqual(detail.deliveries.first?.sendPlace, "door_reply")
        try expectEqual(detail.deliveries.first?.sendAgain, true)
    }),
    Test("a taf's work reads as the iPad's TafWork: its rows newest first, its oldest waiting case, the owner's promise") {
        let work = try AccountClient.decoder.decode(TafWork.self, from: Data(workAnswer.utf8))
        try expectEqual(work.rows.map(\.id).first, "r|r2")
        try expectEqual(work.rows.count, 3)
        try expectEqual(work.oldestWaiting, TafWork.OldestWaiting(words: "Oldest case waiting 5 h", late: true))
        try expectEqual(work.promiseHours, 4)
        try expectEqual(work.requests[0].deliveries.map(\.sendPlace), ["door_reply", "slack-post"])
        // An idle taf's line is its health's first reason: said once, by the health.
        try expectEqual(work.shownLine(health: work.health), nil)
        try expectEqual(work.shownLine(health: nil), "Nothing matched, so nothing ran")
    },
    Test("a work with none of its parts, or parts that aren't theirs, reads as nothing to say, never a failed read") {
        let bare = try AccountClient.decoder.decode(TafWork.self, from: Data(#"{}"#.utf8))
        try expectEqual(bare.rows.count, 0)
        try expectEqual(bare.line, nil)
        let odd = try AccountClient.decoder.decode(TafWork.self, from: Data(#"{"summary":{"line":"  "},"oldest_waiting":{"words":" "},"promise":{"hours":0},"health":7}"#.utf8))
        try expectEqual(odd.line, nil)
        try expectEqual(odd.oldestWaiting, nil)
        try expectEqual(odd.promiseHours, nil)
        try expectEqual(odd.health, nil)
    },
    Test("Answer within is said in whole days where it can be, else hours, and Not set with none") {
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        try expectEqual(TafWork.promise(nil, words: words), "Not set")
        try expectEqual(TafWork.promise(1, words: words), "1 hour")
        try expectEqual(TafWork.promise(8, words: words), "8 hours")
        try expectEqual(TafWork.promise(24, words: words), "1 day")
        try expectEqual(TafWork.promise(168, words: words), "7 days")
        try expectEqual(TafWork.Failure.notSentAgain(why: "Offline.").line(words), "It wasn't sent again. Offline.")
    },
    Test("the work is read by the taf's id; the promise is put in hours, or null to clear it; Send again posts to the place", awaiting: {
        let transport = CannedTransport([(200, workAnswer), (200, "{}"), (200, "{}"), (200, #"{"state":"sent"}"#)])
        let cloud = CloudClient(transport: transport, session: session)
        _ = try await cloud.work(of: "taf/1")
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "GET /v1/tafs/taf%2F1/work")
        try await cloud.setPromise(of: "taf-1", hours: 24)
        try expectEqual(transport.sent[1].method + " " + transport.sent[1].path, "PUT /v1/tafs/taf-1/promise")
        try expectEqual(String(decoding: transport.sent[1].body, as: UTF8.self), #"{"hours":24}"#)
        try await cloud.setPromise(of: "taf-1", hours: nil)
        try expectEqual(String(decoding: transport.sent[2].body, as: UTF8.self), #"{"hours":null}"#)
        try await cloud.sendAgain(of: "taf-1", run: "r1", place: "slack-post")
        try expectEqual(transport.sent[3].method + " " + transport.sent[3].path, "POST /v1/tafs/taf-1/requests/r1/deliveries/slack-post/send")
    }),
]

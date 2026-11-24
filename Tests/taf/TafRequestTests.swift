import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let detail = #"""
{"id":"run/7","from":"From the door","line":"Refund for order 1042",
 "steps":[{"label":"Read the order","line":"Order 1042, €42","at":"09:02","state":"done"},
          {"label":"Refund it","state":"next"},
          {"label":"Reply to the customer","line":"Slack didn't answer","state":"failed"}],
 "deliveries":[{"place":"door_reply","state":"not_sent","line":"Not sent yet","send_again":true},
               {"place":"app","key":"notion","state":"sent","line":"Sent to Notion"}]}
"""#

let tafRequestTests: [Test] = [
    Test("a run opened from its line, as the iPad's RequestDetail: tafs cloud's heading, line, steps and deliveries", awaiting: {
        let transport = CannedTransport([(200, detail)])
        let run = try await CloudClient(transport: transport, session: session).request(of: "taf/1", run: "run/7")
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["GET /v1/tafs/taf%2F1/requests/run%2F7"])
        try expectEqual(run.from, "From the door")
        try expectEqual(run.steps.map(\.mark), [.done, .next, .failed])
        try expectEqual(run.steps.map(\.line), ["Order 1042, €42", nil, "Slack didn't answer"])
        try expectEqual(run.deliveries.map(\.sendPlace), ["door_reply", "notion"])
    }),
    Test("Send again only for whoever manages the taf, and only a delivery that offers it; Ask Coach as the iPad's", awaiting: {
        let run = try await CloudClient(transport: CannedTransport([(200, detail)]), session: session).request(of: "taf-1", run: "r")
        try expectEqual(run.sendsAgain(manages: false), [])
        try expectEqual(run.sendsAgain(manages: true).map(\.place), ["door_reply"])
        try expectEqual(TafRequest.offersAskCoach(mayUseCoach: true, manages: true), true)
        try expectEqual(TafRequest.offersAskCoach(mayUseCoach: true, manages: false), false)
        try expectEqual(TafRequest.offersAskCoach(mayUseCoach: false, manages: true), false)
    }),
    Test("a run that doesn't read whole fails the read, and a refusal says tafs cloud's words", awaiting: {
        let missing = CloudClient(transport: CannedTransport([(200, #"{"id":"r","from":"x","line":"y","steps":[{"label":"a"}],"deliveries":[]}"#)]), session: session)
        do { _ = try await missing.request(of: "taf-1", run: "r"); throw Failure(description: "read a step with no state") } catch is KIFFError {}
        let refused = CloudClient(transport: CannedTransport([(404, #"{"error":"not_found","words":"This run isn't kept any more."}"#)]), session: session)
        do { _ = try await refused.request(of: "taf-1", run: "r"); throw Failure(description: "read a refusal") } catch let r as CloudRefusal {
            try expectEqual(r.words, "This run isn't kept any more.")
        }
    }),
]

import Foundation

private let words = try! Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

let approvalsHeldContinueTests: [Test] = [
    Test("once KIFF takes a held call's answer, tafs cloud is asked to continue that taf's run, by its id and the hold's", awaiting: {
        let transport = CannedTransport([(200, #"{"run":"run_1","status":"running"}"#)])
        let cloud = CloudClient(transport: transport, session: session)
        try await cloud.continueHeld(taf: "taf 1", hold: "exc/9")
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["POST /v1/tafs/taf%201/holds/exc%2F9/continue"])
        try expectEqual(transport.sent[0].headers["Authorization"], "Bearer tok")
    }),
    Test("a run that had already ended says so in tafs cloud's words, never silence", awaiting: {
        let ended = #"{"error":"no run of this taf waits on that held call","code":"run_ended","words":"You approved it after the run had ended, so nothing ran."}"#
        let cloud = CloudClient(transport: CannedTransport([(404, ended)]), session: session)
        do {
            try await cloud.continueHeld(taf: "taf_1", hold: "exc_1")
            throw Failure(description: "a 404 was taken")
        } catch let refusal as CloudRefusal {
            try expectEqual(refusal.code, "run_ended")
            try expectEqual(HeldContinue.said(words, summary: "Refund order 4417", error: refusal), "You approved it after the run had ended, so nothing ran.")
        }
    }),
    Test("a run KIFF's alert already continued says nothing, and taken says nothing") {
        try expectEqual(HeldContinue.said(words, summary: "Refund", error: nil), nil)
        let wentOn = CloudRefusal(status: 409, body: Data(#"{"error":"the run has ended: send it as a new message"}"#.utf8))
        try expectEqual(HeldContinue.said(words, summary: "Refund", error: wentOn), nil)
    },
    Test("any other refusal, or tafs cloud not reached, says what didn't go through and why") {
        let refused = CloudRefusal(status: 500, body: Data(#"{"error":"the agents service didn't answer"}"#.utf8))
        try expectEqual(HeldContinue.said(words, summary: "Refund", error: refused), "Refund didn't go through. the agents service didn't answer")
        try expectEqual(HeldContinue.said(words, summary: "Refund", error: URLError(.notConnectedToInternet)),
                        "Refund didn't go through. It didn't reach the server. Try again once you're online.")
    },
]

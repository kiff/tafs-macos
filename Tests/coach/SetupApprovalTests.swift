import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev1")

/// An approval card's Card step on this Mac (`SetupApproval`), as the iPad's `approve(_:shown:shownDraft:)` for `cards`:
/// only that step is ever signed here, and only with the message this Mac builds itself.
let coachSetupApprovalTests: [Test] = [
    Test("the Card step is signed only for the draft and version drawn, with exactly the message this Mac builds") {
        let ask = SetupApproval.Decision.Ask(id: "a1", step: "cards", message: "tafs.cards.v1|t1|d1|v7", reason: "Approve the Card",
                                             kiff: .init(draft: "d1", version: "v7"))
        try expect(SetupApproval.signsHere(ask, draft: "d1", shownDraft: "v7", tenant: "t1"), "the card's own Card step")
        try expect(!SetupApproval.signsHere(ask, draft: "d1", shownDraft: "v8", tenant: "t1"), "another version than drawn")
        try expect(!SetupApproval.signsHere(ask, draft: "d2", shownDraft: "v7", tenant: "t1"), "another draft")
        try expect(!SetupApproval.signsHere(ask, draft: "d1", shownDraft: "v7", tenant: "t2"), "another account")
        var other = ask; other = .init(id: "a1", step: "cards", message: "tafs.cards.v1|t1|d1|v7|x", reason: "", kiff: ask.kiff)
        try expect(!SetupApproval.signsHere(other, draft: "d1", shownDraft: "v7", tenant: "t1"), "a message that isn't this Mac's")
        let connect = SetupApproval.Decision.Ask(id: "a2", step: "connect", message: "tafs.connect.v1|t1|g1|dig", reason: "", kiff: nil)
        try expect(!SetupApproval.signsHere(connect, draft: "d1", shownDraft: "v7", tenant: "t1"), "never the connection's step")
    },
    Test("Approve is offered only once the connection is made and the Card comes next, drawn from a draft at a version") {
        try expect(SetupApproval.offered(connected: true, cardNext: true, draft: "d1", shownDraft: "v7"), "the Card step")
        try expect(!SetupApproval.offered(connected: false, cardNext: true, draft: "d1", shownDraft: "v7"), "the connection first, on the phone")
        try expect(!SetupApproval.offered(connected: true, cardNext: false, draft: "d1", shownDraft: "v7"), "a Card signed with the connection")
        try expect(!SetupApproval.offered(connected: true, cardNext: true, draft: nil, shownDraft: nil), "no Card drawn")
    },
    Test("the ask and the report go to tafs cloud's approval routes, the report signed over the exact bytes sent", awaiting: {
        let decision = #"{"outcome":"sign","ask":{"id":"a1","step":"cards","message":"tafs.cards.v1|t1|d1|v7","reason":"Approve","kiff":{"draft":"d1","version":"v7"}},"session":"s1"}"#
        let done = #"{"outcome":"answered","note":"Approved."}"#
        let transport = CannedTransport([(200, decision), (200, done)])
        let cloud = CloudClient(transport: transport, session: session)
        let asked = try await cloud.approval(taf: "setup/1", component: "c1", body: .init(grant: "g1", draft: "d1", shownDraft: "v7", session: "s1"),
                                             proof: "t=1,v1=p,d=dev1")
        try expectEqual(asked.outcome, "sign")
        try expectEqual(asked.ask?.kiff, .init(draft: "d1", version: "v7"))
        var signed: HTTPRequest?
        let reported = try await cloud.approvalReport(taf: "setup/1", component: "c1", ask: "a1", body: .init(result: "confirmed", session: "s1"),
                                                      proof: "t=2,v1=q,d=dev1", sign: { signed = $0; return "t=3,v1=sig" })
        try expectEqual(reported.note, "Approved.")
        let sent = transport.sent
        try expectEqual(sent.map(\.path), ["/v1/tafs/setup%2F1/components/c1/approval", "/v1/tafs/setup%2F1/components/c1/approval/a1"])
        try expectEqual(sent[0].headers["Planque-Device-Signature"], "t=1,v1=p,d=dev1")
        try expectEqual(sent[1].headers["KIFF-Device-Signature"], "t=3,v1=sig")
        try expectEqual(sent[1].headers["Planque-Device-Signature"], "t=2,v1=q,d=dev1")
        try expectEqual(signed?.body, sent[1].body)
        try expectEqual(String(decoding: sent[1].body, as: UTF8.self), #"{"result":"confirmed","session":"s1"}"#)
    }),
]

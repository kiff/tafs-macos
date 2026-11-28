import Foundation

private let words = #"{"line":"Rae's reply to Ben waits for you","send":"Send","discard":"Don't send","prompt":"Send this reply to Ben","changed":"The reply changed, so nothing was sent."}"#
private let hash = String(repeating: "a", count: 64)

let tafHeldReplyTests: [Test] = [
    Test("the doors read lists each held reply with its exact text, hash and tafs cloud's words; one that doesn't read is left out, never the rest") {
        let body = """
        {"doors":[],"apps":[],"knocks":[],"replies":[
          {"run":"run_1","door":"d1","to":"Ben","subject":"Refund","text":"Hello Ben,\\nyour refund is on its way.","text_sha256":"\(hash)","words":\(words),"at":"2026-11-28T06:00:00Z"},
          {"run":"run_2","door":"d1","to":"Ana","text":"no words here","text_sha256":"\(hash)"},
          {"run":"run_3","door":"d1","to":"Cy","text":"bad hash","text_sha256":"zz","words":\(words)}
        ]}
        """
        let page = try AccountClient.decoder.decode(TafDoors.Page.self, from: Data(body.utf8))
        try expectEqual(page.replies.map(\.run), ["run_1"])
        try expectEqual(page.replies[0].text, "Hello Ben,\nyour refund is on its way.")
        try expectEqual(page.replies[0].words.prompt, "Send this reply to Ben")
        let older = try AccountClient.decoder.decode(TafDoors.Page.self, from: Data(#"{"doors":[],"apps":[],"knocks":[]}"#.utf8))
        try expect(older.replies.isEmpty, "a tafs cloud before them: none")
    },
    Test("Home's door lights give each taf's held replies and the newest one's line, for Needs you") {
        let lights = try AccountClient.decoder.decode([TafDoors.Light].self, from: Data(#"[{"app":"email","open":true,"knocks":0,"replies":2,"reply_line":"Rae's reply to Ben waits for you"},{"app":"slack","open":true,"knocks":1}]"#.utf8))
        let held = TafDoors.heldReplies(lights)
        try expectEqual(held.count, 2)
        try expectEqual(held.line, "Rae's reply to Ben waits for you")
        try expectEqual(TafDoors.heldReplies(nil).count, 0)
    },
    Test("Send is one act on the security key: POST to the reply, with exactly {action, text_sha256} in sorted keys, named by tafs cloud's prompt") {
        let act = KeyAct.sendHeldReply(taf: "taf/1", run: "run 1", textSHA256: hash)
        try expectEqual(act.method, "POST")
        try expectEqual(act.path, "/v1/tafs/taf%2F1/doors/replies/run%201")
        try expectEqual(String(decoding: act.body, as: UTF8.self), #"{"action":"send","text_sha256":"\#(hash)"}"#)
        try expectEqual(act.title(try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings")), device: "Send this reply to Ben"), "Send this reply to Ben")
    },
    Test("Don't send signs nothing: a plain POST with action discard", awaiting: {
        let transport = CannedTransport([(200, #"{"run":"run_1","state":"not_sent"}"#)])
        let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")
        let cloud = CloudClient(transport: transport, session: session)
        try await cloud.discardHeldReply("taf_1", run: "run_1")
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "POST /v1/tafs/taf_1/doors/replies/run_1")
        try expectEqual(String(decoding: transport.sent[0].body ?? Data(), as: UTF8.self), #"{"action":"discard"}"#)
        try expect(transport.sent[0].headers[Passkeys.headerName] == nil, "no assertion: nothing is approved")
    }),
]

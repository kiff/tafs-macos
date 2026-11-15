import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
let sentAnswer = #"{"session":"s1","new_session":false,"run":"r9","message":{"id":"m9","at":"2026-11-14T18:05:00Z"}}"#
let consentRefusal = #"{"error":"Allow AI use first: Coach and your tafs need it to answer.","code":"ai_consent_required","consent":{"given":false,"version":"3","words":{"title":"Your data and the AI","lines":["tafs uses an AI for Coach and your tafs."],"allow":"Allow","not_now":"Not now","withdraw":"Withdraw","given":"AI use: allowed"}}}"#

private func cloud(_ answers: [(Int, String)]) -> (CloudClient, CannedTransport) {
    let transport = CannedTransport(answers)
    return (CloudClient(transport: transport, session: session, language: "fr"), transport)
}

let coachSendTests: [Test] = [
    Test("a message is 1 to 2,000 characters once trimmed, and nothing else is one") {
        try expectEqual(Outgoing.text("  Connect Qonto \n"), "Connect Qonto")
        try expectEqual(Outgoing.text(""), nil)
        try expectEqual(Outgoing.text(" \n\t "), nil)
        try expectEqual(Outgoing.text(String(repeating: "a", count: 2000))?.count, 2000)
        try expectEqual(Outgoing.text(String(repeating: "a", count: 2001)), nil)
    },
    Test("sending posts the person's exact words to that taf's chat, with the session and the language", awaiting: {
        let (client, transport) = cloud([(200, sentAnswer)])
        let sent = try await client.send("  Connect \"Qonto\" & co  ", to: "taf-coach")
        try expectEqual(sent.message?.id, "m9")
        try expectEqual(sent.session, "s1")
        let request = transport.sent[0]
        try expectEqual(request.method + " " + request.path, "POST /v1/tafs/taf-coach/messages")
        try expectEqual(request.headers["Authorization"], "Bearer tok")
        try expectEqual(request.headers["Accept-Language"], "fr")
        try expectEqual(try JSONDecoder().decode([String: String].self, from: request.body), ["text": "Connect \"Qonto\" & co"])
    }),
    Test("what isn't a message is never sent", awaiting: {
        let (client, transport) = cloud([(200, sentAnswer)])
        for text in ["", "   ", String(repeating: "x", count: 2001)] {
            do { _ = try await client.send(text, to: "taf-coach"); throw Failure(description: "sent") } catch let refusal as CloudRefusal {
                try expectEqual(refusal.code, "not_a_message")
            }
        }
        try expectEqual(transport.sent.count, 0)
    }),
    Test("a refusal keeps tafs cloud's own words, and says when AI use must be allowed first", awaiting: {
        let cases: [(Int, String)] = [(403, consentRefusal), (429, #"{"error":"too_many"}"#), (409, #"{"error":"halted","words":"Halted: nothing runs until it's resumed."}"#), (502, "<html>")]
        var got: [CloudRefusal] = []
        for answer in cases {
            do { _ = try await cloud([answer]).0.send("hello", to: "t"); throw Failure(description: "sent") } catch let refusal as CloudRefusal { got.append(refusal) }
        }
        try expectEqual(got[0].needsConsent, true)
        try expectEqual(got[0].consent?.version, "3")
        try expectEqual(got[1].tooMany, true)
        try expectEqual(got[1].needsConsent, false)
        try expectEqual(got[2].words, "Halted: nothing runs until it's resumed.")
        try expectEqual(got[3].words, nil)
        try expectEqual(got[3].status, 502)
    }),
    Test("a refusal's why is tafs cloud's words, else its error, else the status, never its code, as the iPad's CloudError", {
        let say = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        let why = { (status: Int, body: String) in CloudRefusal(status: status, body: Data(body.utf8)).why(say) }
        try expectEqual(why(409, #"{"error":"halted","code":"held_full","words":"Halted: nothing runs until it's resumed."}"#), "Halted: nothing runs until it's resumed.")
        try expectEqual(why(409, #"{"error":"halted","code":"held_full"}"#), "halted")
        try expectEqual(why(409, #"{"code":"held_full"}"#), "tafs cloud answered 409")
        try expectEqual(why(502, "<html>"), "tafs cloud answered 502")
    }),
    Test("a message names its chat as the iPad's ChatTarget: the live one says nothing, a new one or a chat says so", awaiting: {
        let (client, transport) = cloud([(200, sentAnswer), (200, sentAnswer), (200, sentAnswer)])
        var handedOver = ChatTarget.new
        handedOver.newChatAfterHandover = true
        _ = try await client.send("hello", to: "taf-coach")
        _ = try await client.send("hello", to: "taf-coach", target: handedOver)
        _ = try await client.send("hello", to: "taf-coach", target: ChatTarget(session: "s2"))
        let bodies = try transport.sent.map { try JSONSerialization.jsonObject(with: $0.body) as? NSDictionary }
        try expectEqual(bodies, [["text": "hello"], ["text": "hello", "new_chat": true, "new_chat_after_handover": true], ["text": "hello", "session": "s2"]])
        let request = client.streamRequest("hello", to: "taf-coach", target: ChatTarget(session: "s2"))
        try expectEqual(request.flatMap { try? JSONSerialization.jsonObject(with: $0.body) as? NSDictionary }, ["text": "hello", "session": "s2"])
    }),
    Test("a taf's chats are read by its id, each one strictly; a chat's thread by its session", awaiting: {
        let chats = #"{"chats":[{"session":"s1","started":"2026-11-14T18:00:00Z","updated":"2026-11-14T19:00:00Z","title":"Refunds"}]}"#
        let (client, transport) = cloud([(200, chats), (200, #"{"chats":[{"session":"s1","title":"No times"}]}"#), (200, #"{"items":[]}"#)])
        let read = try await client.chats(of: "taf-coach")
        try expectEqual(read.map(\.session), ["s1"])
        try expectEqual(read[0].title, "Refunds")
        let timeless = try? await client.chats(of: "taf-coach")
        try expect(timeless == nil, "a chat without its times doesn't read")
        _ = try await client.thread(of: "taf-coach", session: "s 1")
        try expectEqual(transport.sent.map(\.path), ["/v1/tafs/taf-coach/chats", "/v1/tafs/taf-coach/chats", "/v1/tafs/taf-coach/conversation/s%201"])
    }),
    Test("improving a taf posts the person's words to its improve route, and nothing that isn't a message", awaiting: {
        let (client, transport) = cloud([(200, sentAnswer)])
        let sent = try await client.improve("taf-1", text: " Why was it held? ")
        try expectEqual(sent.session, "s1")
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "POST /v1/tafs/taf%2D1/improve")
        try expectEqual(try JSONDecoder().decode([String: String].self, from: transport.sent[0].body), ["text": "Why was it held?"])
        let none = try? await client.improve("taf-1", text: "   ")
        try expect(none == nil, "a blank message isn't sent")
        try expectEqual(transport.sent.count, 1)
    }),
    Test("what tafs cloud answers a message says whether it started a new chat", {
        let sent = try JSONDecoder().decode(Outgoing.Sent.self, from: Data(#"{"session":"s7","new_session":true,"message":{"id":"m9"}}"#.utf8))
        try expectEqual(sent.session, "s7")
        try expectEqual(sent.newSession, true)
        try expect((try? JSONDecoder().decode(Outgoing.Sent.self, from: Data(#"{"session":"s7"}"#.utf8))) == nil, "no new_session doesn't read")
    }),
    Test("allowing AI use sends the version of the words that were read", awaiting: {
        let (client, transport) = cloud([(200, "{}")])
        try await client.allowAI(version: "3")
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "POST /v1/me/ai-consent")
        try expectEqual(try JSONDecoder().decode([String: String].self, from: transport.sent[0].body), ["version": "3"])
    }),
]

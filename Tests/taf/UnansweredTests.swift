import Foundation

private let words = #"{"line":"Rae can't do what Ben asked: the app it needs isn't connected.","connect":"Connect an app","reply":"Answer them yourself","ignore":"Ignore","prompt":"Send this reply to Ben","changed":"The reply changed since you read it."}"#
private let otherWords = #"{"line":"Rae can't do what Ana asked.","reply":"Answer them yourself","ignore":"Ignore","prompt":"Send this reply to Ana","changed":"The reply changed since you read it."}"#

let tafUnansweredTests: [Test] = [
    Test("the doors read lists the writers the taf couldn't help, apart from the replies, each with tafs cloud's words; one that doesn't read is left out, never the rest") {
        let body = """
        {"doors":[],"apps":[],"knocks":[],"replies":[],"unanswered":[
          {"run":"run_1","door":"d1","to":"Ben","subject":"Refund","at":"2026-11-28T08:00:00Z","cant_do":"no_app","words":\(words)},
          {"run":"run_2","door":"d1","to":"Ana","at":"2026-11-28T08:01:00Z","cant_do":"other","words":\(otherWords)},
          {"run":"run_3","door":"d1","to":"Cy","at":"2026-11-28T08:02:00Z","cant_do":"unfinished"},
          {"run":"","door":"d1","to":"Di","cant_do":"other","words":\(otherWords)}
        ]}
        """
        let page = try AccountClient.decoder.decode(TafDoors.Page.self, from: Data(body.utf8))
        try expectEqual(page.unanswered.map(\.run), ["run_1", "run_2"])
        try expectEqual(page.unanswered[0].cantDo, "no_app")
        try expectEqual(page.unanswered[0].words.connect, "Connect an app")
        try expect(page.unanswered[1].words.connect == nil, "Connect an app comes only for no_app")
        try expect(page.replies.isEmpty, "never counted as a reply")
        let older = try AccountClient.decoder.decode(TafDoors.Page.self, from: Data(#"{"doors":[],"apps":[],"knocks":[],"replies":[]}"#.utf8))
        try expect(older.unanswered.isEmpty, "a tafs cloud before them: none")
    },
    Test("an own answer is sendable only with words in it; its length is tafs cloud's to judge") {
        try expect(!TafDoors.Unanswered.sendable(""), "empty")
        try expect(!TafDoors.Unanswered.sendable("  \n "), "only spaces")
        try expect(TafDoors.Unanswered.sendable("Hi Ben, I'll look at it today."), "words")
        try expect(TafDoors.Unanswered.sendable(String(repeating: "a", count: 5000)), "a long one goes, and tafs cloud says if it's too long")
    },
    Test("Answer them yourself is one act on the security key: POST to the run, with exactly {action, text, text_sha256} in sorted keys, the text as typed") {
        let text = "Hi Ben,\nI'll send it by 5/12."
        let hash = String(repeating: "b", count: 64)
        let act = KeyAct.sendOwnReply(taf: "taf/1", run: "run 1", text: text, textSHA256: hash)
        try expectEqual(act.method, "POST")
        try expectEqual(act.path, "/v1/tafs/taf%2F1/doors/replies/run%201")
        try expectEqual(String(decoding: act.body, as: UTF8.self), #"{"action":"send","text":"Hi Ben,\nI'll send it by 5/12.","text_sha256":"\#(hash)"}"#)
        // What's signed carries the text exactly: decoded, it's the same string.
        let sent = try JSONSerialization.jsonObject(with: act.body) as? [String: String]
        try expectEqual(sent?["text"], text)
        try expectEqual(act.title(try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings")), device: "Send this reply to Ben"), "Send this reply to Ben")
    },
]

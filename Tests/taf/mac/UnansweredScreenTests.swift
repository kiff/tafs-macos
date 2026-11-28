import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let refunds = #"{"kiff_agent":"agent_refunds","id":"taf-1","name":"Refunds","color":1,"state":"working"}"#
private let page = #"""
{"doors":[],"apps":[],"knocks":[],"replies":[],"unanswered":[
  {"run":"run_1","door":"d1","to":"Ben","subject":"Refund for order 1042","at":"2026-11-28T08:00:00Z","cant_do":"no_app",
   "words":{"line":"Refunds can't do what Ben asked: the app it needs isn't connected.","connect":"Connect an app","reply":"Answer them yourself","ignore":"Ignore","prompt":"Send this reply to Ben","changed":"The reply changed since you read it."}},
  {"run":"run_2","door":"d1","to":"Ana","at":"2026-11-28T08:01:00Z","cant_do":"unfinished",
   "words":{"line":"Refunds couldn't finish what Ana asked.","reply":"Answer them yourself","ignore":"Ignore","prompt":"Send this reply to Ana","changed":"The reply changed since you read it."}}
]}
"""#

@MainActor
private func doors(_ answers: [(Int, String)]) -> (DoorsModel, CannedTransport) {
    let transport = CannedTransport(answers)
    let model = DoorsModel(cloud: CloudClient(transport: transport, session: session), taf: "taf-1")
    model.retryDelays = [0, 0]
    return (model, transport)
}

let tafUnansweredMacTests: [Test] = [
    Test("Answer them yourself signs the text as typed, behind tafs cloud's prompt, and sends exactly it; the writer leaves the list", awaiting: { @MainActor in
        let (model, transport) = doors([(200, page), (200, #"{"run":"run_1","state":"sent"}"#)])
        await model.load()
        try expectEqual(model.unanswered.map(\.run), ["run_1", "run_2"])
        var asked: (KeyAct, String)?
        model.signWithKey = { act, title in asked = (act, title); return "ASSERTION" }
        let text = "Hi Ben, I'll do the refund myself today."
        let sent = await model.sendOwn(model.unanswered[0], text: text)
        try expect(sent, "sent")
        try expectEqual(asked?.1, "Send this reply to Ben")
        let request = transport.sent[1]
        try expectEqual(request.method + " " + request.path, "POST /v1/tafs/taf-1/doors/replies/run_1")
        try expectEqual(request.headers[Passkeys.headerName], "ASSERTION")
        let body = try JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: String]
        try expectEqual(body?["text"], text)
        try expectEqual(body?["text_sha256"], DoorsModel.textSHA256(text))
        try expectEqual(model.unanswered.map(\.run), ["run_2"])
    }),
    Test("nothing is asked or sent for an empty answer; a 409 says tafs cloud's words and reads the list again", awaiting: { @MainActor in
        let (model, transport) = doors([(200, page), (409, #"{"error":"The reply changed since you read it.","code":"reply_changed"}"#), (200, page)])
        await model.load()
        var asks = 0
        model.signWithKey = { _, _ in asks += 1; return "ASSERTION" }
        let empty = await model.sendOwn(model.unanswered[0], text: "   ")
        try expect(!empty && asks == 0 && transport.sent.count == 1, "nothing asked or sent")
        let refused = await model.sendOwn(model.unanswered[0], text: "Hi Ben")
        try expect(!refused, "not sent")
        // Read again, and tafs cloud's words still say why: the read that works doesn't clear them.
        try expectEqual(model.error, "The reply changed since you read it.")
        try expectEqual(transport.sent.count, 3)
        try expectEqual(model.unanswered.count, 2)
    }),
    Test("a held reply whose Send is refused as changed keeps saying so after the list is read again", awaiting: { @MainActor in
        let held = #"{"doors":[],"apps":[],"knocks":[],"replies":[{"run":"run_9","door":"d1","to":"Ben","text":"Hello","text_sha256":"\#(DoorsModel.textSHA256("Hello"))","words":{"line":"A reply waits","send":"Send","discard":"Don't send","prompt":"Send this reply to Ben","changed":"The reply changed, so nothing was sent."}}]}"#
        let (model, _) = doors([(200, held), (409, #"{"error":"The reply changed, so nothing was sent.","code":"reply_changed"}"#), (200, held)])
        await model.load()
        model.signWithKey = { _, _ in "ASSERTION" }
        await model.send(model.replies[0])
        try expectEqual(model.error, "The reply changed, so nothing was sent.")
    }),
    Test("an answer tafs cloud refuses as too long says tafs cloud's words, and the writer stays", awaiting: { @MainActor in
        let (model, _) = doors([(200, page), (400, #"{"error":"Your answer is too long: at most 4,000 characters."}"#)])
        await model.load()
        model.signWithKey = { _, _ in "ASSERTION" }
        let sent = await model.sendOwn(model.unanswered[0], text: String(repeating: "a", count: 5000))
        try expect(!sent, "not sent")
        try expect(model.error?.contains("too long") == true, "tafs cloud's words: \(model.error ?? "nil")")
        try expectEqual(model.unanswered.count, 2)
    }),
    Test("Ignore signs nothing: a plain POST with action discard, and the writer leaves the list", awaiting: { @MainActor in
        let (model, transport) = doors([(200, page), (200, #"{"run":"run_2","state":"not_sent"}"#)])
        await model.load()
        await model.ignore(model.unanswered[1])
        try expectEqual(String(decoding: transport.sent[1].body ?? Data(), as: UTF8.self), #"{"action":"discard"}"#)
        try expect(transport.sent[1].headers[Passkeys.headerName] == nil, "no assertion")
        try expectEqual(model.unanswered.map(\.run), ["run_1"])
    }),
    Test("the screenshot: two writers the taf couldn't help, one with Connect an app, light and dark", awaiting: { @MainActor in
        let (model, _) = doors([(200, page)])
        await model.load()
        let taf = try AccountClient.decoder.decode(Home.Taf.self, from: Data(refunds.utf8))
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: "build/screenshots"), withIntermediateDirectories: true)
        for dark in [false, true] {
            let view = TafKnocksPanel(taf: taf, doors: model, offered: false, openConnect: {})
                .padding(20).frame(width: 520, alignment: .topLeading).background(Theme.background)
                .environment(\.words, Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 520, height: 560), dark: dark), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: URL(fileURLWithPath: "build/screenshots/door-unanswered-en\(dark ? "-dark" : "").png"))
        }
    }),
]

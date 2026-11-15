import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let refunds = #"{"kiff_agent":"agent_refunds","id":"taf-1","name":"Refunds","color":1,"state":"working"}"#

@MainActor
private func doors(_ answers: [(Int, String)]) -> (DoorsModel, CannedTransport) {
    let transport = CannedTransport(answers)
    let model = DoorsModel(cloud: CloudClient(transport: transport, session: session), taf: "taf-1")
    model.retryDelays = [0, 0]
    return (model, transport)
}

let tafDoorsMacTests: [Test] = [
    Test("the doors are read again quietly when a read fails; only one that keeps failing says so", awaiting: { @MainActor in
        let (flaky, transport) = doors([(503, ""), (200, doorPage)])
        await flaky.load()
        try expectEqual(transport.sent.count, 2)
        try expectEqual(flaky.loaded, true)
        try expectEqual(flaky.error, nil)
        try expectEqual(flaky.openKnocks.map(\.id), ["k1"])
        // One door of each app: email is taken, so WhatsApp and SMS can still be added.
        try expectEqual(flaky.addable.map(\.id), ["whatsapp", "sms"])
        let (down, _) = doors([(503, ""), (503, ""), (503, "")])
        await down.load()
        try expectEqual(down.loaded, false)
        try expectEqual(down.error, "The doors couldn't be read just now. They're tried again when you come back here.")
    }),
    Test("a knock's answer: Pair reads the doors again, Ignore takes it away, too many says so in the app's words", awaiting: { @MainActor in
        let (model, transport) = doors([(200, doorPage), (200, #"{"state":"paired"}"#), (200, doorPage), (200, #"{"state":"done"}"#), (429, #"{"error":"rate_limited"}"#)])
        await model.load()
        let knock = model.openKnocks[0]
        await model.answer(knock, "pair")
        try expectEqual(transport.sent.map(\.method), ["GET", "POST", "GET"])
        await model.answer(knock, "ignore")
        try expectEqual(model.knocks.map(\.id), ["k2"])
        await model.answer(knock, "ignore")
        try expectEqual(model.error, "That's a lot of messages in a few minutes. Wait a little, then send it again: nothing was sent.")
    }),
    Test("a Slack door with its channel's subscription isn't removed from this Mac, which has no planque connection to stop it", awaiting: { @MainActor in
        let slack = ##"{"doors":[{"id":"s1","app":"slack","kind":"slack","label":"Slack","open":true,"address":"#support","proof":"proven","how":"h","keys":[],"today":0,"limit":20,"resting":false,"grant":"g1","channel":"C1","trigger":"t1"}],"apps":[],"knocks":[]}"##
        let (model, transport) = doors([(200, slack)])
        await model.load()
        await model.remove(model.doors[0])
        try expectEqual(transport.sent.count, 1)
        try expectEqual(model.doors.count, 1)
        try expectEqual(model.error, "Start from Connected apps on this Mac first. Slack's subscription must be stopped before removing its door.")
    }),
    Test("the screenshot: a door's own screen, with who may give it work and a knock waiting", awaiting: { @MainActor in
        let (model, _) = doors([(200, doorPage), (200, doorPage)])
        await model.load()
        let taf = try AccountClient.decoder.decode(Home.Taf.self, from: Data(refunds.utf8))
        let view = DoorScreen(taf: taf, doors: model, doorID: "d1", myEmail: "you@acme.example", close: {})
            .environment(\.words, Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"]))
        guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 480, height: 620)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: "build/screenshots"), withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: "build/screenshots/doors-en.png"))
    }),
]

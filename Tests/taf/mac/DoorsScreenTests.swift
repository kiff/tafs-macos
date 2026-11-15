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
    Test("a taf's knocks show on Needs you whether KIFF's held list was read or not, as the iPad's", awaiting: { @MainActor in
        let page = try AccountClient.decoder.decode(Home.Page.self, from: Data(#"{"tafs":[{"kiff_agent":"agent_refunds","id":"taf-1","name":"Refunds","color":1,"state":"working","doors":[{"app":"email","open":true,"knocks":2}]}]}"#.utf8))
        let transport = CannedTransport([(503, ""), (503, ""), (503, "")])
        let needsYou = NeedsYouModel(account: AccountClient(transport: transport, session: session), route: .phoneOrPasskey)
        await needsYou.load()
        guard case .unread = needsYou.state else { throw Failure(description: "the held list read") }
        let view = NeedsYouView(model: needsYou, tafs: page.tafs, now: Date(timeIntervalSince1970: 1_794_679_800))
            .environment(\.words, Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"]))
        // The knocked row's avatar, in the taf's colour, is drawn under the unread line. One host
        // is drawn again until it shows, the run loop turned between: a runner can lay out the
        // scrolled content a turn later than a Mac at a desk.
        let wanted = Palette.tafColor(1)
        func shows(_ bitmap: NSBitmapImageRep) -> Bool {
            for y in stride(from: 0, to: 900, by: 2) {
                for x in stride(from: 0, to: 980, by: 2) {
                    // As stored or as sRGB: a runner's virtual screen keeps the drawn numbers.
                    for got in Snapshot.hexes(bitmap, x: x, y: y)
                    where [16, 8, 0].allSatisfy({ abs(Int((got >> $0) & 0xFF) - Int((wanted >> $0) & 0xFF)) <= 6 }) { return true }
                }
            }
            return false
        }
        let drawn = Snapshot.settled(of: view, size: CGSize(width: 980, height: 900), until: shows)
        // What was drawn, for the run's screenshots either way.
        if let drawn, let png = Snapshot.png(drawn) {
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: "build/screenshots"), withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: "build/screenshots/needs-you-knocks-en.png"))
        }
        // When it isn't seen, what was read at the avatar, and the bitmap's own shape, say why.
        let read = drawn.map { bitmap in
            [(48, 140), (60, 146), (52, 156)].map { Snapshot.hexes(bitmap, x: $0.0, y: $0.1).map { String(format: "%06X", $0) }.joined(separator: "/") }.joined(separator: " ")
                + " | \(bitmap.pixelsWide)x\(bitmap.pixelsHigh) of \(Int(bitmap.size.width))x\(Int(bitmap.size.height)), \(bitmap.bitsPerSample) bits, "
                + "format \(bitmap.bitmapFormat.rawValue), \(bitmap.colorSpace.localizedName ?? "?")"
        } ?? "nothing drawn"
        try expect(drawn.map(shows) == true, "the knocked taf's row is drawn (read \(read), wanted \(String(format: "%06X", wanted)))")
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

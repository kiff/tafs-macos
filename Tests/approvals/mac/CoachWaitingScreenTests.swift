import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")
private let noCalls = #"{"exceptions":[]}"#

@MainActor
private func model(_ answers: [(Int, String)], proof: String? = "t=1,v1=SIG,d=dev_1") -> (NeedsYouModel, CannedTransport) {
    let transport = CannedTransport(answers)
    let account = AccountClient(transport: transport, session: session, signMessage: { _ in "SIG" })
    let cloud = CloudClient(transport: transport, session: session)
    return (NeedsYouModel(account: account, route: .phoneOrPasskey, confirm: { _ in }, cloud: cloud, proof: { proof }), transport)
}

private func page() throws -> Home.Page { try AccountClient.decoder.decode(Home.Page.self, from: Data(coachWaitingHome.utf8)) }

let approvalsCoachWaitingMacTests: [Test] = [
    Test("Needs you shows Home's waiting chats and counts them as the iPad's: tafs cloud's count, else its own with Coach's chats", awaiting: { @MainActor in
        let (model, _) = model([(200, noCalls)])
        await model.load()
        model.show(try page())
        try expectEqual(model.coachWaiting().map(\.session), ["chat/1", "chat-2"])
        try expectEqual(model.setAllAside()?.words.title, "End 2 waiting Coach chats?")
        try expectEqual(model.needsYouCount(), 3)
        // The chat open in Coach is left out of the rows and the count, and Set all aside goes with one row.
        try expectEqual(model.needsYouCount(onScreen: "chat/1"), 2)
        try expectEqual(model.setAllAside(onScreen: "chat/1"), nil)
        // A tafs cloud that sends no count: held calls, Card units, steps, "Did this happen?" and Coach's chats.
        let own = coachWaitingHome.replacingOccurrences(of: #""needs_you":{"count":3,"words":"3 need you."},"#, with: "")
        model.show(try AccountClient.decoder.decode(Home.Page.self, from: Data(own.utf8)))
        try expectEqual(model.needsYouCount(), 3)
        try expectEqual(NeedsYouCount.words(model.countParts(), Words.app), "3 need you.")
    }),
    Test("Set aside is tafs cloud's, sent once, with this device's read of its connections; the row goes once it's taken", awaiting: { @MainActor in
        let (model, transport) = model([(200, noCalls), (200, #"{"set_aside":["chat/1"],"withdrawn":0}"#)])
        await model.load()
        model.show(try page())
        var ended: Set<String> = []
        await model.setAside("chat/1") { ended = $0 }
        try expectEqual(ended, ["chat/1"])
        try expectEqual(model.coachWaiting().map(\.session), ["chat-2"])
        try expectEqual(model.settingAside, [])
        let posts = transport.sent.filter { $0.method == "POST" }
        try expectEqual(posts.map(\.path), ["/v1/home/coach-waiting/chat%2F1/set-aside"])
        try expectEqual(posts[0].headers["Planque-Device-Signature"], "t=1,v1=SIG,d=dev_1")
        // KIFF's signature never goes with it: nothing is approved.
        try expectEqual(posts[0].headers["KIFF-Device-Signature"], nil)
    }),
    Test("Set all aside ends every chat Home listed in one call; a refusal keeps the rows and says tafs cloud's words", awaiting: { @MainActor in
        let (model, transport) = model([(200, noCalls), (409, #"{"error":"busy","words":"Try again in a moment."}"#), (200, #"{"set_aside":["chat/1","chat-2"]}"#)])
        await model.load()
        model.show(try page())
        await model.setAside(nil)
        try expectEqual(model.setAsideNotDone, "Try again in a moment.")
        try expectEqual(model.coachWaiting().count, 2)
        await model.setAside(nil)
        try expectEqual(model.setAsideNotDone, nil)
        try expectEqual(model.coachWaiting(), [])
        try expectEqual(transport.sent.filter { $0.method == "POST" }.map(\.path), ["/v1/home/coach-waiting/set-aside", "/v1/home/coach-waiting/set-aside"])
    }),
    Test("the screenshots: Needs you with Coach's waiting chats, light and dark", awaiting: { @MainActor in
        let (model, _) = model([(200, noCalls)])
        await model.load()
        model.show(try page())
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for dark in [false, true] {
            let view = NeedsYouView(model: model, now: Date(timeIntervalSince1970: 1_794_679_800), mayUseCoach: true)
                .environment(\.words, Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 700), dark: dark), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("needs-you-coach-waiting-en\(dark ? "-dark" : "").png"))
        }
    }),
]

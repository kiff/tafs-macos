import AppKit
import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let strings = URL(fileURLWithPath: ".shared/app/strings")

/// Coach with its tools still to give.
private let setupWithTools = #"{"setup":{"id":"taf-coach","name":"Coach"},"tools":{"state":"to_give","coach_tools_step":{"title":"Give Coach its tools","row":"Coach's tools are waiting for you · Give them","groups":[{"name":"Watch your tafs","line":"See your tafs and their runs.","tools":[{"name":"See your tafs","does":"Read each taf.","why":"It reads your account."}]}],"details":"Each tool and its limits","ask":"Give them now?"},"connect":{"body":{},"lines":["See your tafs"]},"card":{"body":{},"card_title":"Coach's Cards","cards":[{"title":"Watching","lines":["Up to 500 a day"]}]}}}"#

/// A chat that connected Stripe, then asked again for it with the taf's Card, and a hand-over.
private let shapeThread = #"""
{"working":false,"items":[
  {"type":"message","message":{"id":"m1","at":"2026-11-20T09:00:00Z","from":"owner","text":"Refund my Stripe customers","session":"s1"}},
  {"type":"card","card":{"key":"s1#a1","session":"s1","at":"2026-11-20T09:01:00Z","answer":{"state":"answered","words":"Approved","answer":"approved"},"component":{"id":"a1","type":"approval","title":"Connect Stripe","grant":"g_stripe","waits":"owner"}}},
  {"type":"card","card":{"key":"s1#a2","session":"s1","at":"2026-11-20T09:02:00Z","component":{"id":"a2","type":"approval","title":"Approve the refunds Card","text":"Refunds may refund up to €100 each.","grant":"g_stripe","draft":"drf_s1","signs":{"card":true},"waits":"owner"}}},
  {"type":"card","card":{"key":"s1#d","session":"s1","at":"2026-11-20T09:03:00Z","component":{"id":"d","type":"drive","text":"Open your refunds","waits":"owner"}}}
]}
"""#

private let stripeGrants = #"""
[{"id":"g_stripe","status":"connected","vendor":"Stripe","request":{"server":"mcp.stripe.com","agent":"a","tools":[{"tool":"create_refund","name":"stripe__create_refund","title":"Refund a payment"}]}}]
"""#

@MainActor
private func shaped() async throws -> (CoachModel, CannedTransport) {
    let transport = CannedTransport([(200, setupWithTools), (200, noChats), (200, shapeThread)])
    let grants = try AccountClient.decoder.decode([AppConnections.Grant].self, from: Data(stripeGrants.utf8))
    let draft = try AccountClient.decoder.decode(AccountClient.Draft.self, from: Data(approvalDraftAnswer.utf8))
    var asked: [String] = []
    let model = CoachModel(cloud: CloudClient(transport: transport, session: session), sleep: { _ in },
                           grants: { grants }, drafts: { id in asked.append(id); return draft })
    await model.load()
    await model.readNamed()
    try expectEqual(asked, ["drf_s1"])
    return (model, transport)
}

let coachShapeMacTests: [Test] = [
    Test("what Coach's cards name is read once Coach is: planque's grants and the drafts its approvals name, and nothing else is sent", awaiting: { @MainActor in
        let (model, transport) = try await shaped()
        try expectEqual(transport.sent.map(\.path), ["/v1/setup", "/v1/tafs/taf-coach/chats", "/v1/tafs/taf-coach/conversation"])
        try expectEqual(model.grants.map(\.id), ["g_stripe"])
        try expectEqual(model.readDrafts["drf_s1"]?.label, "Refunds assistant")
        try expectEqual(model.coachTools?.toGive, true)
        guard case .loaded(_, let page) = model.state else { throw Failure(description: "the thread wasn't read") }
        try expectEqual(page.cards.map { model.replaced($0) }, [true, false, false])
        let words = Words.load(folder: strings, preferred: ["en"])
        try expectEqual(model.shape(words)?.tools.map(\.actions), [["stripe__create_refund"]])
        model.signedOut()
        try expectEqual(model.grants, [])
        try expectEqual(model.drafts, [:])
        try expectEqual(model.coachTools, nil)
    }),
    Test("Coach's own chat reads nothing more without a proof or a source given; a taf's chat never does", awaiting: { @MainActor in
        let transport = CannedTransport([(200, setupWithTools), (200, noChats), (200, shapeThread)])
        let model = CoachModel(cloud: CloudClient(transport: transport, session: session), sleep: { _ in })
        await model.load()
        await model.readNamed()
        try expectEqual(transport.sent.count, 3)
        try expectEqual(model.readsPlanque, false)
        let taf = CoachModel(cloud: CloudClient(transport: CannedTransport([(200, shapeThread)]), session: session), taf: Coach(id: "taf-1", name: "Refunds"),
                             sleep: { _ in }, proof: { "t=1,v1=c2ln,d=dev_mac" })
        try expectEqual(taf.readsPlanque, false)
    }),
    Test("the screenshots: Taking shape beside a wide Coach, an approval replaced and its Card, and Coach's tools step", awaiting: { @MainActor in
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let (model, _) = try await shaped()
        let words = Words.load(folder: strings, preferred: ["en"])
        let wide = CoachView(model: model).environment(\.words, words)
        guard let shape = Snapshot.bitmap(of: wide, size: CGSize(width: 1280, height: 900)), let png = Snapshot.png(shape) else { throw Failure(description: "no PNG") }
        try png.write(to: folder.appendingPathComponent("coach-shape-en.png"))
        let narrow = CoachView(model: model).environment(\.words, words)
        guard let replaced = Snapshot.bitmap(of: narrow, size: CGSize(width: 560, height: 1000)), let shot = Snapshot.png(replaced) else { throw Failure(description: "no PNG") }
        try shot.write(to: folder.appendingPathComponent("coach-replaced-en.png"))
        guard let tools = model.coachTools else { throw Failure(description: "no tools read") }
        let sheet = CoachToolsSheet(tools: tools, close: {}).environment(\.words, words)
        guard let step = Snapshot.bitmap(of: sheet, size: CGSize(width: 520, height: 600)), let stepPNG = Snapshot.png(step) else { throw Failure(description: "no PNG") }
        try stepPNG.write(to: folder.appendingPathComponent("coach-tools-en.png"))
    }),
]

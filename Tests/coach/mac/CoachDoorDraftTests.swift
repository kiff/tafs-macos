import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let draftAnswer = #"{"draft_id":"dd-1","body":{"kind":"api","draft":{"name":"Shop site","fields":[{"name":"order","type":"string"},{"name":"reason","type":"choice","values":["refund","exchange"]}],"job":"answer a customer's refund request","outcomes":["done","needs_you"],"text":true}}}"#

let coachDoorDraftMacTests: [Test] = [
    Test("a drafted door is read once from tafs cloud for its card, and only read: nothing is signed or sent", awaiting: { @MainActor in
        let transport = CannedTransport([(200, draftAnswer)])
        let coach = CoachModel(cloud: CloudClient(transport: transport, session: session), sleep: { _ in })
        let draft = try await coach.doorDraft(taf: "taf-1", draft: "dd-1")
        try expectEqual(draft?.name, "Shop site")
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["GET /v1/tafs/taf-1/doors/drafts/dd-1"])
        try expectEqual(transport.sent[0].headers["KIFF-Device-Signature"], nil)
        // Drawn for whoever manages the taf: Approve is there, and gated.
        let view = DoorDraftCard(model: coach, taf: "taf-1", draft: "dd-1", tafName: "Refunds", manages: true)
            .frame(width: 560).padding(20).background(Theme.background)
            .environment(\.words, Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"]))
        guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 600, height: 560)), let png = Snapshot.png(bitmap) else {
            throw Failure(description: "no PNG")
        }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: "build/screenshots"), withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: "build/screenshots/coach-door-draft.png"))
    }),
    Test("a drafted door's Approve goes on the security key through the model, only for whoever manages the taf; without a key it's gated (sources)") {
        let source = try String(contentsOf: URL(fileURLWithPath: "Sources/App/coach/CoachView.swift"), encoding: .utf8)
        guard let start = source.range(of: "struct DoorDraftCard: View {") else { throw Failure(description: "no card") }
        let card = String(source[start.lowerBound...])
        // With a key on this Mac, for whoever manages the taf: the model's `approveDoorDraft` (`KeyAct.addDraftedAPIDoor`).
        try expect(card.contains("} else if manages, model.signWithKey != nil {"), "Approve on the key, for whoever manages the taf")
        try expect(card.contains("await model.approveDoorDraft(taf: taf, draft: d, tafName: tafName)"), "through the model's act")
        // Without one: the gated line, as before.
        try expect(card.contains("} else if manages {") && card.contains(#"GatedAction(title: words("approval.approve"), id: "door-draft|" + d.id"#),
                   "Approve gated without a key")
        // The card itself never posts or signs: the model's act does, on the key.
        for forbidden in ["approveWithKey", "post(", "send(\"POST", "signMessage", "signWithKey("] {
            try expect(!card.contains(forbidden), "no \(forbidden) in the card")
        }
        // The first key only in the sheet kept out of capture.
        try expect(card.contains("IssuedKeySheet(key: shown.added.key, door: shown.added.door)"), "the key, once, out of capture")
        try expect(source.contains("} else if let door = card.door {"), "Coach draws a door card")
        let window = try String(contentsOf: URL(fileURLWithPath: "Sources/App/shell/SignedInView.swift"), encoding: .utf8)
        try expect(window.contains("managesTaf: { id in overview.tafs.first { $0.tafID == id }.map { Access.manages(access[$0.id]) } ?? false }"),
                   "whoever manages the taf, as the iPad's manages(tafID)")
    },
]

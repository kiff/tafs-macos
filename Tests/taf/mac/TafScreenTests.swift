import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

private let tafThread = #"""
{"working":false,"items":[
  {"type":"message","message":{"id":"m1","at":"2026-11-15T00:30:00Z","from":"owner","text":"Which emails are still waiting on me?"}},
  {"type":"message","message":{"id":"m2","at":"2026-11-15T00:30:12Z","from":"taf","text":"**3 emails** are waiting for your answer:\n- Invoice 1042, from the accountant\n- The venue's quote\n- A question about Friday",
    "work":{"ms":12400,"steps":[{"tool":"mail.list","words":"Listing your inbox"}]}}}
]}
"""#

@MainActor
private func make(_ answers: [(Int, String)]) async throws -> (Home.Taf, CoachModel, CannedTransport) {
    let taf = try AccountClient.decoder.decode(Home.Page.self, from: Data(tafWithCards.utf8)).tafs[0]
    let transport = CannedTransport(answers)
    let chat = CoachModel(cloud: CloudClient(transport: transport, session: session),
                          taf: Coach(id: taf.tafID ?? "", name: taf.name), sleep: { _ in })
    await chat.load()
    return (taf, chat, transport)
}

let tafMacTests: [Test] = [
    Test("a taf's chat reads that taf's conversation, without asking which taf is Coach", awaiting: { @MainActor in
        let (_, chat, transport) = try await make([(200, tafThread)])
        try expectEqual(transport.sent.map(\.method), ["GET"])
        try expect(transport.sent[0].path.removingPercentEncoding == "/v1/tafs/taf-1/conversation", "read \(transport.sent[0].path)")
        guard case .loaded(let coach, _) = chat.state else { throw Failure(description: "not loaded") }
        try expectEqual(coach.id, "taf-1")
    }),
    Test("a Card with no rules has no empty panel under it on the Card tab", awaiting: { @MainActor in
        // Whether a panel's white shows anywhere down the page's middle, under the Card's face.
        func panelUnderCard(rules: String) throws -> Bool {
            let json = #"{"tafs":[{"id":"taf-2","name":"Refunds","kiff_agent":"a2","state":"idle","card":{"cards":[{"id":"c9","title":"Refunds","rules":\#(rules)}]}}]}"#
            let taf = try AccountClient.decoder.decode(Home.Page.self, from: Data(json.utf8)).tafs[0]
            let chat = CoachModel(cloud: CloudClient(transport: CannedTransport([]), session: session), taf: Coach(id: "taf-2", name: "Refunds"), sleep: { _ in })
            guard let bitmap = Snapshot.bitmap(of: TafView(taf: taf, chat: chat, tab: .card), size: CGSize(width: 980, height: 860)) else {
                throw Failure(description: "no bitmap")
            }
            return (330...760).contains { Snapshot.hex(bitmap, x: 490, y: $0) == Palette.panel.light }
        }
        let withRules = try panelUnderCard(rules: #"[{"label":"Refund a payment","outside":"hold"}]"#)
        let without = try panelUnderCard(rules: "[]")
        try expect(withRules, "a Card with rules has its panel")
        try expect(!without, "a Card with none has no panel")
    }),
    Test("the screenshots: a taf's Chat and Card tabs, in three languages", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr", "pt"] {
            for tab in TafView.Tab.allCases {
                let (taf, chat, _) = try await make([(200, tafThread)])
                let view = TafView(taf: taf, chat: chat, tab: tab).environment(\.words, Words.load(folder: strings, preferred: [language]))
                guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 860)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
                try png.write(to: folder.appendingPathComponent("taf-\(tab.rawValue)-\(language).png"))
            }
        }
    }),
]

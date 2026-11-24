import AppKit
import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

/// Coach asking to drive the phone, then what it did there, as tafs cloud sends both.
private let driveThread = #"""
{"working":false,"items":[
  {"type":"message","message":{"id":"m1","at":"2026-11-24T08:00:00Z","from":"owner","kind":"message","text":"Run my chargebacks taf for me","session":"s1"}},
  {"type":"card","card":{"key":"s1:d1","session":"s1","component":{"id":"d1","type":"drive","text":"Run Chargebacks","waits":"owner"}}},
  {"type":"card","card":{"key":"s1:d0","session":"s1","answer":{"state":"answered","answer":"approved: the drive is on"},"component":{"id":"d0","type":"drive","text":"Open Refunds","waits":"owner"}}},
  {"type":"drive","drive":{"id":"dr0","session":"s1","task":"Open Refunds","why":"done","at":"2026-11-24T07:50:00Z",
    "steps":[{"at":"x","line":"Looked"},{"at":"x","line":"Tapped Refunds","touched":{"words":"Refunds","taf":"Refunds"}}]}}
]}
"""#

let coachDriveMacTests: [Test] = [
    Test("Coach's drive card and what it did are drawn in Coach's chat, and the screenshot is written", awaiting: { @MainActor in
        let transport = CannedTransport([(200, setupAnswer), (200, noChats), (200, driveThread)])
        let model = CoachModel(cloud: CloudClient(transport: transport, session: session), sleep: { _ in })
        await model.load()
        guard case .loaded(_, let page) = model.state else { throw Failure(description: "the thread wasn't read") }
        try expectEqual(page.cards.map { model.drive($0) }, [.asking, .drove])
        guard case .drive(let drive, _) = page.items[3] else { throw Failure(description: "the drive's end") }
        try expectEqual(drive.steps.map(\.shown), ["Looked", "Tapped Refunds · Refunds · Refunds"])
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        let size = CGSize(width: 980, height: 900)
        let view = CoachView(model: model).environment(\.words, words)
        guard let bitmap = Snapshot.settled(of: view, size: size, until: { _ in true }) else { throw Failure(description: "nothing drawn") }
        // Asked on the phone, so nothing was sent from here past the reads.
        try expect(!transport.sent.contains { $0.path.contains("answer") || $0.path.contains("/drive") }, "nothing answered, no drive started")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
        try png.write(to: folder.appendingPathComponent("coach-drive.png"))
    }),
]

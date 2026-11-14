import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")
private let two = #"{"devices":[{"id":"dev_1","display_name":"Mac","platform":"macos","key_fingerprint":"3f2a 91c0 7b1e 0d44","last_used_at":"2026-11-14T18:09:40Z","this_device":true},{"id":"dev_2","display_name":"iPhone","platform":"ios","key_fingerprint":"9c1d 22ab 0f3e 77a1","last_used_at":"2026-11-14T15:10:00Z"}]}"#
private let oneLeft = #"{"devices":[{"id":"dev_1","display_name":"Mac","this_device":true}]}"#

@MainActor
private func model(_ answers: [(Int, String)], canRemoveOthers: Bool = true) -> (DevicesModel, CannedTransport) {
    let transport = CannedTransport(answers)
    return (DevicesModel(account: AccountClient(transport: transport, session: session), canRemoveOthers: canRemoveOthers), transport)
}

/// The colours drawn in a view, to tell whether Sign out's red is among them.
@MainActor
private func draws(_ wanted: UInt32, in view: DevicesView, words: Words) -> Bool {
    let size = CGSize(width: 980, height: 400)
    guard let bitmap = Snapshot.bitmap(of: view.environment(\.words, words), size: size) else { return false }
    for y in stride(from: 0, to: Int(size.height), by: 2) {
        for x in stride(from: 300, to: 740, by: 1) {
            guard let got = Snapshot.hex(bitmap, x: x, y: y) else { continue }
            if [16, 8, 0].allSatisfy({ abs(Int((got >> $0) & 0xFF) - Int((wanted >> $0) & 0xFF)) <= 6 }) { return true }
        }
    }
    return false
}

let accountScreenTests: [Test] = [
    Test("removing another device signs it out at KIFF and reads the list again", awaiting: { @MainActor in
        let (model, transport) = model([(200, two), (204, ""), (200, oneLeft)])
        await model.load()
        guard case .loaded(let devices) = model.state else { throw Failure(description: "not loaded") }
        await model.remove(devices[1])
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["GET /v1/me/devices", "DELETE /v1/me/devices/dev_2", "GET /v1/me/devices"])
        guard case .loaded(let left) = model.state else { throw Failure(description: "not loaded") }
        try expectEqual(left.map(\.id), ["dev_1"])
    }),
    Test("this Mac is never removed from the list's button, and a refused removal says why", awaiting: { @MainActor in
        let (model, transport) = model([(200, two), (403, #"{"error":"owner_only"}"#)])
        await model.load()
        guard case .loaded(let devices) = model.state else { throw Failure(description: "not loaded") }
        await model.remove(devices[0])
        try expectEqual(transport.sent.count, 1)
        await model.remove(devices[1])
        try expectEqual(model.notRemoved, "owner_only")
        try expectEqual(model.state, .loaded(devices))
    }),
    Test("a Mac that can't approve draws no Sign out for another device, and never sends a removal", awaiting: { @MainActor in
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        let (without, transport) = model([(200, two)], canRemoveOthers: false)
        await without.load()
        guard case .loaded(let devices) = without.state else { throw Failure(description: "not loaded") }
        try expect(!draws(Palette.no.light, in: DevicesView(model: without), words: words), "no red Sign out is drawn")
        await without.remove(devices[1])
        try expectEqual(transport.sent.map(\.method), ["GET"])
        try expectEqual(without.state, .loaded(devices))
        // The same list on a Mac that may: the button is there, so the check above can fail.
        let (with, _) = model([(200, two)])
        await with.load()
        try expect(draws(Palette.no.light, in: DevicesView(model: with), words: words), "Sign out is drawn when it may")
    }),
    Test("the default is that a Mac may not sign another device out", awaiting: { @MainActor in
        let transport = CannedTransport([])
        try expectEqual(DevicesModel(account: AccountClient(transport: transport, session: session)).canRemoveOthers, false)
    }),
    Test("signing out a device that approves needs a device that can approve, and says so", awaiting: { @MainActor in
        for code in ["approval_key_required", "critical_key_required"] {
            let (model, _) = model([(200, two), (403, #"{"error":"\#(code)"}"#)])
            await model.load()
            guard case .loaded(let devices) = model.state else { throw Failure(description: "not loaded") }
            await model.remove(devices[1])
            try expectEqual(model.needsApprover, true)
            try expectEqual(model.notRemoved, nil)
            try expectEqual(model.state, .loaded(devices))
        }
    }),
    Test("the screenshots: Devices in three languages", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr", "pt"] {
            let (model, _) = model([(200, two)], canRemoveOthers: false)
            await model.load()
            let view = DevicesView(model: model, now: Date(timeIntervalSince1970: 1_794_679_800))
                .environment(\.words, Words.load(folder: strings, preferred: [language]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 800)), let png = Snapshot.png(bitmap) else {
                throw Failure(description: "no PNG")
            }
            try png.write(to: folder.appendingPathComponent("devices-\(language).png"))
        }
    }),
]

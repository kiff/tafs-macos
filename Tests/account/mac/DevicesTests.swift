import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")
private let two = #"{"devices":[{"id":"dev_1","display_name":"Mac","platform":"macos","key_fingerprint":"3f2a 91c0 7b1e 0d44","last_used_at":"2026-11-14T18:09:40Z","this_device":true},{"id":"dev_2","display_name":"iPhone","platform":"ios","key_fingerprint":"9c1d 22ab 0f3e 77a1","last_used_at":"2026-11-14T15:10:00Z"}]}"#
private let oneLeft = #"{"devices":[{"id":"dev_1","display_name":"Mac","this_device":true}]}"#

@MainActor
private func model(_ answers: [(Int, String)]) -> (DevicesModel, CannedTransport) {
    let transport = CannedTransport(answers)
    return (DevicesModel(account: AccountClient(transport: transport, session: session)), transport)
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
    Test("the screenshots: Devices in three languages", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr", "pt"] {
            let (model, _) = model([(200, two)])
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

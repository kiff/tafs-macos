import Foundation
import SwiftUI
import AppKit

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

@MainActor
private func model(_ answers: [(Int, String)]) -> (UsageModel, CannedTransport) {
    let transport = CannedTransport(answers)
    return (UsageModel(cloud: CloudClient(transport: transport, session: session)), transport)
}

let usageMacTests: [Test] = [
    Test("each half is read on its own: an unread balance leaves the credits, and the other way round", awaiting: { @MainActor in
        let (a, _) = model([(503, ""), (200, creditsAnswer)])
        await a.load()
        try expectEqual(a.balance, .unread(why: "503"))
        guard case .loaded = a.credits else { throw Failure(description: "the credits were lost") }
        let (b, _) = model([(200, balanceAnswer), (500, "")])
        await b.load()
        guard case .loaded = b.balance else { throw Failure(description: "the balance was lost") }
        try expectEqual(b.credits, .unread(why: "500"))
    }),
    Test("choosing the last period reads it, and choosing the same one again reads nothing", awaiting: { @MainActor in
        let (model, transport) = model([(200, balanceAnswer), (200, creditsAnswer), (200, creditsAnswer)])
        await model.load()
        await model.show(previous: true)
        await model.show(previous: true)
        try expectEqual(transport.sent.map(\.path), ["/v1/usage/balance", "/v1/usage/credits", "/v1/usage/credits?period=previous"])
        try expectEqual(model.previous, true)
    }),
    Test("the screen only reads: nothing but GET is ever sent", awaiting: { @MainActor in
        let (model, transport) = model([(200, balanceAnswer), (200, creditsAnswer), (200, creditsAnswer)])
        await model.load()
        await model.show(previous: true)
        try expectEqual(Set(transport.sent.map(\.method)), ["GET"])
    }),
    Test("the meter fills to its fraction and never past its track, either way", awaiting: { @MainActor in
        // Red on a white ground, so a pixel says plainly whether the fill reaches it.
        func filled(_ fraction: Double, at x: Double) throws -> Bool {
            let meter = Meter(fraction: fraction, color: Color(red: 1, green: 0, blue: 0)).background(Color.white)
            guard let bitmap = Snapshot.bitmap(of: meter, size: CGSize(width: 200, height: 5)),
                  let pixel = bitmap.colorAt(x: Int(Double(bitmap.pixelsWide) * x), y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB)
            else { throw Failure(description: "no bitmap") }
            return pixel.redComponent > 0.9 && pixel.greenComponent < 0.2
        }
        try expect(try filled(0.4, at: 0.3), "40% reaches 30%")
        try expect(!(try filled(0.4, at: 0.5)), "40% stops before 50%")
        try expect(try filled(2, at: 0.95), "past 1 is full")
        try expect(!(try filled(-1, at: 0.05)), "under 0 is empty")
    }),
    Test("the screenshots: Plan & usage in three languages", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr", "pt"] {
            let (model, _) = model([(200, balanceAnswer), (200, creditsAnswer)])
            await model.load()
            let view = UsageView(model: model).environment(\.words, Words.load(folder: strings, preferred: [language]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 700)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("usage-\(language).png"))
        }
    }),
]

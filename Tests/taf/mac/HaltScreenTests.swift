import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

let tafHaltTests: [Test] = [
    Test("halting is one POST, then the halt is read again while halting until every part holds it", awaiting: { @MainActor in
        let transport = CannedTransport([
            (200, #"{"halt":{"state":"halting","runtime":true}}"#),
            (200, #"{"halt":{"state":"halting","runtime":true,"kiff":true}}"#),
            (200, #"{"halt":{"state":"halted","runtime":true,"kiff":true,"planque":true}}"#),
        ])
        let model = HaltModel(cloud: CloudClient(transport: transport, session: session), taf: "taf-1", sleep: { _ in })
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        await model.halt(words: words)
        try expectEqual(transport.sent.map(\.method), ["POST", "GET", "GET"])
        try expectEqual(model.halt.state, .halted)
        try expectEqual(model.notHalted, nil)
    }),
    Test("a halt tafs cloud refuses says why, in the shared words, and stays running", awaiting: { @MainActor in
        let transport = CannedTransport([(403, #"{"error":"not_allowed"}"#)])
        let model = HaltModel(cloud: CloudClient(transport: transport, session: session), taf: nil, sleep: { _ in })
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        await model.halt(words: words)
        try expectEqual(model.halt.state, .running)
        try expect(model.notHalted?.hasPrefix("tafs couldn't halt your tafs.") == true, model.notHalted ?? "nothing said")
    }),
    Test("the screenshots: a halt running, and halted with who holds it", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, answer) in [("running", #"{"halt":{"state":"running"}}"#), ("halted", #"{"halt":{"state":"halted","runtime":true,"kiff":true,"planque":true}}"#)] {
            let model = HaltModel(cloud: CloudClient(transport: CannedTransport([(200, answer), (200, answer)]), session: session), taf: nil, sleep: { _ in })
            await model.refresh()
            let view = HaltView(model: model, name: nil, close: {}).environment(\.words, Words.load(folder: strings, preferred: ["en"]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 520, height: 520)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("halt-\(name)-en.png"))
        }
    }),
]

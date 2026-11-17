import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

private let tafs: [Home.Taf] = {
    let json = #"{"tafs":[{"id":"taf_1","name":"Refunds","kiff_agent":"a1","color":1,"state":"working","work":{"line":"Working on 3 refunds"}},{"id":"taf_2","name":"Invoices","kiff_agent":"a2","color":4,"state":"idle","next_run_words":"Next run Mon 08:00"}]}"#
    return (try? AccountClient.decoder.decode(Home.Page.self, from: Data(json.utf8)))?.tafs ?? []
}()

let shellHaltAllMacTests: [Test] = [
    Test("the screenshots: the sidebar with Halt all under Connect apps, running and halted, light and dark", awaiting: { @MainActor in
        Mascot.file = URL(fileURLWithPath: ".shared/ios/Shared/Mascot.xcassets/Mascot.imageset/mascot.png")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let halted = #"{"halt":{"state":"halted","halted_at":"2026-11-15T09:00:00Z","runtime":true,"kiff":true,"planque":true}}"#
        for (name, answer) in [("running", #"{"halt":{"state":"running"}}"#), ("halted", halted)] {
            let halt = HaltModel(cloud: CloudClient(transport: CannedTransport([(200, answer)]), session: session), taf: nil, sleep: { _ in })
            await halt.refresh()
            for dark in [false, true] {
                let view = ShellView(selection: .constant(.overview), needsYou: 3, tafs: tafs, held: [], accountLine: "you@example.com", haltAll: halt)
                    .environment(\.words, Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"]))
                guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 1280, height: 800), dark: dark), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
                try png.write(to: folder.appendingPathComponent("sidebar-halt-all-\(name)-en\(dark ? "-dark" : "").png"))
            }
        }
    }),
]

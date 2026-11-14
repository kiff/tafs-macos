import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

@MainActor
private func model(_ answers: [(Int, String)]) -> OverviewModel {
    OverviewModel(cloud: CloudClient(transport: CannedTransport(answers), session: session))
}

let overviewMacTests: [Test] = [
    Test("the Overview loads tafs cloud's list, and says so when it can't", awaiting: { @MainActor in
        let loaded = model([(200, homePage)])
        await loaded.load()
        guard case .loaded(let page) = loaded.state else { throw Failure(description: "not loaded") }
        try expectEqual(page.tafs.count, 3)
        let unread = model([(503, "")])
        await unread.load()
        try expectEqual(unread.state, .unread(why: "503"))
    }),
    Test("the screenshots: the Overview with tafs, and with none, in three languages", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr", "pt"] {
            for (name, body) in [("tafs", homePage), ("empty", #"{"tafs":[]}"#)] {
                let model = model([(200, body)])
                await model.load()
                let view = OverviewView(model: model).environment(\.words, Words.load(folder: strings, preferred: [language]))
                guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 800)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
                try png.write(to: folder.appendingPathComponent("overview-\(name)-\(language).png"))
            }
        }
    }),
]

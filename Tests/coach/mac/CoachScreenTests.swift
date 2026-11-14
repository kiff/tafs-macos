import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

@MainActor
private func make(_ answers: [(Int, String)]) -> (CoachModel, CannedTransport) {
    let transport = CannedTransport(answers)
    return (CoachModel(cloud: CloudClient(transport: transport, session: session)), transport)
}

let coachScreenTests: [Test] = [
    Test("Coach's chat is read from its own taf, and an account with no Coach reads no thread", awaiting: { @MainActor in
        let (model, transport) = make([(200, setupAnswer), (200, threadAnswer)])
        await model.load()
        try expectEqual(transport.sent.map(\.path), ["/v1/setup", "/v1/tafs/taf%2Dcoach/conversation"])
        guard case .loaded(let coach, let page) = model.state else { throw Failure(description: "not loaded") }
        try expectEqual(coach.id, "taf-coach")
        try expectEqual(page.items.count, 6)
        let (none, sent) = make([(200, #"{"setup":null}"#)])
        await none.load()
        try expectEqual(none.state, .notStarted)
        try expectEqual(sent.sent.count, 1)
    }),
    Test("opening the chat only reads, and a chat that can't be read says so", awaiting: { @MainActor in
        let (model, transport) = make([(200, setupAnswer), (200, threadAnswer)])
        await model.load()
        try expectEqual(Set(transport.sent.map(\.method)), ["GET"])
        let (unread, _) = make([(200, setupAnswer), (500, "")])
        await unread.load()
        try expectEqual(unread.state, .unread(why: "500"))
    }),
    Test("the screenshots: Coach's chat in three languages", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr", "pt"] {
            let (model, _) = make([(200, setupAnswer), (200, threadAnswer)])
            await model.load()
            let view = CoachView(model: model).environment(\.words, Words.load(folder: strings, preferred: [language]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 600)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("coach-\(language).png"))
        }
    }),
]

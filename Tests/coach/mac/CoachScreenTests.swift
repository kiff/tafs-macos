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
        let (model, transport) = make([(200, setupAnswer), (200, noChats), (200, threadAnswer)])
        await model.load()
        try expectEqual(transport.sent.map(\.path), ["/v1/setup", "/v1/tafs/taf-coach/chats", "/v1/tafs/taf-coach/conversation"])
        guard case .loaded(let coach, let page) = model.state else { throw Failure(description: "not loaded") }
        try expectEqual(coach.id, "taf-coach")
        try expectEqual(page.items.count, 6)
        let (none, sent) = make([(200, #"{"setup":null}"#)])
        await none.load()
        try expectEqual(none.state, .notStarted)
        try expectEqual(sent.sent.count, 1)
    }),
    Test("opening the chat only reads, and a chat that can't be read says so", awaiting: { @MainActor in
        let (model, transport) = make([(200, setupAnswer), (200, noChats), (200, threadAnswer)])
        await model.load()
        try expectEqual(Set(transport.sent.map(\.method)), ["GET"])
        let (unread, _) = make([(200, setupAnswer), (200, noChats), (500, "")])
        await unread.load()
        try expectEqual(unread.state, .unread(why: "500"))
    }),
    Test("an empty chat is Coach mode's start; while Coach works the box asks for the next message", awaiting: { @MainActor in
        let (none, _) = make([(200, #"{"setup":null}"#)])
        await none.load()
        try expectEqual(none.isEmpty, true)
        let (empty, _) = make([(200, setupAnswer), (200, noChats), (200, #"{"items":[]}"#)])
        await empty.load()
        try expectEqual(empty.isEmpty, true)
        try expectEqual(empty.working, false)
        // A run going on with nothing in the thread yet is not the start: Coach is at work.
        let (busy, _) = make([(200, setupAnswer), (200, noChats), (200, #"{"items":[],"working":true}"#)])
        await busy.load()
        try expectEqual(busy.isEmpty, false)
        try expectEqual(busy.working, true)
        let (full, _) = make([(200, setupAnswer), (200, noChats), (200, threadAnswer)])
        await full.load()
        try expectEqual(full.isEmpty, false)
        let (loading, _) = make([])
        try expectEqual(loading.isEmpty, false)
    }),
    Test("the screenshots: Coach's chat in three languages, and its start", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr", "pt"] {
            let (model, _) = make([(200, setupAnswer), (200, noChats), (200, threadAnswer)])
            await model.load()
            let view = CoachView(model: model).environment(\.words, Words.load(folder: strings, preferred: [language]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 600)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("coach-\(language).png"))
        }
        let (empty, _) = make([(200, setupAnswer), (200, noChats), (200, #"{"items":[]}"#)])
        await empty.load()
        let start = CoachView(model: empty).environment(\.words, Words.load(folder: strings, preferred: ["en"]))
        guard let bitmap = Snapshot.bitmap(of: start, size: CGSize(width: 980, height: 600)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
        try png.write(to: folder.appendingPathComponent("coach-start-en.png"))
    }),
]

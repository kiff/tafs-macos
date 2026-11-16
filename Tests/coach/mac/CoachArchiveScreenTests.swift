import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let twoChats = #"{"chats":[{"session":"s1","started":"2026-11-13T09:00:00Z","updated":"2026-11-13T10:00:00Z","title":"Refunds"},{"session":"s2","started":"2026-11-14T09:00:00Z","updated":"2026-11-14T10:00:00Z","title":"Invoices"}]}"#
private let oneArchived = #"{"chats":[{"session":"s0","started":"2026-11-12T09:00:00Z","updated":"2026-11-12T10:00:00Z","title":"Late parcels"}]}"#
private let thread = #"{"working":false,"items":[{"type":"message","message":{"id":"m1","from":"taf","text":"What should your taf do?","session":"s2"}}]}"#

/// Answers as canned, and runs something while a request is on its way: the person signing out.
private final class WhileSending: Transport, @unchecked Sendable {
    let canned: CannedTransport
    var during: (String) async -> Void = { _ in }
    init(_ answers: [(Int, String)]) { canned = CannedTransport(answers) }
    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        await during(request.path)
        return try await canned.send(request)
    }
}

/// Coach read, open on its newest chat (s2), with Previous conversations listed.
@MainActor
private func make(_ answers: [(Int, String)]) async -> (CoachModel, CannedTransport) {
    let transport = CannedTransport([(200, setupAnswer), (200, twoChats), (200, thread)] + answers)
    let model = CoachModel(cloud: CloudClient(transport: transport, session: session), sleep: { _ in })
    await model.load()
    return (model, transport)
}

let coachArchiveMacTests: [Test] = [
    Test("archiving the chat shown gives way to a new conversation; another chat only leaves the list", awaiting: { @MainActor in
        let (model, transport) = await make([(200, twoChats), (200, #"{"archived":true}"#), (200, #"{"archived":true}"#)])
        try expectEqual(model.chat, "s2")
        await model.loadChats()
        let archivedOther = await model.archive(chat: "s1")
        try expectEqual(archivedOther, nil)
        try expectEqual(model.chats.map(\.session), ["s2"])
        try expectEqual(model.chat, "s2")
        try expectEqual(model.fresh, false)
        let archivedShown = await model.archive(chat: "s2")
        try expectEqual(archivedShown, nil)
        try expectEqual(model.chats, [])
        try expectEqual(model.chat, nil)
        try expectEqual(model.fresh, true)
        try expectEqual(transport.sent.map(\.path).suffix(2), ["/v1/tafs/taf-coach/chats/s1/archive", "/v1/tafs/taf-coach/chats/s2/archive"])
    }),
    Test("an archive tafs cloud refuses says why in the shared words, and the list stays as it was", awaiting: { @MainActor in
        let (model, _) = await make([(200, twoChats), (409, #"{"error":"busy"}"#)])
        await model.loadChats()
        let refused = await model.archive(chat: "s1")
        try expectEqual(refused, "Not archived. busy")
        try expectEqual(model.chats.count, 2)
        try expectEqual(model.chat, "s2")
    }),
    Test("Archived lists the archived chats; Put back returns one and reads the list again", awaiting: { @MainActor in
        let (model, transport) = await make([(200, oneArchived), (200, #"{"archived":false}"#), (200, twoChats), (500, "")])
        await model.loadArchivedChats()
        try expectEqual(model.archivedChats.map(\.title), ["Late parcels"])
        let putBack = await model.putBack(chat: "s0")
        try expectEqual(putBack, nil)
        try expectEqual(model.archivedChats, [])
        try expectEqual(model.chats.count, 2)
        try expectEqual(transport.sent.map(\.path).suffix(3), ["/v1/tafs/taf-coach/chats/archived", "/v1/tafs/taf-coach/chats/s0/unarchive", "/v1/tafs/taf-coach/chats"])
        // An archived read that fails keeps the list as it was.
        await model.loadArchivedChats()
        try expectEqual(model.archivedChats, [])
    }),
    Test("an archive or a put-back answered after sign-out says nothing and changes nothing", awaiting: { @MainActor in
        let transport = WhileSending([(200, setupAnswer), (200, twoChats), (200, thread), (200, #"{"archived":true}"#), (200, oneArchived), (200, #"{"archived":false}"#)])
        let model = CoachModel(cloud: CloudClient(transport: transport, session: session), sleep: { _ in })
        await model.load()
        transport.during = { _ in await MainActor.run { model.signedOut() } }
        let archivedShown = await model.archive(chat: "s2")
        try expectEqual(archivedShown, nil)
        try expectEqual(model.chat, "s2")
        try expectEqual(model.fresh, false)
        await model.loadArchivedChats()
        try expectEqual(model.archivedChats, [])
        let putBack = await model.putBack(chat: "s0")
        try expectEqual(putBack, nil)
    }),
    Test("the screenshots: Previous conversations with Archive and Archived, and Archived with Put back, in English and French", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr"] {
            let (model, _) = await make([(200, twoChats), (200, oneArchived)])
            await model.loadChats()
            await model.loadArchivedChats()
            let words = Words.load(folder: strings, preferred: [language])
            for (archived, name) in [(false, "coach-chats"), (true, "coach-chats-archived")] {
                let view = CoachChatsSheet(model: model, open: { _ in }, archived: archived).environment(\.words, words)
                guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 420, height: 460)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
                try png.write(to: folder.appendingPathComponent("\(name)-\(language).png"))
            }
        }
    }),
]

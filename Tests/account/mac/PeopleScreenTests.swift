import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")
private let groups = #"{"groups":[{"id":"g1","name":"Everyone","everyone":true,"members":[{"subject":"u1","role":"member"},{"subject":"u2","role":"manager"}],"agents":["agent_refunds"]},{"id":"g2","name":"Finance","members":[{"subject":"u2","role":"member"}],"agents":[]}]}"#
private let people = #"{"members":[{"subject":"u1","role":"admin","status":"active","email":"you@example.com","you":true},{"subject":"u2","role":"member","status":"active","email":"sam@example.com"}]}"#

@MainActor
private func make(_ answers: [(Int, String)]) -> (PeopleModel, CannedTransport) {
    let transport = CannedTransport(answers)
    return (PeopleModel(account: AccountClient(transport: transport, session: session)), transport)
}

let accountPeopleTests: [Test] = [
    Test("People & groups reads both lists and only reads; a failed first read says why, a later one keeps what's shown and says why over it", awaiting: { @MainActor in
        let (model, transport) = make([(200, groups), (200, people), (500, ""), (500, "")])
        await model.load()
        guard case .loaded(let read, let persons) = model.state else { throw Failure(description: "not loaded") }
        try expectEqual(read.map(\.id), ["g1", "g2"])
        try expectEqual(persons.count, 2)
        await model.load()
        try expectEqual(Set(transport.sent.map(\.method)), ["GET"])
        if case .unread = model.state { throw Failure(description: "a later failure hid the groups") }
        // Why it failed is said over what is kept, until a read works.
        try expectEqual(model.notRead, "500")
        let (unread, _) = make([(500, ""), (500, "")])
        await unread.load()
        if case .loaded = unread.state { throw Failure(description: "a failed read was shown as loaded") }
    }),
    Test("the screenshots: People & groups in three languages", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let me = try AccountClient.decoder.decode(Me.self, from: Data(#"{"tenant_slug":"acme","tenant_display_name":"Acme","email":"you@example.com"}"#.utf8))
        for language in ["en", "fr", "pt"] {
            let (model, _) = make([(200, groups), (200, people)])
            await model.load()
            let view = PeopleView(model: model, me: me, tafName: { $0 == "agent_refunds" ? "Refunds" : nil })
                .environment(\.words, Words.load(folder: strings, preferred: [language]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 700)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("people-\(language).png"))
        }
    }),
]

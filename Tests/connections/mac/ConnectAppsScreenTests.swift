import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let second = #"{"apps":[{"entry":"connector:p:slack","name":"Slack","state":"available","line":"Sign in"},{"entry":"connector:p:notion","name":"Notion","state":"available","line":"Sign in"}],"partial":true}"#

@MainActor
private func make(_ answers: [(Int, String)]) -> (ConnectAppsModel, CannedTransport) {
    let transport = CannedTransport(answers)
    return (ConnectAppsModel(cloud: CloudClient(transport: transport, session: session)), transport)
}

let connectAppsMacTests: [Test] = [
    Test("yours come first and apart from the catalog, and the next page lists no app twice", awaiting: { @MainActor in
        let (model, transport) = make([(200, appsPage), (200, second)])
        await model.load()
        try expectEqual(model.yours.map(\.name), ["Qonto", "Gmail"])
        try expectEqual(model.discover.map(\.name), ["Slack", "Bank"])
        try expectEqual(model.canContinue, true)
        await model.more()
        try expectEqual(transport.sent[1].path, "/v1/connect/apps?q=&cursor=c2")
        try expectEqual(model.discover.map(\.name), ["Slack", "Bank", "Notion"])
        try expectEqual(model.canContinue, false)
        try expectEqual(model.partial, true)
    }),
    Test("the screen only lists: nothing but GET is sent, and an unreadable catalog says so", awaiting: { @MainActor in
        let (model, transport) = make([(200, appsPage), (200, second)])
        await model.load()
        await model.more()
        try expectEqual(Set(transport.sent.map(\.method)), ["GET"])
        let (unread, _) = make([(502, "")])
        await unread.load()
        try expectEqual(unread.state, .unread(why: "502"))
        try expectEqual(unread.apps.count, 0)
    }),
    Test("Not listed? Ask Coach shows only while tafs cloud says Coach can connect by key; a new search asks again", awaiting: { @MainActor in
        let byKey = #"{"apps":[{"entry":"connector:p:slack","name":"Slack","state":"available"}],"by_key":true,"next_cursor":"c2"}"#
        let (model, _) = make([(200, appsPage), (200, byKey), (200, second), (200, appsPage)])
        await model.load()
        try expectEqual(model.byKey, false)
        await model.load()
        try expectEqual(model.byKey, true)
        await model.more()
        try expectEqual(model.byKey, true)
        await model.load()
        try expectEqual(model.byKey, false)
    }),
    Test("the screenshots: Connect apps in three languages", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr", "pt"] {
            let (model, _) = make([(200, appsPage)])
            await model.load()
            // A taf this person manages, so Connect is on: "Make one first" has its own shot.
            let refunds = try AccountClient.decoder.decode(Home.Taf.self, from: Data(#"{"kiff_agent":"a_refunds","id":"t1","name":"Refunds","state":"idle"}"#.utf8))
            let view = ConnectAppsView(model: model, connectable: [refunds]).environment(\.words, Words.load(folder: strings, preferred: [language]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 760)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("connect-apps-\(language).png"))
        }
    }),
    Test("a signed-in row's status is tafs cloud's line without how it connects, which has its own column") {
        try expect(ConnectAppsView.statusLine("Sign in · Signed in · Not used by any taf") == "Signed in · Not used by any taf", "the method part goes")
        try expect(ConnectAppsView.statusLine("Sign in") == nil, "nothing after it: the shared words")
        try expect(ConnectAppsView.statusLine(nil) == nil, "no line: the shared words")
    },
    Test("the screenshot: every sign-in under Yours, the unused one included, from tafs cloud's own contract", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // connect-apps.json's first page: Gmail to sign in again, Stripe connected, and Pipedrive signed in with no taf.
        let data = try Data(contentsOf: URL(fileURLWithPath: ".shared/contracts/connect-apps.json"))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let answer = object["answer"] else {
            throw Failure(description: "connect-apps.json has no answer")
        }
        let page = String(decoding: try JSONSerialization.data(withJSONObject: answer), as: UTF8.self)
        let (model, _) = make([(200, page)])
        await model.load()
        let pipedrive = model.yours.first { $0.name == "Pipedrive" }
        try expect(pipedrive?.isSignedIn == true && pipedrive?.usedBy.isEmpty == true, "Pipedrive, signed in and used by no taf, is under Yours")
        let refunds = try AccountClient.decoder.decode(Home.Taf.self, from: Data(#"{"kiff_agent":"a_refunds","id":"t1","name":"Refunds","state":"idle"}"#.utf8))
        let view = ConnectAppsView(model: model, connectable: [refunds]).environment(\.words, Words.load(folder: strings, preferred: ["en"]))
        guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 760)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
        try png.write(to: folder.appendingPathComponent("connect-apps-signed-in-en.png"))
    }),
]

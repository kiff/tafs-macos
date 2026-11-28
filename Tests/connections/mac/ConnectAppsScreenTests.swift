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
    Test("the screenshot: the two ways a taf uses websites, and a cloud connection's saved sign-ins with their health, light and dark", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let page = #"""
        {"apps":[
          {"entry":"browser","name":"Websites","state":"connected","line":"Connected","grant":"g_web","whose":"Yours","way":"cloud",
           "way_words":{"title":"Cloud browser","line":"Works while your computer is off."}}
        ],
        "saved_sign_ins":[
          {"grant":"g_web","site":"supplier-portal.example","used_by":["File invoices"],"sign_in":{"title":"Sign in again"},"health":{"state":"needs_you_soon","words":{"line":"Needs you by Tue 2 Dec","why":"At 07:00, tafs opened one page of the site with your saved sign-in, without clicking anything. The site set your saved sign-in to end on 2 Dec."}}},
          {"grant":"g_web","site":"books.example","used_by":["Month end"],"sign_in":{"title":"Sign in again"},"health":{"state":"signed_in","words":{"line":"Signed in · checked today 07:00"}}},
          {"grant":"g_web","site":"tax-office.example","used_by":["VAT return"],"sign_in":{"title":"Sign in again"},"health":{"state":"stopped","words":{"line":"Stopped working at 07:55","why":"At 07:55, tafs opened one page of the site with your saved sign-in, without clicking anything. The site asked to sign in again."}}}
        ],
        "ways":[
          {"way":"cloud","words":{"title":"Cloud browser","line":"Works while your computer is off.","facts":["A fresh browser for each run, only on the sites you allow.","You sign in once, in a live view. Your password is never kept."],"status":"3 sign-ins saved"}},
          {"way":"chrome","words":{"title":"Chrome extension","line":"Works in your Chrome, where you're signed in.","facts":["Uses the sign-ins already in your Chrome. Your passwords stay there.","Banks and password managers stay blocked unless your phone allows each one."],"status":"Paired with Office Mac"}}
        ]}
        """#
        let (model, _) = make([(200, page)])
        await model.load()
        try expectEqual(model.ways.map(\.way), ["cloud", "chrome"])
        try expectEqual(model.yours.first.map { model.savedSignIns(of: $0).count }, 3)
        model.siteSignIn = { _ in throw PlanqueClient.PlanqueError.notSigning }
        for dark in [false, true] {
            let view = ConnectAppsView(model: model, connectable: []).environment(\.words, Words.load(folder: strings, preferred: ["en"]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 760), dark: dark), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("connect-apps-ways-en\(dark ? "-dark" : "").png"))
        }
    }),
    Test("the screenshot: Needs you's two sign-in items, soon with Later and stopped with Skip this run", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let home = #"""
        {"tafs":[],"sign_ins":[
          {"kind":"sign_in_soon","grant":"g_web","site":"supplier-portal.example","taf":{"id":"t1","name":"File invoices"},
           "words":{"title":"Sign-in · needs you soon","line":"supplier-portal.example asks you to sign in again by Tue 2 Dec","sign_in":"Sign in again","later":"Later","why":"File invoices runs there every day at 8:00. Until then it works as now."}},
          {"kind":"sign_in_stopped","grant":"g_web","site":"tax-office.example","taf":{"id":"t2","name":"VAT return"},
           "words":{"title":"Sign-in · stopped working","line":"VAT return's 8:00 run waits for you. It won't run with a broken sign-in, and it's skipped only if you skip it.","sign_in":"Sign in again","skip":"Skip this run"}}
        ]}
        """#
        let page = try AccountClient.decoder.decode(Home.Page.self, from: Data(home.utf8))
        let needsYou = NeedsYouModel(account: AccountClient(transport: CannedTransport([]), session: Session(accessToken: "t", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)), route: .touchID)
        needsYou.show(page)
        needsYou.siteSignIn = { _ in throw PlanqueClient.PlanqueError.notSigning }
        for dark in [false, true] {
            let view = VStack(spacing: 14) { ForEach(needsYou.signIns) { SignInNeedCard(model: needsYou, need: $0) } }
                .padding(20).frame(width: 560).background(Theme.background)
                .environment(\.words, Words.load(folder: strings, preferred: ["en"]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 560, height: 420), dark: dark), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("needs-you-sign-ins-en\(dark ? "-dark" : "").png"))
        }
    }),
]

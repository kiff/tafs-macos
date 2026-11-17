import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")
private let meView = #"{"tenant_slug":"acme","tenant_display_name":"Acme","email":"you@example.com","approval_mode":"view"}"#
private let mePasskey = #"{"tenant_slug":"acme","email":"you@example.com","approval_mode":"passkey"}"#

@MainActor
private func make(_ kiff: [(Int, String)], _ cloudAnswers: [(Int, String)], defaults: UserDefaults) -> AccountModel {
    AccountModel(account: AccountClient(transport: CannedTransport(kiff), session: session),
                 cloud: CloudClient(transport: CannedTransport(cloudAnswers), session: session), defaults: defaults)
}

private func scratchDefaults() -> UserDefaults {
    let name = "tafs.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

let accountPageTests: [Test] = [
    Test("Export my chats offers its two files, says why when it couldn't, and shares the last files again", awaiting: { @MainActor in
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("export-mac-\(UUID().uuidString)", isDirectory: true)
        let transport = CannedTransport([(503, #"{"error":"down"}"#), (200, #"{"readable":"hi","chats":[]}"#)])
        let model = ExportChatsModel(cloud: CloudClient(transport: transport, session: session), folder: folder)
        await model.export(words: words)
        try expectEqual(model.why, "Your chats weren't exported. Check your connection and try again.")
        try expectEqual(model.sharing, nil)
        await model.export(words: words)
        try expectEqual(model.why, nil)
        try expectEqual(model.made?.map(\.lastPathComponent), ["tafs-chats.json", "tafs-chats.txt"])
        try expectEqual(model.sharing, model.made)
        model.sharing = nil
        model.shareAgain()
        try expectEqual(model.sharing, model.made)
        ChatsExport.removeFiles(in: folder)
    }),
    Test("the page reads who is signed in and the plan's line, each on its own", awaiting: { @MainActor in
        let both = make([(200, meView)], [(200, balanceLine)], defaults: scratchDefaults())
        await both.load()
        try expectEqual(both.me?.email, "you@example.com")
        try expectEqual(both.me?.viewOnly, true)
        try expectEqual(both.balance?.planLine, "Solo · renews 1 December")
        try expectEqual(both.balance?.planTone, "warning")
        try expectEqual(both.planColor, Theme.amberText)
        let noPlan = make([(200, mePasskey)], [(503, "")], defaults: scratchDefaults())
        await noPlan.load()
        try expectEqual(noPlan.me?.viewOnly, false)
        try expectEqual(noPlan.balance, nil)
        try expectEqual(noPlan.planColor, Theme.ink)
        let noMe = make([(500, "")], [(200, balanceLine)], defaults: scratchDefaults())
        await noMe.load()
        try expectEqual(noMe.me, nil)
        try expectEqual(noMe.balance?.planLine, "Solo · renews 1 December")
    }),
    Test("the theme chosen is kept for the next launch, and System is the start", awaiting: { @MainActor in
        let defaults = scratchDefaults()
        try expectEqual(ThemeChoice.saved(in: defaults), .system)
        let model = make([], [], defaults: defaults)
        model.choose(.dark)
        try expectEqual(ThemeChoice.saved(in: defaults), .dark)
        try expectEqual(make([], [], defaults: defaults).theme, .dark)
        defaults.set("neon", forKey: ThemeChoice.key)
        try expectEqual(ThemeChoice.saved(in: defaults), .system)
    }),
    Test("the screenshots: Account in three languages, view-only and not, view-only with a software key, and the whole page", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A software key pairs view-only (the iPad's Pairing.swift:88-91): its line, never Add this Mac.
        for (language, me, softwareKey, name) in [("en", meView, false, "account-view-only-en"), ("en", meView, true, "account-view-only-software-key-en"),
                                                  ("en", mePasskey, false, "account-en"), ("fr", mePasskey, false, "account-fr"), ("pt", mePasskey, false, "account-pt")] {
            let model = make([(200, me)], [(200, balanceLine)], defaults: scratchDefaults())
            await model.load()
            let devices = DevicesModel(account: AccountClient(transport: CannedTransport([]), session: session))
            let view = AccountView(model: model, devices: devices, open: { _ in }, addThisMac: {}, softwareKey: softwareKey, signOut: {})
                .environment(\.words, Words.load(folder: strings, preferred: [language]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 900)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("\(name).png"))
        }
        // The whole page, down to Language, About and Sign out.
        let model = make([(200, mePasskey)], [(200, balanceLine)], defaults: scratchDefaults())
        await model.load()
        let devices = DevicesModel(account: AccountClient(transport: CannedTransport([]), session: session))
        let view = AccountView(model: model, devices: devices, open: { _ in }, addThisMac: {}, signOut: {})
            .environment(\.words, Words.load(folder: strings, preferred: ["en"]))
        guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 1800)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
        try png.write(to: folder.appendingPathComponent("account-whole-en.png"))
    }),
]

private let meOwner = #"{"tenant_slug":"acme","tenant_display_name":"Acme","email":"you@example.com","approval_mode":"passkey","time_zone":"Europe/Paris","capabilities":["cards.manage","account.delete"]}"#
private let suggestionsOn = #"{"suggestions":{"show":true,"words":"New conversations offer jobs to start from."}}"#
private let zonesAnswer = #"{"zones":[{"id":"Europe/Paris","title":"Paris (UTC+1)"},{"id":"Europe/London","title":"London (UTC+0)"},{"id":"America/New_York","title":"New York (UTC-5)"}]}"#

/// A consent from tafs cloud's own contract, given or not.
private func consentAnswer(given: Bool) throws -> String {
    let data = try Data(contentsOf: URL(fileURLWithPath: ".shared/contracts/ai-consent.json"))
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let cases = root["cases"] as? [[String: Any]],
          let found = cases.first(where: { ($0["name"] as? String) == (given ? "given" : "not given yet") }), let body = found["body"]
    else { throw Failure(description: "no consent case") }
    return String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
}

/// An owner's Account, every row read: who is signed in, the plan, Coach's suggestions and AI use given.
@MainActor
private func owner(confirm: @escaping (String) async throws -> Void = { _ in }) async throws -> (AccountModel, CannedTransport, CannedTransport) {
    let kiff = CannedTransport([(200, meOwner)])
    let cloud = CannedTransport([(200, balanceLine), (200, suggestionsOn), (200, try consentAnswer(given: true)), (200, zonesAnswer)])
    let model = AccountModel(account: AccountClient(transport: kiff, session: session, sign: { _ in "t=1,v1=SIG" }),
                             cloud: CloudClient(transport: cloud, session: session), defaults: scratchDefaults(), confirm: confirm)
    await model.load()
    await model.loadSettings()
    await model.loadZones("", words: Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"]))
    return (model, kiff, cloud)
}

let accountControlsMacTests: [Test] = [
    Test("Account reads Coach's suggestions and the consent; Show suggestions and Withdraw each send one change", awaiting: { @MainActor in
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        let (model, _, cloud) = try await owner()
        try expectEqual(model.suggestions?.show, true)
        try expectEqual(model.consent?.given, true)
        try expectEqual(model.zones.map(\.id), ["Europe/Paris", "Europe/London", "America/New_York"])
        try expectEqual(model.zone, "Europe/Paris")
        cloud.answers = [(200, #"{"suggestions":{"show":false}}"#), (200, try consentAnswer(given: false))]
        await model.setSuggestions(false, words: words)
        try expectEqual(model.suggestions?.show, false)
        await model.withdrawAI(words: words)
        try expectEqual(model.consent?.given, false)
        try expectEqual(Array(cloud.sent.suffix(2)).map { $0.method + " " + $0.path }, ["PUT /v1/me/suggestions", "DELETE /v1/me/ai-consent"])
        // A change refused says so in the shared words, and keeps what was.
        cloud.answers = [(403, #"{"error":"Only the account's admins can change this."}"#)]
        await model.setSuggestions(true, words: words)
        try expectEqual(model.suggestions?.show, false)
        try expectEqual(model.suggestionsError, "It didn't change. Only the account's admins can change this.")
    }),
    Test("not given, AI use opens the consent's screen; Allow sends the version read, Not now sends nothing", awaiting: { @MainActor in
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        let (model, _, cloud) = try await owner()
        cloud.answers = [(200, suggestionsOn), (200, try consentAnswer(given: false))]
        await model.loadSettings()
        try expectEqual(model.consent?.given, false)
        model.askConsent()
        try expectEqual(model.consentAsked?.version, "1")
        model.notNowAI()
        try expectEqual(model.consentAsked, nil)
        let sent = cloud.sent.count
        model.askConsent()
        cloud.answers = [(200, try consentAnswer(given: true))]
        await model.allowAI(words: words)
        try expectEqual(cloud.sent.count, sent + 1)
        try expectEqual(cloud.sent.last.map { $0.method + " " + $0.path }, "POST /v1/me/ai-consent")
        try expectEqual(model.consent?.given, true)
        try expectEqual(model.consentAsked, nil)
    }),
    Test("a zone chosen is confirmed, saved to KIFF signed, and who is signed in read again", awaiting: { @MainActor in
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        var asked: [String] = []
        let (model, kiff, cloud) = try await owner(confirm: { asked.append($0) })
        kiff.answers = [(200, #"{"time_zone":"Europe/London"}"#), (200, meOwner.replacingOccurrences(of: "Europe/Paris", with: "Europe/London"))]
        cloud.answers = [(200, #"{"time_zone":"Europe/London","updated":1}"#)]
        await model.saveZone("Europe/London", words: words)
        try expectEqual(asked, ["Set your account's time zone to Europe/London"])
        try expectEqual(Array(kiff.sent.suffix(2)).map { $0.method + " " + $0.path }, ["PUT /v1/me/time-zone", "GET /v1/me"])
        try expectEqual(kiff.sent.suffix(2).first?.headers["KIFF-Device-Signature"], "t=1,v1=SIG")
        try expectEqual(cloud.sent.last.map { $0.method + " " + $0.path }, "POST /v1/account/time-zone")
        try expectEqual(model.zone, "Europe/London")
        try expectEqual(model.zoneError, nil)
        try expectEqual(model.savingZone, false)
    }),
    Test("the screenshots: Account, the KIFF account page and the zone picker, light and dark", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pages: [(String, [AccountPage], CGFloat)] = [("account-settings", [], 2100), ("account-kiff", [.kiffAccount], 900), ("account-zone", [.kiffAccount, .timeZone], 700)]
        for (name, opened, height) in pages {
            for dark in [false, true] {
                // A model of its own for each: drawing reads again (its `.task`), from answers of its own.
                let (model, _, _) = try await owner()
                let devices = DevicesModel(account: AccountClient(transport: CannedTransport([]), session: session))
                let exportChats = ExportChatsModel(cloud: CloudClient(transport: CannedTransport([]), session: session))
                // People & groups and Alerts, as the iPad's Account lists them, so every row is drawn.
                let people = PeopleModel(account: AccountClient(transport: CannedTransport([]), session: session))
                let alerts = AlertsModel(account: "t-shot", defaults: UserDefaults(suiteName: "tafs.tests.\(UUID().uuidString)")!)
                let view = AccountView(model: model, devices: devices, people: people, exportChats: exportChats, alerts: alerts,
                                       open: { _ in }, addThisMac: {}, mayUseCoach: true, signOut: {}, pages: opened)
                    .environment(\.words, Words.load(folder: strings, preferred: ["en"]))
                guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: height), dark: dark), let png = Snapshot.png(bitmap) else {
                    throw Failure(description: "no PNG")
                }
                try png.write(to: folder.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            }
        }
    }),
]

private let balanceLine = #"{"balance":{"state":"ok","meter_pct":null,"words":"No limit · 2,231 credits used"},"plan_line":"Solo · renews 1 December","plan_tone":"warning"}"#

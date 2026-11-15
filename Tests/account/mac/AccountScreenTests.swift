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
    Test("the screenshots: Account in three languages, view-only and not", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (language, me, name) in [("en", meView, "account-view-only-en"), ("en", mePasskey, "account-en"), ("fr", mePasskey, "account-fr"), ("pt", mePasskey, "account-pt")] {
            let model = make([(200, me)], [(200, balanceLine)], defaults: scratchDefaults())
            await model.load()
            let devices = DevicesModel(account: AccountClient(transport: CannedTransport([]), session: session))
            let view = AccountView(model: model, devices: devices, open: { _ in }, addThisMac: {}, signOut: {})
                .environment(\.words, Words.load(folder: strings, preferred: [language]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 900)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }),
]

private let balanceLine = #"{"balance":{"state":"ok","meter_pct":null,"words":"No limit · 2,231 credits used"},"plan_line":"Solo · renews 1 December","plan_tone":"warning"}"#

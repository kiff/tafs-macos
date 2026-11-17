import Foundation
import SwiftUI
import UserNotifications

/// macOS's answer, as a test gives it.
private final class FakePermission: AlertPermission {
    var granted: Bool
    var asked = 0
    init(_ granted: Bool) { self.granted = granted }
    func allowed() async -> Bool { granted }
    func ask() async -> Bool { asked += 1; return granted }
}

private func scratch() -> (UserDefaults, String) {
    let name = "tafs.tests.\(UUID().uuidString)"
    return (UserDefaults(suiteName: name)!, name)
}

let accountAlertsTests: [Test] = [
    Test("alerts turn on only once macOS allows them; refused, they say so and stay off", awaiting: { @MainActor in
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        let (defaults, name) = scratch()
        defer { defaults.removePersistentDomain(forName: name) }
        let refused = FakePermission(false)
        let model = AlertsModel(account: "t-a", defaults: defaults, permission: refused)
        await model.refresh()
        try expectEqual(model.on, false)
        await model.turnOn(words: words)
        try expectEqual(refused.asked, 1)
        try expectEqual(model.on, false)
        try expectEqual(model.why, "Allow notifications for tafs in Settings, then try again.")
        try expectEqual(AlertPrefs(defaults: defaults, account: "t-a").on, false)
        refused.granted = true
        await model.turnOn(words: words)
        try expectEqual(model.on, true)
        try expectEqual(model.why, nil)
        try expectEqual(AlertPrefs(defaults: defaults, account: "t-a").on, true)
        // Another account starts from its own state.
        let other = AlertsModel(account: "t-b", defaults: defaults, permission: refused)
        await other.refresh()
        try expectEqual(other.on, false)
        model.turnOff()
        try expectEqual(model.on, false)
    }),
    Test("with Sound off an alert arrives quietly, in the list only; with Sound on, a banner with sound") {
        try expectEqual(Notifier.presentation(plays: true), [.banner, .sound])
        try expectEqual(Notifier.presentation(plays: false), [.list])
        try expectEqual(Notifier.interruption(plays: true), .active)
        try expectEqual(Notifier.interruption(plays: false), .passive)
    },
    Test("the screenshots: Alerts in three languages, on and with sound off", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let (defaults, name) = scratch()
        defer { defaults.removePersistentDomain(forName: name) }
        AlertPrefs(on: true, sound: false).save(to: defaults, account: "t-a")
        let model = AlertsModel(account: "t-a", defaults: defaults, permission: FakePermission(true))
        await model.refresh()
        for language in ["en", "fr", "pt"] {
            let view = AlertsView(model: model).environment(\.words, Words.load(folder: strings, preferred: [language]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 600)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("alerts-\(language).png"))
        }
    }),
    Test("the screenshots: Alerts with each switch at its row's end, light and dark", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let (defaults, name) = scratch()
        defer { defaults.removePersistentDomain(forName: name) }
        AlertPrefs(on: true, sound: true).save(to: defaults, account: "t-a")
        let model = AlertsModel(account: "t-a", defaults: defaults, permission: FakePermission(true))
        await model.refresh()
        for dark in [false, true] {
            let view = AlertsView(model: model).environment(\.words, Words.load(folder: strings, preferred: ["en"]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 600), dark: dark), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("alerts-switches-\(dark ? "dark" : "light").png"))
        }
    }),
]

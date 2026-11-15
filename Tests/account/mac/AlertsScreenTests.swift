import Foundation
import SwiftUI

let accountAlertsTests: [Test] = [
    Test("the screenshots: Alerts in three languages, on and with sound off", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "tafs.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { throw Failure(description: "no defaults") }
        defer { defaults.removePersistentDomain(forName: name) }
        AlertPrefs(on: true, sound: false).save(to: defaults)
        for language in ["en", "fr", "pt"] {
            let view = AlertsView(defaults: defaults).environment(\.words, Words.load(folder: strings, preferred: [language]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 600)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("alerts-\(language).png"))
        }
    }),
]

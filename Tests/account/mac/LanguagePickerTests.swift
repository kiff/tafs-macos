import Foundation
import SwiftUI

private let strings = URL(fileURLWithPath: ".shared/app/strings")

private func scratch() -> UserDefaults {
    let name = "tafs.tests.picker.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

let accountLanguageTests: [Test] = [
    Test("the list is every shipped language by its own name, the chosen one marked", awaiting: { @MainActor in
        let shipped = try Words.shipped(folder: strings)
        let fr = Words.load(folder: strings, preferred: ["fr"], chosen: nil)
        let rows = LanguageRows.rows(chosen: "pl", shipped: shipped, words: fr)
        let languages = rows.filter { $0.code != nil }
        try expectEqual(languages.map(\.code), shipped.map { Optional($0) })
        try expectEqual(languages.first { $0.code == "de" }?.title, "Deutsch")
        try expectEqual(languages.first { $0.code == "pl" }?.title, "Polski")
        try expectEqual(rows.filter(\.current).map(\.code), [Optional("pl")])
    }),
    Test("with no choice, the Mac's own language row is marked, or the language in use when its line isn't at the pin yet", awaiting: { @MainActor in
        let shipped = try Words.shipped(folder: strings)
        let en = Words.load(folder: strings, preferred: ["en"], chosen: nil)
        let rows = LanguageRows.rows(chosen: nil, shipped: shipped, words: en)
        if en.lines["settings.language_device"] != nil {
            try expectEqual(rows.first?.code, nil)
            try expectEqual(rows.filter(\.current).map(\.id), ["device"])
        } else {
            try expectEqual(rows.contains { $0.code == nil }, false)
            try expectEqual(rows.filter(\.current).map(\.code), [Optional("en")])
        }
        // A kept code that's no longer shipped counts as no choice.
        try expectEqual(LanguageRows.rows(chosen: "ja", shipped: shipped, words: en).filter(\.current).count, 1)
    }),
    Test("choosing a language keeps it for this Mac and reads the words again at once, and nil goes back to the Mac's", awaiting: { @MainActor in
        let defaults = scratch()
        let language = AppLanguage(defaults: defaults, folder: strings, preferred: ["en"])
        try expectEqual(language.words.language, "en")
        try expectEqual(language.chosen, nil)
        language.choose("fr", during: "tok")
        try expectEqual(language.words.language, "fr")
        try expectEqual(language.words("settings.language_title"), "Langue")
        try expectEqual(Words.app.language, "fr")
        try expectEqual(LanguageChoice.saved(defaults), "fr")
        try expectEqual(language.changedIn, "tok")
        // The next launch reads it back.
        try expectEqual(AppLanguage(defaults: defaults, folder: strings, preferred: ["en"]).words.language, "fr")
        language.chooser(session: "tok").choose(nil)
        try expectEqual(language.words.language, "en")
        try expectEqual(LanguageChoice.saved(defaults), nil)
        Words.app = Words.load(folder: strings, preferred: ["en"], chosen: nil)
    }),
    Test("the screenshots: Account › Language in English and French", awaiting: { @MainActor in
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let shipped = try Words.shipped(folder: strings)
        for (language, chosen) in [("en", nil), ("fr", Optional("fr"))] as [(String, String?)] {
            let view = LanguagePickerView()
                .environment(\.words, Words.load(folder: strings, preferred: [language], chosen: chosen))
                .environment(\.languageChooser, LanguageChooser(chosen: chosen, shipped: shipped) { _ in })
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 700, height: 760)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("account-language-\(language).png"))
        }
    }),
]

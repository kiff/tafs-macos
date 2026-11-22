import SwiftUI

/// The app's language on this Mac: the one chosen in Account › Language (`LanguageChoice`),
/// else the Mac's own. Choosing one applies it at once: the words are read again, and the
/// signed-in window is rebuilt on Account, so every client is made again and every request's
/// `Accept-Language` follows. No relaunch.
@MainActor
final class AppLanguage: ObservableObject {
    @Published private(set) var words: Words
    @Published private(set) var chosen: String?
    /// The session the language was last changed in: its window opens on Account again.
    @Published private(set) var changedIn: String?
    let shipped: [String]
    private let defaults: UserDefaults
    private let folder: URL?
    private let preferred: [String]

    init(defaults: UserDefaults = .standard, folder: URL? = Words.bundleFolder, preferred: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        self.folder = folder
        self.preferred = preferred
        let chosen = LanguageChoice.saved(defaults)
        self.chosen = chosen
        shipped = folder.flatMap { try? Words.offered(folder: $0) } ?? ["en"]
        words = Words.load(folder: folder, preferred: preferred, chosen: chosen)
        Words.app = words
    }

    /// Keeps the choice (nil: the Mac's own language) and applies it now.
    func choose(_ code: String?, during session: String?) {
        LanguageChoice.save(code, defaults)
        chosen = code
        words = Words.load(folder: folder, preferred: preferred, chosen: code)
        Words.app = words
        changedIn = session
    }

    /// What Account's language page needs: the choice, the languages, and how to choose.
    func chooser(session: String?) -> LanguageChooser {
        LanguageChooser(chosen: chosen, shipped: shipped) { [weak self] code in self?.choose(code, during: session) }
    }
}

/// Account › Language's choice, handed down the window. Nil (a test, a preview) shows the
/// list but changes nothing.
struct LanguageChooser {
    let chosen: String?
    let shipped: [String]
    let choose: (String?) -> Void
}

private struct LanguageChooserKey: EnvironmentKey {
    static let defaultValue: LanguageChooser? = nil
}

extension EnvironmentValues {
    var languageChooser: LanguageChooser? {
        get { self[LanguageChooserKey.self] }
        set { self[LanguageChooserKey.self] = newValue }
    }
}

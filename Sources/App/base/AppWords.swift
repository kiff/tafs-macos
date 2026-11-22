import AppKit
import SwiftUI

extension Words {
    /// The shared words in the app's bundle.
    static var bundleFolder: URL? { Bundle.main.resourceURL?.appendingPathComponent("strings") }

    /// The words in the app's bundle, in the language chosen for this Mac (Account › Language)
    /// when it's shipped, else the first the person prefers that is shipped. With no bundle (a
    /// test), `folder` says where they are.
    static func load(folder: URL? = bundleFolder, preferred: [String] = Locale.preferredLanguages,
                     chosen: String? = LanguageChoice.saved(.standard)) -> Words {
        guard let folder, let shipped = try? Words.shipped(folder: folder) else { return Words(language: "en", lines: [:]) }
        let language = LanguageChoice.language(chosen: chosen, preferred: preferred, shipped: shipped)
        return (try? Words(language: language, folder: folder)) ?? Words(language: "en", lines: [:])
    }

    /// The app's words where no view hands them over: a model's line for a refusal, as the
    /// iPad's `Words.line`. Set once at launch, and by the test runner on a Mac (English):
    /// unset, a line reads as its key.
    static var app = Words(language: "en", lines: [:])
}

private struct WordsKey: EnvironmentKey {
    static let defaultValue = Words(language: "en", lines: [:])
}

extension EnvironmentValues {
    /// The app's words, for every view: `words("needs_you.title")`.
    var words: Words {
        get { self[WordsKey.self] }
        set { self[WordsKey.self] = newValue }
    }
}

extension View {
    /// The app's words, and the direction and locale that go with their language: Arabic (and any
    /// language in `Words.rightToLeft`) mirrors the view, as the iPad's does, and dates and numbers
    /// follow the app's language, not only the Mac's. The window and the screenshot tests both use it.
    func inLanguage(_ words: Words) -> some View {
        environment(\.words, words)
            .environment(\.layoutDirection, words.isRightToLeft ? .rightToLeft : .leftToRight)
            .environment(\.locale, Locale(identifier: words.language))
    }
}

/// The tafs mascot, from the app's bundle, or from `Mascot.folder` in a test.
struct Mascot: View {
    static var file = Bundle.main.resourceURL?.appendingPathComponent("mascot.png")
    var size: CGFloat = 40

    var body: some View {
        if let file = Self.file, let image = NSImage(contentsOf: file) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
        } else {
            Circle().fill(Theme.brand).frame(width: size, height: size).accessibilityHidden(true)
        }
    }
}

import AppKit
import SwiftUI

extension Words {
    /// The words in the app's bundle, in the first language the person prefers that is
    /// shipped. With no bundle (a test), `folder` says where they are.
    static func load(folder: URL? = Bundle.main.resourceURL?.appendingPathComponent("strings"),
                     preferred: [String] = Locale.preferredLanguages) -> Words {
        guard let folder, let shipped = try? Words.shipped(folder: folder) else { return Words(language: "en", lines: [:]) }
        let language = Words.language(preferred: preferred, shipped: shipped)
        return (try? Words(language: language, folder: folder)) ?? Words(language: "en", lines: [:])
    }

    /// The app's words where no view hands them over: a model's line for a refusal, as the
    /// iPad's `Words.line`. Set once at launch.
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

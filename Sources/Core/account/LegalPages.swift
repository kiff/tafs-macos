import Foundation

/// tafs's own Terms and Privacy policy on kiff.dev, in the app's language where kiff.dev has them,
/// else in English. The English pages govern.
enum LegalPages {
    /// The languages kiff.dev has the pages in, besides English, at `kiff.dev/<lang>/tafs/…`.
    static let languages: Set<String> = ["de", "es", "fr", "it", "nl", "pl", "pt"]

    /// The Terms, in `language` where kiff.dev has them, else in English (no `/en/`).
    static func terms(_ language: String) -> String { page("terms", language) }

    /// The Privacy policy, in `language` where kiff.dev has it, else in English.
    static func privacy(_ language: String) -> String { page("privacy", language) }

    /// Whether a link's label says the page is in English: only in a language kiff.dev has no
    /// page in. English itself never says so.
    static func saysEnglish(_ language: String) -> Bool {
        language != "en" && !languages.contains(language)
    }

    private static func page(_ name: String, _ language: String) -> String {
        languages.contains(language) ? "https://kiff.dev/\(language)/tafs/\(name)" : "https://kiff.dev/tafs/\(name)"
    }
}

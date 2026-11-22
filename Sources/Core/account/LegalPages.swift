import Foundation

/// tafs's Terms and Privacy policy on kiff.dev, as the iPad's `Legal` (kiff/tafs
/// `ios/Tafs/Design/Components.swift`) opens them.
enum LegalPages {
    /// The languages kiff.dev serves the pages in, besides English, at `kiff.dev/<lang>/tafs/…`: the iPad's
    /// `Legal.translated`, one for one. Traditional Chinese is served under `/zh/`, Serbian in Latin script under `/sr/`
    /// and Brazilian Portuguese under `/pt/` (`site`).
    static let languages: Set<String> = ["de", "es", "fr", "it", "nl", "pl", "pt", "ko", "ja", "et", "lt", "lv", "cs", "sk", "sl",
                                         "hu", "ro", "bg", "hr", "tr", "id", "vi", "th", "zh", "ar", "sr", "sq", "ka", "hy", "az", "bn", "he"]

    /// The Terms, in `language` where kiff.dev has them, else in English (no `/en/`).
    static func terms(_ language: String) -> String { page("terms", language) }

    /// The Privacy policy, in `language` where kiff.dev has it, else in English.
    static func privacy(_ language: String) -> String { page("privacy", language) }

    /// KIFF's own Terms of Service, beside tafs's: `kiff.dev/<lang>/terms`, as the iPad's `Legal.kiffTerms`.
    static func kiffTerms(_ language: String) -> String { kiffPage("terms", language) }

    /// KIFF's own Privacy Policy: `kiff.dev/<lang>/privacy`, as the iPad's `Legal.kiffPrivacy`.
    static func kiffPrivacy(_ language: String) -> String { kiffPage("privacy", language) }

    /// Whether a link's label says the page is in English: only in a language kiff.dev has no
    /// page in. English itself never says so.
    static func saysEnglish(_ language: String) -> Bool {
        language != "en" && !languages.contains(site(language))
    }

    /// The app's language as kiff.dev names it: "zh" for Traditional Chinese, "sr" for Serbian in Latin script, "pt" for
    /// Brazilian Portuguese, as the iPad's `Legal.language`.
    static func site(_ language: String) -> String {
        switch language {
        case "zh-Hant": return "zh"
        case "sr-Latn": return "sr"
        case "pt-BR": return "pt"
        default: return language
        }
    }

    private static func kiffPage(_ name: String, _ language: String) -> String {
        let site = site(language)
        return languages.contains(site) ? "https://kiff.dev/\(site)/\(name)" : "https://kiff.dev/\(name)"
    }

    private static func page(_ name: String, _ language: String) -> String {
        let site = site(language)
        return languages.contains(site) ? "https://kiff.dev/\(site)/tafs/\(name)" : "https://kiff.dev/tafs/\(name)"
    }
}

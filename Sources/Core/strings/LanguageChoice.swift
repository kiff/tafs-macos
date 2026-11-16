import Foundation

/// The language a person chose for tafs on this Mac, in the app's own list (Account ›
/// Language), kept per Mac. Nil follows the Mac's own preferred languages, as before. It's
/// a choice among the shipped languages only: anything else kept reads as no choice.
enum LanguageChoice {
    /// Where the choice is kept, beside the theme's.
    static let key = "tafs.language"

    /// The kept choice, or nil for the Mac's own language.
    static func saved(_ defaults: UserDefaults) -> String? {
        defaults.string(forKey: key)
    }

    /// Keeps a choice; nil goes back to the Mac's own language.
    static func save(_ code: String?, _ defaults: UserDefaults) {
        if let code { defaults.set(code, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    /// The language the app is in: the chosen one when it's shipped, else the first the
    /// person prefers that is shipped (`Words.language`), else English. A kept code that's no
    /// longer shipped falls back, so a stale choice never leaves the app without words.
    static func language(chosen: String?, preferred: [String], shipped: [String]) -> String {
        if let chosen, shipped.contains(chosen) { return chosen }
        return Words.language(preferred: preferred, shipped: shipped)
    }
}

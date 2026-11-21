import Foundation

/// What Account's Language and About sections say about the app itself.
enum AppInfo {
    /// "0.1 (1)": the version and its build, as the iPad shows them; the version alone when
    /// there is no build, and "–" when the bundle names neither.
    static func version(_ info: [String: Any]) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? "–"
        guard let build = info["CFBundleVersion"] as? String, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }

    /// A language by its own name, capitalised as that language does ("Français",
    /// "Português"), as the iPad's `AppLanguage.name`.
    static func languageName(_ code: String) -> String {
        let locale = Locale(identifier: code)
        // A regional variant is named with its region ("Português (Brasil)"), as the other apps name it.
        let name = (code.contains("-") ? locale.localizedString(forIdentifier: code) : locale.localizedString(forLanguageCode: code)) ?? code
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }
}

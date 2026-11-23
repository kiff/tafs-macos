import Foundation

/// How tafs works' help sections, as the iPad's `HowTafsWorksView` at the pin (kiff/tafs `ios/Tafs/Views/OnboardingCards.swift`,
/// tafs#1758) and Linux's security-key section (tafs#1848), in the shared `help.*` lines. The app says nothing about what
/// the person can't use here:
/// - **Chrome**, only once planque offers this person Chromes (Account › Chrome shows), as the iPad's `model.chromes != nil`.
/// - **The emailed code** never: the iPad shows it where KIFF can send one, and points to Account › Sign in with a code,
///   a setting this Mac doesn't have. It shows here once that setting does.
/// - **The security key**, while this Mac approves with one (`Features.macPasskeyApprovals`): it says what key, that
///   an ordinary USB stick won't do, and that without one this Mac only views.
enum HelpSections {
    enum Section: String, CaseIterable {
        case chrome
        case securityKey = "security_key"

        /// Its title, its lead, and its second line, filled with the screens they name in the person's language.
        func lines(_ words: Words) -> (title: String, lead: String, more: String) {
            switch self {
            case .chrome:
                return (words("help.chrome_title"),
                        words("help.chrome_lead", ["needs_you": words("needs_you.title")]),
                        words("help.chrome_manage", ["account": words("settings.title"), "chrome": words("chrome.title")]))
            case .securityKey:
                return (words("help.security_key_title"), words("help.security_key_lead"), words("help.security_key_use"))
            }
        }
    }

    /// The sections shown, in the order drawn: Chrome's first, as the iPad's.
    static func shown(chromeOffered: Bool, securityKey: Bool = Features.macPasskeyApprovals) -> [Section] {
        (chromeOffered ? [.chrome] : []) + (securityKey ? [.securityKey] : [])
    }
}

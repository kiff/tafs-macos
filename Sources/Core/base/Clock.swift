import Foundation

/// The clock a time of day is drawn on: this Mac's 12- or 24-hour setting, in the app language's own pattern, as the
/// iPad's `ChatTime` and Android's `shortTime` (kiff/tafs#2195, #2196). One clock for every time the app draws, so a
/// conversation never shows "10:22 PM" beside "22:22".
///
/// The app draws in its own language (`AppDates.locale`), not this Mac's, and a locale built from a language never
/// carries this Mac's 24-hour setting, so a style's time follows the language's default instead. A locale's hour-cycle
/// keyword (`@hours=h23`, `-u-hc-h23`) is ignored by the styles (checked on macOS 12), so the time part is drawn from
/// a template ("Hmm", "hmm"), which honours it, in the language's own pattern ("22.22" in Finnish, "午後10:22" in
/// Japanese).
enum Clock {
    /// Whether a locale's own hour is 24-hour: its "j" skeleton has no day period.
    static func twentyFour(_ locale: Locale) -> Bool {
        !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "H").contains("a")
    }

    /// This Mac's own setting: `Locale.current` carries the 24-hour choice made in System Preferences.
    static var macTwentyFour: Bool { twentyFour(.current) }

    /// The time-of-day pattern in a language, on the clock asked for: hours and minutes for a short time, with seconds
    /// for a medium one; nil for a style this doesn't redraw (none, or long and full, which name the zone).
    static func pattern(_ style: DateFormatter.Style, locale: Locale, twentyFour: Bool) -> String? {
        let template: String
        switch style {
        case .short: template = twentyFour ? "Hmm" : "hmm"
        case .medium: template = twentyFour ? "Hmmss" : "hmmss"
        default: return nil
        }
        return DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: locale)
    }

    /// A styled format with its time part on the clock asked for: the locale's own pattern for that time style is
    /// swapped for `pattern`'s, and the date part and the words joining them stay as the style wrote them. A format
    /// with no such time part, or whose time is already on that clock, comes back as it is.
    static func swapTime(in format: String, style: DateFormatter.Style, locale: Locale, twentyFour: Bool) -> String {
        guard let want = pattern(style, locale: locale, twentyFour: twentyFour) else { return format }
        let own = DateFormatter()
        own.locale = locale
        own.dateStyle = .none
        own.timeStyle = style
        guard let have = own.dateFormat, !have.isEmpty, have != want, format.contains(have) else { return format }
        return format.replacingOccurrences(of: have, with: want)
    }
}

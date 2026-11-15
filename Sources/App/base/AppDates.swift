import Foundation

/// Dates and times as the app shows them: in the app's language, the words' own, never this
/// Mac's. A Mac set to Spanish that shows the app in English reads English dates, as the iPad's
/// formatters in its app language.
enum AppDates {
    /// The app's language with this Mac's region, as the iPad's `Locale.current` with a per-app
    /// language (Components.swift:269-278): an English app on a British Mac reads "15 Nov" and
    /// 14:05. `region` is this Mac's unless given (tests pin it).
    static func locale(_ words: Words, region: String? = Locale.current.regionCode) -> Locale {
        guard let region, !region.isEmpty else { return Locale(identifier: words.language) }
        return Locale(identifier: words.language + "_" + region)
    }

    /// A formatter in the app's language and this Mac's region, in a style and, when given, a zone.
    static func formatter(_ words: Words, date: DateFormatter.Style = .none, time: DateFormatter.Style = .none,
                          zone: TimeZone? = nil, region: String? = Locale.current.regionCode) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale(words, region: region)
        formatter.dateStyle = date
        formatter.timeStyle = time
        if let zone { formatter.timeZone = zone }
        return formatter
    }

    /// A fixed format ("HH:mm") that no language or Mac setting changes: a 24-hour clock stays one.
    static func fixed(_ format: String, zone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        formatter.timeZone = zone
        return formatter
    }
}

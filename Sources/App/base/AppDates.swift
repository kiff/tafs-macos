import Foundation

/// Dates and times as the app shows them: in the app's language, the words' own, never this
/// Mac's. A Mac set to Spanish that shows the app in English reads English dates, as the iPad's
/// formatters in its app language.
enum AppDates {
    /// A formatter in the words' language, in a style and, when given, a zone.
    static func formatter(_ words: Words, date: DateFormatter.Style = .none, time: DateFormatter.Style = .none,
                          zone: TimeZone? = nil) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: words.language)
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

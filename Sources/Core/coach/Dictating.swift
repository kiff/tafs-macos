import Foundation

/// A language this Mac recognizes on the device, by its locale ("fr-FR", "es-CO"), as the
/// iPad's `Dictation.Language` (Services/Dictation.swift:21-81): any it has, not a fixed list.
struct DictationLanguage: Hashable {
    let id: String

    static let english = DictationLanguage(id: "en-US")
    static let spanish = DictationLanguage(id: "es-ES")

    var code: String { String(id.prefix { $0 != "-" && $0 != "_" }).lowercased() }
    /// The switch's label: "FR".
    var label: String { code.uppercased() }
    /// Its own name, as its speakers write it: "Français", "Español", "English".
    var name: String {
        let own = Locale(identifier: id).localizedString(forLanguageCode: code) ?? code
        return own.prefix(1).uppercased() + own.dropFirst()
    }

    /// The device's languages, one form each, the person's first: for each of their preferred
    /// languages, the form they use when the device has it, else another of that language; then
    /// the rest, by code. `supported` are the forms the device recognizes on the device.
    static func ordered(supported: [String], preferred: [String] = Locale.preferredLanguages) -> [DictationLanguage] {
        let have = supported.map { $0.replacingOccurrences(of: "_", with: "-") }
        var out: [DictationLanguage] = []
        func add(_ id: String) {
            let l = DictationLanguage(id: id)
            if !out.contains(where: { $0.code == l.code }) { out.append(l) }
        }
        for p in preferred.map({ $0.replacingOccurrences(of: "_", with: "-") }) {
            let code = DictationLanguage(id: p).code
            if let exact = have.first(where: { $0.caseInsensitiveCompare(p) == .orderedSame }) {
                add(exact)
            } else if let same = bestForm(of: code, among: have) {
                add(same)
            }
        }
        for id in have.sorted() { add(id) }
        return out
    }

    /// The form of a language to dictate in when the person's own isn't on the device: for
    /// English, British then American; for another language, its own country's (fr-FR, de-DE);
    /// else the first of its forms, alphabetically.
    static func bestForm(of code: String, among have: [String]) -> String? {
        let forms = have.filter { DictationLanguage(id: $0).code == code }.sorted()
        let preferred = code == "en" ? ["en-GB", "en-US"] : ["\(code)-\(code.uppercased())"]
        for p in preferred {
            if let f = forms.first(where: { $0.caseInsensitiveCompare(p) == .orderedSame }) { return f }
        }
        return forms.first
    }

    /// The person's own languages among them, theirs first: their keyboards, then the device's
    /// languages. All of the device's when none of theirs is there.
    static func owners(supported: [String], keyboards: [String], preferred: [String] = Locale.preferredLanguages) -> [DictationLanguage] {
        let theirs = keyboards + preferred
        let codes = Set(theirs.map { DictationLanguage(id: $0.replacingOccurrences(of: "_", with: "-")).code })
        let all = ordered(supported: supported, preferred: theirs)
        let mine = all.filter { codes.contains($0.code) }
        return mine.isEmpty ? all : mine
    }
}

/// How dictated words go into the message box, as the iPad's `Dictation` statics
/// (Services/Dictation.swift:126-133, 300-361): nothing here listens or sends.
enum Dictating {
    /// The language dictation starts in: the one last switched to with the chip, when the device
    /// still has it; else the app's language, in the form the device has; else the device's first.
    static func starting(have: [DictationLanguage], last: String?, app: String) -> DictationLanguage? {
        if let last, let chosen = have.first(where: { $0.id == last }) { return chosen }
        let code = DictationLanguage(id: app).code
        return have.first { $0.code == code } ?? have.first
    }

    /// Whether the recognizer's text starts a new stretch rather than revising the one being
    /// heard: shorter, and not beginning with the same word. A revision ("refund ten" to
    /// "refund 10") keeps its start.
    static func startsAfresh(_ was: String, _ now: String) -> Bool {
        let first = { (s: String) in s.split(separator: " ").first.map { $0.lowercased() } }
        guard let a = first(was) else { return false }
        return now.count < was.count && first(now) != a
    }

    /// How loud a stretch of sound is, 0 to 1: its root mean square in decibels, from a quiet
    /// room (-50 dB) to speech up close (-10 dB).
    static func level(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for x in samples { sum += x * x }
        let db = 20 * log10(max(sqrtf(sum / Float(samples.count)), 1e-7))
        return max(0, min(1, (db + 50) / 40))
    }

    /// The box's text before dictation, then what was heard, with one space between.
    static func joined(_ before: String, _ heard: String) -> String {
        let words = heard.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return before }
        guard !before.isEmpty else { return words }
        return before.last?.isWhitespace == true ? before + words : before + " " + words
    }

    /// The box split at its insertion point: the words heard go between the two. No point, or
    /// one past the end, is the end.
    static func split(_ text: String, at cursor: Int?) -> (String, String) {
        guard let cursor, cursor >= 0, cursor < text.count else { return (text, "") }
        let i = text.index(text.startIndex, offsetBy: cursor)
        return (String(text[..<i]), String(text[i...]))
    }

    /// What was after the insertion point, after the words heard: one space between, unless it
    /// starts with a space or closes the sentence.
    static func rest(_ after: String) -> String {
        guard let first = after.first else { return "" }
        return first.isWhitespace || ".,;:!?)".contains(first) ? after : " " + after
    }

    /// The hints, each once, without blanks, at most 100: the recognizer weighs fewer better.
    static func cleaned(_ hints: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for h in hints {
            let t = h.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, seen.insert(t.lowercased()).inserted else { continue }
            out.append(t)
            if out.count == 100 { break }
        }
        return out
    }

    /// The words the person is likely to say, so dictation spells them right, as the iPad's
    /// `dictationHints` (AppModel.swift:9221-9231): the app's own names, then each taf's name.
    static func hints(tafs: [String]) -> [String] {
        cleaned(["tafs", "Coach", "KIFF", "Solo", "Team", "Company"] + tafs)
    }
}

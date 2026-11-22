import Foundation

/// The app's own words in one language, each by its shared key, as kiff/tafs writes them in
/// `app/strings/<lang>/*.json` at the pinned commit (docs/shared.md). Nothing is worded here.
struct Words {
    /// A line as its file has it: one text, or a count's text for each plural form.
    enum Line: Decodable, Equatable {
        case text(String)
        case forms([String: String])

        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let text = try? value.decode(String.self) { self = .text(text) } else { self = .forms(try value.decode([String: String].self)) }
        }
    }

    let language: String
    let lines: [String: Line]

    init(language: String, lines: [String: Line]) {
        self.language = language
        self.lines = lines
    }

    /// Reads a language's lines from the shared folder (`app/strings`): every file of `<language>/`. A regional
    /// variant (`languages.json`'s "variants": "pt-BR" over "pt") is its base's lines with its own on top, as
    /// kiff/tafs's apps read it: it holds only the lines that read differently there.
    init(language: String, folder: URL) throws {
        var lines: [String: Line] = [:]
        if let base = try Self.variants(folder: folder)[language] {
            lines = try Self.read(base, folder: folder)
        }
        lines.merge(try Self.read(language, folder: folder)) { _, own in own }
        self.init(language: language, lines: lines)
    }

    private static func read(_ language: String, folder: URL) throws -> [String: Line] {
        let files = try FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent(language), includingPropertiesForKeys: nil)
        var lines: [String: Line] = [:]
        for file in files where file.pathExtension == "json" {
            let read = try JSONDecoder().decode([String: Line].self, from: Data(contentsOf: file))
            lines.merge(read) { first, _ in first }
        }
        return lines
    }

    /// The languages the apps ship, as `languages.json` lists them.
    static func shipped(folder: URL) throws -> [String] {
        struct Languages: Decodable { let shipped: [String] }
        return try JSONDecoder().decode(Languages.self, from: Data(contentsOf: folder.appendingPathComponent("languages.json"))).shipped
    }

    /// The languages written right to left, by their language code. The window mirrors for them.
    static let rightToLeft: Set<String> = ["ar", "he", "fa", "ur", "dv"]

    /// Whether this language is written right to left.
    var isRightToLeft: Bool { Self.rightToLeft.contains(String(language.split(separator: "-").first ?? "")) }

    /// Each regional variant's base, as `languages.json` lists them ("pt-BR": "pt"); none when it lists none.
    static func variants(folder: URL) throws -> [String: String] {
        struct Languages: Decodable { let variants: [String: String]? }
        return try JSONDecoder().decode(Languages.self, from: Data(contentsOf: folder.appendingPathComponent("languages.json"))).variants ?? [:]
    }

    /// The language the app is in: the first the person prefers that is shipped, as its regional variant when that's
    /// shipped ("pt-BR"), else its language ("pt-PT" reads "pt", "fr-FR" reads "fr"); else English.
    static func language(preferred: [String], shipped: [String]) -> String {
        for tag in preferred {
            let parts = tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
            let code = parts.first?.lowercased() ?? ""
            if parts.count > 1, parts[1].count == 2, shipped.contains(code + "-" + parts[1].uppercased()) {
                return code + "-" + parts[1].uppercased()
            }
            if shipped.contains(code) { return code }
        }
        return "en"
    }

    /// A line by its key, with its values by name. A key that isn't in the files answers the
    /// key itself; a test fails for any key the code names that English lacks.
    func callAsFunction(_ key: String, _ values: [String: String] = [:]) -> String {
        guard case .text(let text)? = lines[key] else { return key }
        return fill(text, values)
    }

    /// A count's line: the plural form its number takes in this language, else `other`. The
    /// number is the line's `{count}`, written as the language writes it.
    func count(_ key: String, _ count: Int, _ values: [String: String] = [:]) -> String {
        guard case .forms(let forms)? = lines[key],
              let text = forms[Plural.form(count, language: language)] ?? forms["other"] else { return key }
        var all = values
        all["count"] = number(count)
        return fill(text, all)
    }

    /// A number as this language writes it: 1,000, 1.000, 1 000.
    func number(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: language)
        return formatter.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// Names as this language lists them: "Refunds and Invoices", "Refunds et Invoices". Where
    /// the system has no list formatter (Linux), joined with commas.
    func list(_ names: [String]) -> String {
        #if canImport(Darwin)
        let formatter = ListFormatter()
        formatter.locale = Locale(identifier: language)
        return formatter.string(from: names) ?? names.joined(separator: ", ")
        #else
        return names.joined(separator: ", ")
        #endif
    }

    /// A name's possessive by the language's rule, the one in kiff/tafs's `generate.py`
    /// (`POSSESSIVE`): "Refunds'", "Rae's"; German "Klaus'", "Raes". A language with no rule
    /// keeps the name, and its lines word around it.
    static func possessive(_ name: String, language: String) -> String {
        guard let last = name.lowercased().last else { return name }
        switch language {
        case "en": return name + ("s".contains(last) ? "'" : "'s")
        case "de": return name + ("sßxz".contains(last) ? "'" : "s")
        default: return name
        }
    }

    /// "This name" by the language's rule, the one in kiff/tafs's `generate.py` (`THIS`):
    /// French "ce Mac", "cet appareil"; `capital` opens a sentence ("Cet appareil"). A language
    /// with no rule keeps the name: its lines write their own word. Right for the device kinds
    /// the apps name: it takes every h as mute and y as a vowel.
    static func demonstrative(_ name: String, language: String, capital: Bool = false) -> String {
        guard let first = name.lowercased().first else { return name }
        let word: String
        switch language {
        case "fr": word = "aeiouyhàâäéèêëîïôöùûüœæ".contains(first) ? "cet " : "ce "
        default: return name
        }
        return (capital ? word.prefix(1).uppercased() + word.dropFirst() : word) + name
    }

    /// A value as a placeholder's form asks for it: as it is, `possessive`, `this` or `This`.
    /// A form this app doesn't know gives nil, so its placeholder stays as written and the
    /// strings test that fills every line fails, rather than the word silently going missing.
    static func form(_ form: String?, of value: String, language: String) -> String? {
        switch form {
        case nil: return value
        case "possessive"?: return possessive(value, language: language)
        case "this"?: return demonstrative(value, language: language)
        case "This"?: return demonstrative(value, language: language, capital: true)
        default: return nil
        }
    }

    /// Puts each value in its `{name}`, `{name|possessive}`, `{name|this}` or `{name|This}`, in
    /// one pass: a value that holds braces is never filled again. A name with no value, or a form
    /// this app doesn't know, stays as written.
    private func fill(_ text: String, _ values: [String: String]) -> String {
        var out = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            out += rest[..<open]
            let parts = rest[rest.index(after: open)..<close].split(separator: "|", maxSplits: 1).map(String.init)
            if let name = parts.first, let value = values[name],
               let filled = Self.form(parts.count == 2 ? parts[1] : nil, of: value, language: language) {
                out += filled
            } else {
                out += rest[open...close]
            }
            rest = rest[rest.index(after: close)...]
        }
        return out + rest
    }
}

/// The plural form a whole number takes in each language the apps ship, by CLDR's cardinal rules for
/// whole numbers, the forms kiff/tafs's `generate.py` lists for each (`PLURALS`). A form a language's
/// line doesn't have reads `other` (`Words.count`).
enum Plural {
    static func form(_ n: Int, language: String) -> String {
        let n = abs(n)
        let million = n != 0 && n % 1_000_000 == 0
        let ten = n % 10, hundred = n % 100
        switch language.split(separator: "-").first.map(String.init) ?? language {
        case "fr", "pt":
            return n <= 1 ? "one" : million ? "many" : "other"
        // One form for every number.
        case "ko", "ja", "zh", "id", "vi", "th", "km", "lo", "ms":
            return "other"
        // "one" is 0 and 1.
        case "hy", "bn":
            return n <= 1 ? "one" : "other"
        // Hebrew's "many" left CLDR in 42.
        case "he":
            return n == 1 ? "one" : n == 2 ? "two" : "other"
        case "mk":
            return ten == 1 && hundred != 11 ? "one" : "other"
        case "ru", "uk":
            if ten == 1 && hundred != 11 { return "one" }
            return (2...4).contains(ten) && !(12...14).contains(hundred) ? "few" : "many"
        case "es", "it":
            return n == 1 ? "one" : million ? "many" : "other"
        case "pl":
            if n == 1 { return "one" }
            return (2...4).contains(ten) && !(12...14).contains(hundred) ? "few" : "many"
        case "cs", "sk":
            return n == 1 ? "one" : (2...4).contains(n) ? "few" : "other"
        case "hr", "sr", "bs":
            if ten == 1 && hundred != 11 { return "one" }
            return (2...4).contains(ten) && !(12...14).contains(hundred) ? "few" : "other"
        case "lt":
            if (11...19).contains(hundred) { return "other" }
            return ten == 1 ? "one" : ten >= 2 ? "few" : "other"
        case "lv":
            if ten == 0 || (11...19).contains(hundred) { return "zero" }
            return ten == 1 ? "one" : "other"
        case "sl":
            return hundred == 1 ? "one" : hundred == 2 ? "two" : (3...4).contains(hundred) ? "few" : "other"
        case "ro":
            return n == 1 ? "one" : n == 0 || (1...19).contains(hundred) ? "few" : "other"
        case "ar":
            if n == 0 { return "zero" }
            if n == 1 { return "one" }
            if n == 2 { return "two" }
            return (3...10).contains(hundred) ? "few" : (11...99).contains(hundred) ? "many" : "other"
        default:
            return n == 1 ? "one" : "other"
        }
    }
}

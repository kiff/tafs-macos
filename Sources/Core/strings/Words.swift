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

    /// Reads a language's lines from the shared folder (`app/strings`): every file of `<language>/`.
    init(language: String, folder: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent(language), includingPropertiesForKeys: nil)
        var lines: [String: Line] = [:]
        for file in files where file.pathExtension == "json" {
            let read = try JSONDecoder().decode([String: Line].self, from: Data(contentsOf: file))
            lines.merge(read) { first, _ in first }
        }
        self.init(language: language, lines: lines)
    }

    /// The languages the apps ship, as `languages.json` lists them.
    static func shipped(folder: URL) throws -> [String] {
        struct Languages: Decodable { let shipped: [String] }
        return try JSONDecoder().decode(Languages.self, from: Data(contentsOf: folder.appendingPathComponent("languages.json"))).shipped
    }

    /// The language the app is in: the first the person prefers ("pt-BR", "fr-FR") that is
    /// shipped, else English.
    static func language(preferred: [String], shipped: [String]) -> String {
        for tag in preferred {
            let code = tag.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
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

    /// Puts each value in its `{name}` or `{name|possessive}`, in one pass: a value that holds
    /// braces is never filled again. A name with no value stays as written.
    private func fill(_ text: String, _ values: [String: String]) -> String {
        var out = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            out += rest[..<open]
            let parts = rest[rest.index(after: open)..<close].split(separator: "|", maxSplits: 1).map(String.init)
            if let name = parts.first, let value = values[name] {
                out += parts.count == 2 && parts[1] == "possessive" ? Self.possessive(value, language: language) : value
            } else {
                out += rest[open...close]
            }
            rest = rest[rest.index(after: close)...]
        }
        return out + rest
    }
}

/// The plural form a whole number takes in each shipped language (CLDR's cardinal rules).
enum Plural {
    static func form(_ n: Int, language: String) -> String {
        let n = abs(n)
        let million = n != 0 && n % 1_000_000 == 0
        switch language {
        case "fr", "pt":
            return n <= 1 ? "one" : million ? "many" : "other"
        case "es", "it":
            return n == 1 ? "one" : million ? "many" : "other"
        case "pl":
            if n == 1 { return "one" }
            return (2...4).contains(n % 10) && !(12...14).contains(n % 100) ? "few" : "many"
        default:
            return n == 1 ? "one" : "other"
        }
    }
}

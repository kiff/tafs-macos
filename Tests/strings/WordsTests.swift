import Foundation

/// The shared words at the pin, as `scripts/shared.sh fetch` leaves them.
private let folder = URL(fileURLWithPath: ".shared/app/strings")

private func words(_ language: String) throws -> Words { try Words(language: language, folder: folder) }

let wordsTests: [Test] = [
    Test("every shipped language is read, with English's keys") {
        let shipped = try Words.shipped(folder: folder)
        // The 34 kiff/tafs ships at the pin, as `languages.json` says, the first ones among them.
        try expect(shipped.count >= 34, "34 or more shipped languages, got \(shipped.count)")
        try expect(Set(["en", "de", "fr", "es", "it", "pt", "nl", "pl", "ja", "ko", "pt-BR", "zh-Hant"]).isSubset(of: Set(shipped)), "the first ones shipped")
        let english = Set(try words("en").lines.keys)
        try expect(english.count > 1000, "more than 1000 keys, got \(english.count)")
        for language in shipped {
            try expectEqual(Set(try words(language).lines.keys), english)
        }
    },
    Test("a line is its language's, by the same key") {
        try expectEqual(try words("en")("home.overview.title"), "Overview")
        try expect(try words("pl")("home.loading") != words("en")("home.loading"), "Polish")
    },
    Test("a value goes in by name, and a name with no value stays") {
        let en = try words("en")
        try expectEqual(en("home.not_fully_removed", ["name": "Refunds"]), "Refunds isn't fully removed yet.")
        try expectEqual(en("home.not_fully_removed"), "{name} isn't fully removed yet.")
    },
    Test("a value that holds braces is not filled again") {
        let line = Words(language: "en", lines: ["a.b": .text("{one} and {two}")])
        try expectEqual(line("a.b", ["one": "{two}", "two": "2"]), "{two} and 2")
    },
    Test("a possessive follows the language's rule") {
        try expectEqual(Words.possessive("Rae", language: "en"), "Rae's")
        try expectEqual(Words.possessive("Refunds", language: "en"), "Refunds'")
        try expectEqual(Words.possessive("Klaus", language: "de"), "Klaus'")
        try expectEqual(Words.possessive("Rae", language: "de"), "Raes")
        try expectEqual(Words.possessive("Rae", language: "fr"), "Rae")
        try expectEqual(try words("en")("card.issue_prompt", ["taf": "Refunds"]), "Issue Refunds' Card")
    },
    Test("\"this\" before a name follows the language's rule, both ways") {
        let french = ["Mac", "PC", "PC Windows", "appareil", "iPad", "écran", "hôte"].map { Words.demonstrative($0, language: "fr") }
        try expectEqual(french, ["ce Mac", "ce PC", "ce PC Windows", "cet appareil", "cet iPad", "cet écran", "cet hôte"])
        try expectEqual(Words.demonstrative("Mac", language: "fr", capital: true), "Ce Mac")
        try expectEqual(Words.demonstrative("appareil", language: "fr", capital: true), "Cet appareil")
        try expectEqual(Words.demonstrative("Mac", language: "en"), "Mac")
        try expectEqual(Words.demonstrative("", language: "fr", capital: true), "")
        let line = Words(language: "fr", lines: ["a.b": .text("Alertes sur {device|this}"), "a.c": .text("{device|This} est ajouté."),
                                                 "a.d": .text("Sur {device|that}")])
        try expectEqual(line("a.b", ["device": "Mac"]), "Alertes sur ce Mac")
        try expectEqual(line("a.c", ["device": "appareil"]), "Cet appareil est ajouté.")
        // A form this app doesn't know stays as written, for the test below to catch.
        try expectEqual(line("a.d", ["device": "Mac"]), "Sur {device|that}")
    },
    Test("the \"this\" rule is the pinned generator's THIS table, letter by letter") {
        // Copied from the shared generate.py's THIS table: once the pin carries it, each language's letters and words must be
        // this app's, so the copy can't drift. Before the pin carries it, no line may use the form.
        let source = (try? String(contentsOf: folder.appendingPathComponent("generate.py"), encoding: .utf8)) ?? ""
        let table = try NSRegularExpression(pattern: #"^THIS = \{(.*)\}\s*$"#, options: .anchorsMatchLines)
        guard let match = table.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let range = Range(match.range(at: 1), in: source) else {
            for language in try Words.shipped(folder: folder) {
                for (key, line) in try words(language).lines {
                    let texts: [String]
                    switch line {
                    case .text(let text): texts = [text]
                    case .forms(let forms): texts = Array(forms.values)
                    }
                    try expect(!texts.contains { $0.contains("|this}") || $0.contains("|This}") },
                               "\(language) \(key) uses |this before the pin has its rule")
                }
            }
            return
        }
        let rules = String(source[range])
        let rule = try NSRegularExpression(pattern: #""(\w+)": \("([^"]*)", "([^"]*)", "([^"]*)"\)"#)
        let found = rule.matches(in: rules, range: NSRange(rules.startIndex..., in: rules))
        try expect(!found.isEmpty, "the pinned THIS table has a rule")
        for m in found {
            func part(_ i: Int) -> String { Range(m.range(at: i), in: rules).map { String(rules[$0]) } ?? "" }
            let (language, starts, before, other) = (part(1), part(2), part(3), part(4))
            for letter in "abcdefghijklmnopqrstuvwxyzàâäçéèêëîïôöùûüœæ" + starts {
                let name = "\(letter)x"
                try expectEqual(Words.demonstrative(name, language: language), (starts.contains(letter) ? before : other) + name)
            }
        }
    },
    Test("every line at the pin fills, in every language, with no brace left") {
        let placeholder = try NSRegularExpression(pattern: #"\{([a-z][a-z0-9_]*)(\|[^}]*)?\}"#)
        func names(_ text: String) -> [String] {
            placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                Range($0.range(at: 1), in: text).map { String(text[$0]) }
            }
        }
        for language in try Words.shipped(folder: folder) {
            let book = try words(language)
            for (key, line) in book.lines {
                switch line {
                case .text(let text):
                    let values = Dictionary(names(text).map { ($0, "Mac") }, uniquingKeysWith: { first, _ in first })
                    let filled = book(key, values)
                    try expect(!filled.contains("{"), "\(language) \(key) left a brace: \(filled)")
                case .forms(let forms):
                    let values = Dictionary(forms.values.flatMap(names).filter { $0 != "count" }.map { ($0, "Mac") },
                                            uniquingKeysWith: { first, _ in first })
                    for n in 0...25 {
                        let filled = book.count(key, n, values)
                        try expect(!filled.contains("{"), "\(language) \(key) (\(n)) left a brace: \(filled)")
                    }
                }
            }
        }
    },
    Test("a number takes its language's plural form") {
        let cases: [(String, [Int: String])] = [
            ("en", [0: "other", 1: "one", 2: "other"]),
            ("de", [1: "one", 5: "other"]),
            ("nl", [1: "one", 0: "other"]),
            ("fr", [0: "one", 1: "one", 2: "other", 1_000_000: "many"]),
            ("pt", [0: "one", 1: "one", 2: "other", 2_000_000: "many"]),
            ("es", [0: "other", 1: "one", 1_000_000: "many"]),
            ("it", [1: "one", 3: "other", 1_000_000: "many"]),
            ("pl", [1: "one", 2: "few", 4: "few", 5: "many", 12: "many", 14: "many", 22: "few", 25: "many", 0: "many"]),
            ("cs", [1: "one", 2: "few", 4: "few", 5: "other", 22: "other"]),
            ("sk", [1: "one", 3: "few", 0: "other"]),
            ("hr", [1: "one", 21: "one", 11: "other", 2: "few", 24: "few", 12: "other", 5: "other"]),
            ("lt", [1: "one", 21: "one", 11: "other", 2: "few", 9: "few", 19: "other", 10: "other"]),
            ("lv", [0: "zero", 10: "zero", 11: "zero", 1: "one", 21: "one", 2: "other"]),
            ("sl", [1: "one", 101: "one", 2: "two", 3: "few", 4: "few", 5: "other", 11: "other"]),
            ("ro", [1: "one", 0: "few", 2: "few", 19: "few", 20: "other", 101: "few", 120: "other"]),
            ("ar", [0: "zero", 1: "one", 2: "two", 3: "few", 10: "few", 11: "many", 99: "many", 100: "other", 103: "few"]),
            ("ja", [1: "other"]), ("zh-Hant", [1: "other"]), ("th", [1: "other"]), ("vi", [1: "other"]), ("id", [1: "other"]),
            ("tr", [1: "one", 2: "other"]), ("hu", [1: "one", 2: "other"]), ("bg", [1: "one"]), ("et", [1: "one"]),
            ("pt-BR", [0: "one", 1: "one", 2: "other"]),
            ("he", [1: "one", 2: "two", 3: "other", 10: "other", 20: "other"]),
            ("hy", [0: "one", 1: "one", 2: "other"]), ("bn", [0: "one", 1: "one", 2: "other"]),
            ("sr-Latn", [1: "one", 21: "one", 11: "other", 3: "few", 13: "other"]),
            ("mk", [1: "one", 21: "one", 11: "other", 2: "other"]),
            ("ca", [1: "one", 2: "other", 1_000_000: "other"]),
            ("km", [1: "other"]), ("lo", [1: "other"]),
            ("ru", [1: "one", 21: "one", 11: "many", 2: "few", 12: "many", 5: "many"]),
        ]
        for (language, forms) in cases {
            for (n, form) in forms {
                try expectEqual("\(language) \(n): \(Plural.form(n, language: language))", "\(language) \(n): \(form)")
            }
        }
    },
    Test("every form a number takes is one kiff/tafs's generator lists for its language, in every offered language") {
        // `generate.py`'s PLURALS: the forms each language's whole numbers take, beside "other".
        let generator = try String(contentsOf: folder.appendingPathComponent("generate.py"))
        guard let start = generator.range(of: "PLURALS = {"), let end = generator[start.upperBound...].range(of: "}") else {
            throw Failure(description: "no PLURALS in generate.py")
        }
        let table = try NSRegularExpression(pattern: #""([a-z]+)": \[([^\]]*)\]"#)
        let text = String(generator[start.upperBound..<end.lowerBound])
        var plurals: [String: Set<String>] = [:]
        for match in table.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let language = String(text[Range(match.range(at: 1), in: text)!])
            let forms = text[Range(match.range(at: 2), in: text)!].split(separator: ",")
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }.filter { !$0.isEmpty }
            plurals[language] = Set(forms + ["other"])
        }
        for language in try Words.shipped(folder: folder) {
            let base = String(language.split(separator: "-")[0])
            guard let forms = plurals[base] else { throw Failure(description: "\(language) has no PLURALS entry") }
            for n in 0...1_200 {
                let form = Plural.form(n, language: language)
                try expect(forms.contains(form) || form == "many" && Set(["fr", "es", "it", "pt"]).contains(base),
                           "\(language) \(n) is \(form), not one of \(forms.sorted())")
            }
            // And each form the generator lists is reached by some whole number.
            let reached = Set((0...1_200).map { Plural.form($0, language: language) })
            try expect(forms.subtracting(["other"]).isSubset(of: reached), "\(language) never reaches \(forms.subtracting(reached).sorted())")
        }
    },
    Test("Arabic and Hebrew are shipped, with every line, and written right to left") {
        let shipped = try Words.shipped(folder: folder)
        try expect(shipped.contains("ar") && shipped.contains("he"), "ar and he shipped")
        let english = Set(try words("en").lines.keys)
        for language in ["ar", "he"] {
            let book = try words(language)
            try expect(book.isRightToLeft, "\(language) right to left")
            try expectEqual(Set(book.lines.keys), english)
            try expect(book("home.overview.title") != (try words("en"))("home.overview.title"), "\(language)'s own line")
        }
        for language in shipped where !["ar", "he"].contains(language) {
            try expect(!(try words(language)).isRightToLeft, "\(language) left to right")
        }
    },
    Test("in Arabic and Hebrew each value is set apart, with no direction character of its own; left to right, values are as they are") {
        let he = try words("he"), en = try words("en")
        let filled = he("home.not_fully_removed", ["name": "Refunds #5098"])
        try expect(filled.contains("\u{2068}Refunds #5098\u{2069}"), "isolated: \(filled)")
        let sneaky = he("home.not_fully_removed", ["name": "A\u{2069}\u{202E}B\u{200F}"])
        try expect(sneaky.contains("\u{2068}AB\u{2069}"), "no direction character inside: \(sneaky.unicodeScalars.map { String($0.value, radix: 16) })")
        try expectEqual(en("home.not_fully_removed", ["name": "Refunds"]), "Refunds isn't fully removed yet.")
        try expect(!(try words("ar")).count("needs_you.count", 3).contains("{"), "a count fills")
        try expectEqual(Words.withoutDirection("a\u{200E}b\u{061C}c\u{2066}d"), "abcd")
    },
    Test("a small heading keeps no letter-spacing in Hangul, kana, Han and Arabic, as the iPad's Eyebrow") {
        for text in ["بانتظارك", "あなたのTAFS", "기억하는 것", "要确认", "Needs you · بانتظارك"] { try expect(Script.ideographic(text), text) }
        // Hebrew's letters don't join, and the iPad spaces it as Latin.
        for text in ["Needs you", "À VOUS", "ЖДЁТ ВАС", "ממתין לך", "Ελληνικά"] { try expect(!Script.ideographic(text), text) }
    },
    Test("a count's line is the form its number takes, with the number in it") {
        let pl = try words("pl")
        try expectEqual(pl.count("needs_you.count", 1), "1 czeka na Ciebie.")
        try expectEqual(pl.count("needs_you.count", 3), "3 czekają na Ciebie.")
        try expectEqual(pl.count("needs_you.count", 5), "5 czeka na Ciebie.")
        // A form the line doesn't have is its `other`.
        let line = Words(language: "fr", lines: ["a.b": .forms(["one": "{count} un", "other": "{count} autres"])])
        try expectEqual(line.count("a.b", 1_000_000).hasSuffix("autres"), true)
        try expectEqual(try words("en").count("needs_you.count", 1000).hasPrefix("1,000"), true)
    },
    Test("the app's language is the first preferred one that is shipped, else English") {
        let shipped = ["en", "de", "fr", "es", "it", "pt", "nl", "pl"]
        try expectEqual(Words.language(preferred: ["pt-BR", "en-US"], shipped: shipped), "pt")
        try expectEqual(Words.language(preferred: ["ja-JP", "fr_FR"], shipped: shipped), "fr")
        try expectEqual(Words.language(preferred: ["ja-JP"], shipped: shipped), "en")
    },
    Test("every key the code names is in the shared words") {
        let english = try words("en").lines
        let named = try NSRegularExpression(pattern: #"\bwords(\.count)?\(\s*"([a-z0-9_.]+)""#)
        let sources = FileManager.default.enumerator(at: URL(fileURLWithPath: "Sources"), includingPropertiesForKeys: nil)
        while let file = sources?.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let code = try String(contentsOf: file, encoding: .utf8)
            for match in named.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                guard let range = Range(match.range(at: 2), in: code) else { continue }
                let key = String(code[range])
                let isCount = match.range(at: 1).location != NSNotFound
                switch english[key] {
                case .forms?: try expect(isCount, "\(key) is a count: words.count, in \(file.lastPathComponent)")
                case .text?: try expect(!isCount, "\(key) is not a count, in \(file.lastPathComponent)")
                case nil: throw Failure(description: "\(key) is not in kiff/tafs app/strings/en (\(file.lastPathComponent))")
                }
            }
        }
    },
]

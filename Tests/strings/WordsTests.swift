import Foundation

/// The shared words at the pin, as `scripts/shared.sh fetch` leaves them.
private let folder = URL(fileURLWithPath: ".shared/app/strings")

private func words(_ language: String) throws -> Words { try Words(language: language, folder: folder) }

let stringsTests: [Test] = [
    Test("every shipped language is read, with English's keys") {
        let shipped = try Words.shipped(folder: folder)
        try expectEqual(shipped.sorted(), ["de", "en", "es", "fr", "it", "nl", "pl", "pt"])
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
        ]
        for (language, forms) in cases {
            for (n, form) in forms {
                try expectEqual("\(language) \(n): \(Plural.form(n, language: language))", "\(language) \(n): \(form)")
            }
        }
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

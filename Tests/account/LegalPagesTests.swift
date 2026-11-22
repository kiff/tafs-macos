import Foundation

let legalPagesTests: [Test] = [
    Test("each of kiff.dev's 38 languages gets its own Terms and Privacy policy, as the iPad's Legal") {
        try expectEqual(LegalPages.languages.count, 38)
        for language in LegalPages.languages {
            try expectEqual(LegalPages.terms(language), "https://kiff.dev/\(language)/tafs/terms")
            try expectEqual(LegalPages.privacy(language), "https://kiff.dev/\(language)/tafs/privacy")
        }
    },
    Test("Traditional Chinese opens under /zh/, Serbian under /sr/ and Brazilian Portuguese under /pt/") {
        try expectEqual(LegalPages.terms("zh-Hant"), "https://kiff.dev/zh/tafs/terms")
        try expectEqual(LegalPages.terms("sr-Latn"), "https://kiff.dev/sr/tafs/terms")
        try expectEqual(LegalPages.privacy("pt-BR"), "https://kiff.dev/pt/tafs/privacy")
        try expectEqual(LegalPages.saysEnglish("zh-Hant"), false)
    },
    Test("English and a language kiff.dev has no page in get the English pages, with no /en/") {
        for language in ["en", "el", "fi", ""] {
            try expectEqual(LegalPages.terms(language), "https://kiff.dev/tafs/terms")
            try expectEqual(LegalPages.privacy(language), "https://kiff.dev/tafs/privacy")
        }
    },
    Test("a link says the page is in English only where kiff.dev has none in the app's language") {
        try expectEqual(LegalPages.saysEnglish("fr"), false)
        try expectEqual(LegalPages.saysEnglish("ja"), false)
        try expectEqual(LegalPages.saysEnglish("en"), false)
        try expectEqual(LegalPages.saysEnglish("ar"), false)
        try expectEqual(LegalPages.saysEnglish("el"), true)
    },
]

import Foundation

let legalPagesTests: [Test] = [
    Test("each of the seven languages gets its own Terms and Privacy policy") {
        for language in ["de", "es", "fr", "it", "nl", "pl", "pt"] {
            try expectEqual(LegalPages.terms(language), "https://kiff.dev/\(language)/tafs/terms")
            try expectEqual(LegalPages.privacy(language), "https://kiff.dev/\(language)/tafs/privacy")
        }
    },
    Test("English and a language kiff.dev has no page in get the English pages, with no /en/") {
        for language in ["en", "ja", ""] {
            try expectEqual(LegalPages.terms(language), "https://kiff.dev/tafs/terms")
            try expectEqual(LegalPages.privacy(language), "https://kiff.dev/tafs/privacy")
        }
    },
    Test("a link says the page is in English only where kiff.dev has none in the app's language") {
        try expectEqual(LegalPages.saysEnglish("fr"), false)
        try expectEqual(LegalPages.saysEnglish("pl"), false)
        try expectEqual(LegalPages.saysEnglish("en"), false)
        try expectEqual(LegalPages.saysEnglish("ja"), true)
    },
]

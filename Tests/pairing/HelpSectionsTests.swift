import Foundation

// How tafs works' help sections (`HelpSections`): which show, and their words filled in every shipped language.

private let strings = URL(fileURLWithPath: ".shared/app/strings")

let pairingHelpSectionsTests: [Test] = [
    Test("Chrome's section shows only once planque offers Chromes; the security key's while this Mac approves with one") {
        try expectEqual(HelpSections.shown(chromeOffered: false, securityKey: true), [.securityKey])
        try expectEqual(HelpSections.shown(chromeOffered: true, securityKey: true), [.chrome, .securityKey])
        try expectEqual(HelpSections.shown(chromeOffered: true, securityKey: false), [.chrome])
        try expectEqual(HelpSections.shown(chromeOffered: false, securityKey: false), [])
    },
    Test("no section offers the emailed code: this Mac has no Sign in with a code setting to point to") {
        try expect(!HelpSections.Section.allCases.map(\.rawValue).contains("code"), "no code section")
    },
    Test("Chrome's lines name Needs you, Account and Chrome by the app's own titles, in English") {
        let words = try Words(language: "en", folder: strings)
        let lines = HelpSections.Section.chrome.lines(words)
        try expectEqual(lines.title, "tafs can work in your Chrome")
        try expect(lines.lead.contains(words("needs_you.title")), "Needs you named: \(lines.lead)")
        try expect(lines.more.hasPrefix("\(words("settings.title")) › \(words("chrome.title"))"), "Account › Chrome: \(lines.more)")
        let key = HelpSections.Section.securityKey.lines(words)
        try expectEqual(key.title, "Approve with a security key on this computer")
        try expect(key.more.contains("Touch ID can't approve"), "macOS 12's Touch ID line")
    },
    Test("every section's lines are filled, with no brace left, in every shipped language") {
        for language in try Words.shipped(folder: strings) {
            let words = try Words(language: language, folder: strings)
            for section in HelpSections.Section.allCases {
                let lines = section.lines(words)
                for line in [lines.title, lines.lead, lines.more] {
                    try expect(!line.isEmpty && !line.contains("{") && !line.hasPrefix("help."), "\(language) \(section): \(line)")
                }
            }
        }
    },
]

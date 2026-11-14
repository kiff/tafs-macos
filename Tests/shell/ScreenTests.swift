import Foundation

let shellScreenTests: [Test] = [
    Test("every screen's name is a shared line, in every shipped language") {
        let folder = URL(fileURLWithPath: ".shared/app/strings")
        for language in try Words.shipped(folder: folder) {
            let words = try Words(language: language, folder: folder)
            for screen in Screen.allCases {
                try expect(words(screen.titleKey) != screen.titleKey, "\(screen.titleKey) in \(language)")
            }
        }
    },
    Test("the sidebar lists each screen once, in the iPad's order, with the Overview behind the app's name") {
        try expectEqual(Screen.list, [.needsYou, .record, .calendar, .usage, .connectApps])
        try expectEqual(Screen.foot, [.coach, .account])
        try expectEqual(Set(Screen.list + Screen.foot + [.overview]).count, Screen.allCases.count)
    },
]

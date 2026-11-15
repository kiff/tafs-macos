import AppKit
import SwiftUI

/// Whether a drawn colour is the one asked for, within the rounding of the display's colour space.
private func near(_ got: UInt32?, _ want: UInt32) -> Bool {
    guard let got else { return false }
    return [16, 8, 0].allSatisfy { abs(Int((got >> $0) & 0xFF) - Int((want >> $0) & 0xFF)) <= 2 }
}

private let strings = URL(fileURLWithPath: ".shared/app/strings")

private let sidebarTafs: [Home.Taf] = {
    let json = #"{"tafs":[{"name":"Refunds","kiff_agent":"a1","color":1,"state":"working","work":{"line":"Working on 3 refunds"}},{"name":"Invoices","kiff_agent":"a2","color":4,"state":"idle","next_run_words":"Next run Mon 08:00"}]}"#
    return (try? JSONDecoder().decode(Home.Page.self, from: Data(json.utf8)))?.tafs ?? []
}()

private func shell(_ language: String, selection: Screen = .overview, needsYou: Int = 0, tafs: [Home.Taf] = []) -> some View {
    Mascot.file = URL(fileURLWithPath: ".shared/ios/Shared/Mascot.xcassets/Mascot.imageset/mascot.png")
    return ShellView(selection: .constant(selection), needsYou: needsYou, tafs: tafs, noTafsLine: "Pick a job for your first taf.", accountLine: "you@example.com").environment(\.words, Words.load(folder: strings, preferred: [language]))
}

let shellMacTests: [Test] = [
    Test("the shell draws the sidebar on the raised ground and the rest on the background") {
        for dark in [false, true] {
            let size = ShellView.minimumSize
            guard let bitmap = Snapshot.bitmap(of: shell("en"), size: size, dark: dark) else { throw Failure(description: "no bitmap") }
            let sidebar = Snapshot.hex(bitmap, x: 4, y: Int(size.height) / 2)
            let detail = Snapshot.hex(bitmap, x: Int(size.width) - 10, y: Int(size.height) - 10)
            try expect(near(sidebar, dark ? Palette.raised.dark : Palette.raised.light), "the raised ground, dark: \(dark)")
            try expect(near(detail, dark ? Palette.background.dark : Palette.background.light), "the background, dark: \(dark)")
        }
    },
    Test("the words are the preferred language's, and English when it isn't shipped") {
        try expectEqual(Words.load(folder: strings, preferred: ["fr-FR"]).language, "fr")
        try expectEqual(Words.load(folder: strings, preferred: ["ja-JP"]).language, "en")
        try expectEqual(Words.load(folder: URL(fileURLWithPath: "nowhere"), preferred: ["fr"])("app.name"), "app.name")
    },
    Test("the screenshots: the sidebar in English, French and Portuguese, light and dark") {
        let size = CGSize(width: 1280, height: 800)
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr", "pt"] {
            for dark in [false, true] {
                guard let bitmap = Snapshot.bitmap(of: shell(language, selection: .needsYou, needsYou: 3, tafs: dark ? sidebarTafs : []), size: size, dark: dark),
                      let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG for \(language)") }
                try expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]), "the PNG signature")
                try png.write(to: folder.appendingPathComponent("sidebar-\(language)\(dark ? "-dark" : "").png"))
            }
        }
    },
]

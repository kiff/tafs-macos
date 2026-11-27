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

private let sidebarHeld: [HeldRow] = {
    let json = #"{"exceptions":[{"id":"exc_1","subject":"a1","action":"refund","title":"Refund order #4471","reason_text":"Over its €500 limit","created_at":"2026-11-15T00:17:00Z","expires_at":"2026-11-15T00:27:00Z"}]}"#
    struct Held: Decodable { let exceptions: [HeldCall] }
    let calls = (try? AccountClient.decoder.decode(Held.self, from: Data(json.utf8)))?.exceptions ?? []
    return calls.map { HeldRow($0, tafs: sidebarTafs) }
}()

private func shell(_ language: String, selection: Screen = .overview, needsYou: Int = 0, tafs: [Home.Taf] = [], held: [HeldRow] = []) -> some View {
    Mascot.file = URL(fileURLWithPath: ".shared/ios/Shared/Mascot.xcassets/Mascot.imageset/mascot.png")
    return ShellView(selection: .constant(selection), needsYou: needsYou, tafs: tafs, noTafsLine: "Pick a job for your first taf.", held: held, accountLine: "you@example.com").environment(\.words, Words.load(folder: strings, preferred: [language]))
}

/// Whether any point down the sidebar's left edge, between two heights, isn't its ground.
private func filled(_ bitmap: NSBitmapImageRep, from top: Int, to bottom: Int, dark: Bool) -> Bool {
    (top...bottom).contains { !near(Snapshot.hex(bitmap, x: 20, y: $0), dark ? Palette.raised.dark : Palette.raised.light) }
}

let shellViewMacTests: [Test] = [
    Test("every date and time is in the app's language, never this Mac's: English words, English dates, on a Spanish Mac too") {
        let folder = URL(fileURLWithPath: ".shared/app/strings")
        let english = Words.load(folder: folder, preferred: ["en"])
        let spanish = Words.load(folder: folder, preferred: ["es"])
        let utc = TimeZone(identifier: "UTC")!
        let at = ISO8601DateFormatter().date(from: "2026-11-15T14:05:00Z")!
        // A day and a time as the app shows them, in the words' language whatever this Mac's.
        try expectEqual(AppDates.formatter(english, date: .medium, zone: utc, region: "US").string(from: at), "Nov 15, 2026")
        let reference = DateFormatter()
        reference.locale = Locale(identifier: "es_ES")
        reference.dateStyle = .medium
        reference.timeZone = utc
        try expectEqual(AppDates.formatter(spanish, date: .medium, zone: utc, region: "ES").string(from: at), reference.string(from: at))
        try expect(reference.string(from: at) != "Nov 15, 2026", "a Spanish date")
        // The dial's times, in the account's zone and the app's language.
        let london = AccountTime("Europe/London")
        try expectEqual(london.zonedShown(at, date: .abbreviated, time: .omitted, words: english, here: utc, region: "US"), "Nov 15, 2026")
        // The app's language keeps this Mac's region, as the iPad's Locale.current: English on a
        // British Mac reads 15 Nov and a 24-hour clock.
        try expectEqual(AppDates.formatter(english, date: .medium, zone: utc, region: "GB").string(from: at), "15 Nov 2026")
        try expectEqual(AppDates.formatter(english, time: .short, zone: utc, region: "GB", twentyFour: true).string(from: at), "14:05")
        // On a Mac set to the 12-hour clock, the same time is a 12-hour one, whatever the language's default
        // (kiff/tafs#2196); and a Mac on 24-hour time draws a US English time as 14:05, not 2:05 PM.
        try expect(AppDates.formatter(english, time: .short, zone: utc, region: "GB", twentyFour: false).string(from: at).hasPrefix("2:05"), "12-hour")
        try expectEqual(AppDates.formatter(english, time: .short, zone: utc, region: "US", twentyFour: true).string(from: at), "14:05")
        // The date part stays as its style writes it; only the time follows the clock.
        let both = AppDates.formatter(english, date: .medium, time: .short, zone: utc, region: "US", twentyFour: true).string(from: at)
        try expect(both.hasPrefix("Nov 15, 2026") && both.hasSuffix("14:05"), both)
        try expectEqual(AppDates.locale(english, region: nil).identifier, "en")
        // A fixed clock stays 24-hour whatever the language.
        try expectEqual(AppDates.fixed("HH:mm", zone: utc).string(from: at), "14:05")
        try expectEqual(london.shortTime(at, words: english, twentyFour: true), "14:05")
        try expect(london.shortTime(at, words: english, region: "US", twentyFour: false).hasPrefix("2:05"), "a 12-hour Mac")
    },
    Test("a held call in NEEDS YOU opens its taf's page, as the iPad's HomeSelection.held; one whose taf isn't listed opens Needs you (sources)") {
        let source = try String(contentsOf: URL(fileURLWithPath: "Sources/App/shell/ShellView.swift"), encoding: .utf8)
        try expect(source.contains("if let taf = tafs.first(where: { $0.kiffAgent == row.agent }), taf.tafID != nil { open(taf) } else { selection = .needsYou }"),
                   "the row opens its taf's page")
        try expectEqual(sidebarHeld.first?.agent, "a1")
    },
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
    Test("the chosen screen's row has a grey ground, and the others none") {
        // The mark ends near 86 points down; the rows that follow are 46 each: Needs you, then Record.
        for dark in [false, true] {
            let size = ShellView.minimumSize
            guard let record = Snapshot.bitmap(of: shell("en", selection: .record), size: size, dark: dark),
                  let overview = Snapshot.bitmap(of: shell("en", selection: .overview), size: size, dark: dark)
            else { throw Failure(description: "no bitmap") }
            try expect(filled(record, from: 140, to: 170, dark: dark), "Record's row is filled, dark: \(dark)")
            try expect(!filled(record, from: 92, to: 126, dark: dark), "Needs you's row is not, dark: \(dark)")
            try expect(!filled(overview, from: 92, to: 170, dark: dark), "no screen row is filled on the Overview, dark: \(dark)")
        }
    },
    Test("the words are the preferred language's, and English when it isn't shipped") {
        try expectEqual(Words.load(folder: strings, preferred: ["fr-FR"]).language, "fr")
        try expectEqual(Words.load(folder: strings, preferred: ["fi-FI"]).language, "en")
        try expectEqual(Words.load(folder: URL(fileURLWithPath: "nowhere"), preferred: ["fr"])("app.name"), "app.name")
    },
    Test("the screenshots: the sidebar in English, French and Portuguese, light and dark") {
        let size = CGSize(width: 1280, height: 800)
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr", "pt"] {
            for dark in [false, true] {
                guard let bitmap = Snapshot.bitmap(of: shell(language, selection: .needsYou, needsYou: 1, tafs: dark ? sidebarTafs : [], held: dark ? sidebarHeld : []), size: size, dark: dark),
                      let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG for \(language)") }
                try expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]), "the PNG signature")
                try png.write(to: folder.appendingPathComponent("sidebar-\(language)\(dark ? "-dark" : "").png"))
            }
        }
    },
]

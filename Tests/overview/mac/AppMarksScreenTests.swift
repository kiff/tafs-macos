import AppKit
import Foundation
import SwiftUI

private let stripeLogo = "/v1/logos/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
private let gmailLogo = "/v1/logos/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
private let qontoLogo = "/v1/logos/cccccccccccccccccccccccccccccccc"
private let refusedLogo = "/v1/logos/dddddddddddddddddddddddddddddddd"

/// The gallery, each job's apps with the logos tafs cloud serves: one it refuses (Zendesk), one
/// from elsewhere and dropped (Notion), and one with none (Sheets).
private let galleryWithLogos = """
{"categories":[{"id":"money","title":"Money","color":{"light":"#1F7A4D","dark":"#4CC38A"}},{"id":"support","title":"Support","color":{"light":"#2F5FD0","dark":"#7EA2FF"}}],
 "recipes":[{"id":"r1","title":"Refunds","category":"money","headline":"Refunds wait days for someone to click","line":"Refunds orders within its limit","say":"Refund orders under €150",
             "apps":[{"name":"Stripe","logo":"\(stripeLogo)"},{"name":"Gmail","logo":"\(gmailLogo)"}]},
            {"id":"r9","title":"Invoices","category":"money","headline":"Invoices chased by hand","line":"Sends the reminders","say":"Chase unpaid invoices",
             "apps":[{"name":"Qonto","logo":"\(qontoLogo)"},{"name":"Google Sheets"}]},
            {"id":"r2","title":"Replies","category":"support","headline":"Tickets wait overnight","line":"Answers the easy ones","say":"Answer tickets",
             "apps":[{"name":"Zendesk","logo":"\(refusedLogo)"},{"name":"Notion","logo":"https://cdn.example.com/notion.png"}]}],
 "words":{"title":"Start a new taf","all":"All jobs","own_words":"Say it in your own words","own_words_line":"Coach builds the taf with you.","explore":"Explore jobs","see_all":"See all jobs","try":"Try it with Coach"}}
"""

/// A logo as tafs cloud serves one: a small PNG of one colour.
@MainActor
private func logoPNG(_ color: Color) -> Data {
    let view = RoundedRectangle(cornerRadius: 10).fill(color).padding(4)
    return Snapshot.bitmap(of: view, size: CGSize(width: 48, height: 48)).flatMap { Snapshot.png($0) } ?? Data()
}

/// tafs cloud's logo route: a PNG for each key it keeps, a 404 for any other.
private struct LogoAnswers: Transport {
    let logos: [String: Data]
    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        guard request.headers["Authorization"] == nil, let png = logos[request.path] else { return (404, Data(#"{"error":"no logo"}"#.utf8)) }
        return (200, png)
    }
}

@MainActor
private func readLogos() async -> AppLogoImages {
    let images = AppLogoImages(AppLogos(transport: LogoAnswers(logos: [
        stripeLogo: logoPNG(Color(red: 0.39, green: 0.36, blue: 0.98)), gmailLogo: logoPNG(Color(red: 0.86, green: 0.2, blue: 0.16)),
        qontoLogo: logoPNG(Color(red: 0.12, green: 0.12, blue: 0.14)),
    ])))
    for path in [stripeLogo, gmailLogo, qontoLogo, refusedLogo] { _ = await images.load(path) }
    return images
}

private let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])

private func write<V: View>(_ view: V, _ name: String, size: CGSize, dark: Bool) throws {
    guard let bitmap = Snapshot.bitmap(of: view, size: size, dark: dark), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
    let folder = URL(fileURLWithPath: "build/screenshots")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try png.write(to: folder.appendingPathComponent(name + (dark ? "-dark" : "") + ".png"))
}

let appMarksMacTests: [Test] = [
    Test("a job's app is its logo, then its name; a refused or dropped logo leaves the name alone", awaiting: { @MainActor in
        let images = await readLogos()
        func drawn(_ app: Recipes.App) throws -> NSBitmapImageRep {
            let view = AppMark(app: app).environment(\.appLogos, images).environment(\.words, words).frame(width: 120, height: 24, alignment: .leading).background(Color.white)
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 120, height: 24)) else { throw Failure(description: "no bitmap") }
            return bitmap
        }
        // Gmail's red logo comes first, at the row's start.
        let gmail = Snapshot.hexes(try drawn(Recipes.App(name: "Gmail", logo: gmailLogo)), x: 9, y: 12)
        try expect(gmail.contains { ($0 >> 16) & 0xFF > 0xA0 && ($0 >> 8) & 0xFF < 0x70 }, "Gmail's logo: \(gmail.map { String($0, radix: 16) })")
        // A logo tafs cloud refused, or none: nothing before the name.
        for app in [Recipes.App(name: "Zendesk", logo: refusedLogo), Recipes.App(name: "Notion", logo: "https://cdn.example.com/notion.png"), Recipes.App(name: "Sheets")] {
            let start = Snapshot.hexes(try drawn(app), x: 1, y: 3)
            try expect(start.contains(0xFFFFFF), "\(app.name) drew a logo: \(start.map { String($0, radix: 16) })")
        }
    }),
    Test("the screenshots: Explore jobs and the New taf gallery with the apps' logos, light and dark", awaiting: { @MainActor in
        let images = await readLogos()
        let gallery = try JSONDecoder().decode(Gallery.self, from: Data(galleryWithLogos.utf8))
        try expectEqual(gallery.asRecipes().recipes.map { $0.apps.map(\.logo) }, [[stripeLogo, gmailLogo], [qontoLogo, nil], [refusedLogo, nil]])
        for dark in [false, true] {
            let explore = RecipeGallerySheet(gallery: gallery, mode: .browse, labels: nil, canHand: true, choose: { _ in }, close: {})
                .environment(\.words, words).environment(\.appLogos, images)
            try write(explore, "explore-jobs-logos-en", size: CGSize(width: 680, height: 640), dark: dark)
            let create = RecipeGallerySheet(gallery: gallery, mode: .create, labels: nil, canHand: true, choose: { _ in }, close: {})
                .environment(\.words, words).environment(\.appLogos, images)
            try write(create, "gallery-logos-en", size: CGSize(width: 680, height: 640), dark: dark)
        }
    }),
]

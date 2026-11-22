import AppKit
import CryptoKit
import Foundation
import SwiftUI

private let artSession = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let artCoachSetup = #"{"setup":{"id":"taf-coach","name":"Coach","job":"setup","status":"active","next_run":null,"last_run":null},"tools":{"state":"given"}}"#
private let artOneTaf = #"{"tafs":[{"name":"Refunds","kiff_agent":"agent_refunds","color":1,"state":"working","work":{"line":"Working on 3 refunds"}}]}"#
private let artBriefClear = #"""
{"decisions":[],
 "done":[{"mission":{"id":"m_1","name":"Late invoices"},"cases":[{"name":"INV-0412","words":"Paid","state":"closed"},{"words":"Reminder sent","state":"waiting","next_check":"Tue"}],"value":"€3,400 due back","log":"m_1"}],
 "words":{"title":"Your brief","done":"Done since last evening","when":"Morning brief · 08:00"}}
"""#
private let artGallery = #"""
{"categories":[{"id":"money","title":"Money"}],
 "recipes":[{"id":"r1","title":"Refunds","category":"money","headline":"Refunds wait days for someone to click","line":"Refunds orders within its limit","say":"Refund orders under €150"}],
 "words":{"title":"Start a new taf","all":"All jobs","own_words":"Say it in your own words","own_words_line":"Coach builds the taf with you."}}
"""#

private func artWords() -> Words { Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"]) }

/// Writes one board's screen, light and dark, as `board-<n>-<name>-<light|dark>.png`.
@MainActor
private func shoot<V: View>(_ board: ArtBoard, _ name: String, _ view: V, _ size: CGSize) throws {
    let folder = URL(fileURLWithPath: "build/screenshots")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for dark in [false, true] {
        guard let bitmap = Snapshot.bitmap(of: view.environment(\.words, artWords()), size: size, dark: dark),
              let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG for board \(board.rawValue)") }
        try png.write(to: folder.appendingPathComponent("board-\(board.rawValue)-\(name)-\(dark ? "dark" : "light").png"))
    }
}

/// Whether the point is drawn in the colour, within a runner's rounding, as stored or as sRGB.
private func artNear(_ bitmap: NSBitmapImageRep, x: Int, y: Int, _ wanted: UInt32) -> Bool {
    Snapshot.hexes(bitmap, x: x, y: y).contains { got in
        [16, 8, 0].allSatisfy { abs(Int((got >> $0) & 0xFF) - Int((wanted >> $0) & 0xFF)) <= 6 }
    }
}

let shellIllustrationMacTests: [Test] = [
    Test("a drawing follows the appearance: board 1's card is the panel's white in light and its dark in dark, on the ground's own colour", awaiting: { @MainActor in
        // Board 1 on its 380 by 335 grid, drawn 200 wide: its card's empty top right is at (260, 70)
        // on the grid, and the board's corner, past the halo, is bare.
        let scale = 200.0 / 380
        for dark in [false, true] {
            let view = Illustration.firstRun.frame(width: 200, height: 335 * scale).background(Theme.background)
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 200, height: 335 * scale), dark: dark) else { throw Failure(description: "no bitmap") }
            let card = (x: Int(260 * scale), y: Int(70 * scale))
            try expect(artNear(bitmap, x: card.x, y: card.y, dark ? Palette.panel.dark : Palette.panel.light), "the card on the panel's colour, dark: \(dark)")
            try expect(artNear(bitmap, x: 2, y: Int(335 * scale) - 2, dark ? Palette.background.dark : Palette.background.light), "the corner bare, dark: \(dark)")
        }
    }),
    Test("the screenshots: each board on its screen, in light and dark", awaiting: { @MainActor in
        // 1. The sign-in window, KIFF's half.
        let signIn = SignInModel(client: KIFFClient(transport: CannedTransport([])), key: SoftwareKey(key: P256.Signing.PrivateKey()), approval: .passkey,
                                 sessions: SessionStore(store: MemoryStore()), deviceName: "tafs on this Mac", sleep: { _ in throw CancellationError() },
                                 open: { _ in }, enclave: false, onboarding: false)
        signIn.show(.welcome)
        try shoot(.firstRun, "sign-in", SignInView(model: signIn), CGSize(width: 1280, height: 800))
        // 2. The Overview with no taf and no job listed; 10. with a taf.
        let none = OverviewModel(cloud: CloudClient(transport: CannedTransport([(200, #"{"tafs":[]}"#)]), session: artSession))
        await none.load()
        try shoot(.noTafs, "overview", OverviewView(model: none, mayUseCoach: true, onboarding: false), CGSize(width: 980, height: 800))
        let one = OverviewModel(cloud: CloudClient(transport: CannedTransport([(200, artOneTaf)]), session: artSession))
        await one.load()
        try shoot(.overview, "overview", OverviewView(model: one), CGSize(width: 980, height: 800))
        // 3. Your brief with nothing to decide.
        let brief = BriefModel(cloud: CloudClient(transport: CannedTransport([(200, artBriefClear)]), session: artSession))
        await brief.load()
        try expectEqual(brief.decisions.count, 0)
        try shoot(.briefClear, "brief", BriefScreen(model: brief, needsYou: Text(verbatim: "")), CGSize(width: 1100, height: 800))
        // 4. Halt all, halted.
        let halted = #"{"halt":{"state":"halted","runtime":true,"kiff":true,"planque":true}}"#
        let halt = HaltModel(cloud: CloudClient(transport: CannedTransport([(200, halted), (200, halted)]), session: artSession), taf: nil, sleep: { _ in })
        await halt.refresh()
        try shoot(.allHalted, "halt", HaltView(model: halt, name: nil, close: {}), CGSize(width: 520, height: HaltView.height(.allHalted)))
        // 5. An app connected: connecting's receipt.
        let receipt = ConnectReceipt(id: "s1:approval-1", heading: "Connect Qonto", line: "Qonto is connected (read only)")
        let receiptSheet = ConnectReceiptSheet(receipt: receipt, done: {})
        try shoot(.appConnected, "connect-receipt", receiptSheet, CGSize(width: ConnectReceiptSheet.width,
                                                                          height: ceil(NSHostingView(rootView: receiptSheet.environment(\.words, artWords())).fittingSize.height)))
        // 6. Needs you with nothing waiting.
        let needsYou = NeedsYouModel(account: AccountClient(transport: CannedTransport([(200, #"{"exceptions":[]}"#)]), session: artSession, signMessage: { _ in "SIG" }),
                                     route: .phoneOrPasskey, confirm: { _ in })
        await needsYou.load()
        try shoot(.nothingWaiting, "needs-you", NeedsYouView(model: needsYou, now: Date(timeIntervalSince1970: 1_794_679_800)), CGSize(width: 980, height: 700))
        // 7. Coach's empty chat with one taf.
        let coach = CoachModel(cloud: CloudClient(transport: CannedTransport([(200, artCoachSetup), (200, #"{"chats":[]}"#), (200, #"{"items":[]}"#)]), session: artSession))
        await coach.load()
        try expect(coach.isEmpty, "the empty chat")
        try shoot(.coachFirst, "coach", CoachView(model: coach, tafCount: 1), CGSize(width: 980, height: 600))
        // 9. Coach before it's started.
        let unstarted = CoachModel(cloud: CloudClient(transport: CannedTransport([(200, #"{"setup":null}"#)]), session: artSession), sleep: { _ in throw CancellationError() })
        await unstarted.load()
        try expectEqual(unstarted.state, .notStarted)
        try shoot(.coachStarting, "coach-start", CoachView(model: unstarted, start: {}), CGSize(width: 980, height: 640))
        // 8. The gallery's Say it in your own words.
        let gallery = try JSONDecoder().decode(Gallery.self, from: Data(artGallery.utf8))
        try shoot(.newTaf, "gallery", RecipeGallerySheet(gallery: gallery, mode: .create, labels: nil, canHand: true, choose: { _ in }, close: {}), CGSize(width: 680, height: 640))
    }),
]

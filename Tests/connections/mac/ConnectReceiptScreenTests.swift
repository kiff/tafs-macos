import AppKit
import Foundation
import SwiftUI

private let receiptSession = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let receiptCoachSetup = #"{"setup":{"id":"taf-coach","name":"Coach","job":"setup","status":"active","next_run":null,"last_run":null},"tools":{"state":"given"}}"#
private let receiptNoChats = #"{"chats":[]}"#
/// Coach's chat with an approval to connect Qonto, waiting, then with its connection made.
private let receiptWaiting = #"{"working":false,"items":[{"type":"card","card":{"key":"s1:approval-1","session":"s1","component":{"id":"approval-1","type":"approval","title":"Connect Qonto","waits":"owner"}}}]}"#
private let receiptConnected = #"{"working":false,"items":[{"type":"card","card":{"key":"s1:approval-1","session":"s1","answer":{"state":"answered","words":"Approved"},"component":{"id":"approval-1","type":"approval","title":"Connect Qonto","connection":{"done":true,"words":"Qonto is connected (read only)"}}}}]}"#

private func receiptWords(_ language: String = "en") -> Words {
    Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: [language])
}

@MainActor
private func coach(_ thread: [(Int, String)], taf: Coach? = nil) async -> (CoachModel, CannedTransport) {
    let start: [(Int, String)] = taf == nil ? [(200, receiptCoachSetup), (200, receiptNoChats)] : []
    let transport = CannedTransport(start + thread)
    let model = CoachModel(cloud: CloudClient(transport: transport, session: receiptSession), taf: taf, sleep: { _ in })
    await model.load()
    return (model, transport)
}

/// Whether the point is drawn in the colour, within a runner's rounding, as stored or as sRGB.
private func receiptNear(_ bitmap: NSBitmapImageRep, x: Int, y: Int, _ wanted: UInt32) -> Bool {
    Snapshot.hexes(bitmap, x: x, y: y).contains { got in
        [16, 8, 0].allSatisfy { abs(Int((got >> $0) & 0xFF) - Int((wanted >> $0) & 0xFF)) <= 6 }
    }
}

/// The sheet's own size, as a sheet takes it: its width, and the height its content needs.
@MainActor
private func receiptSize<V: View>(_ view: V) -> CGSize {
    CGSize(width: ConnectReceiptSheet.width, height: ceil(NSHostingView(rootView: view).fittingSize.height))
}

let connectReceiptMacTests: [Test] = [
    Test("Coach's chat read again with the approval's connection made shows its receipt; Done closes it", awaiting: { @MainActor in
        let (model, transport) = await coach([(200, receiptWaiting), (200, receiptConnected)])
        try expectEqual(model.receipt, nil)
        try expectEqual(model.watchesConnection, true)
        await model.watchConnection()
        try expectEqual(model.receipt, ConnectReceipt(id: "s1:approval-1", heading: "Connect Qonto", line: "Qonto is connected (read only)"))
        // Made: nothing waits, so nothing more is read.
        try expectEqual(model.watchesConnection, false)
        try expectEqual(transport.sent.filter { $0.path.hasPrefix("/v1/tafs/taf-coach/conversation") }.count, 2)
        try expect(transport.sent.allSatisfy { $0.method == "GET" }, "watching only reads")
        model.closeReceipt()
        try expectEqual(model.receipt, nil)
    }),
    Test("no receipt for a connection first seen made, for another chat opened, or in a taf's own chat", awaiting: { @MainActor in
        // Made before Coach was read: nothing was seen to finish, and nothing is watched.
        let (first, _) = await coach([(200, receiptConnected)])
        try expectEqual(first.receipt, nil)
        try expectEqual(first.watchesConnection, false)
        // Another of Coach's chats, opened: its cards are never compared with the chat before's.
        let (other, _) = await coach([(200, receiptWaiting), (200, receiptConnected)])
        await other.open(chat: "s2")
        try expectEqual(other.receipt, nil)
        // A taf's own chat connects nothing here, and isn't watched.
        let (taf, _) = await coach([(200, receiptWaiting), (200, receiptConnected)], taf: Coach(id: "taf-1", name: "Refunds"))
        try expectEqual(taf.watchesConnection, false)
        await taf.watchConnection()
        try expectEqual(taf.receipt, nil)
    }),
    Test("the watch stops when its reads stop: at most its limit, and none once cancelled", awaiting: { @MainActor in
        // tafs cloud answers nothing new: the chat still waits, so it is read again up to the limit.
        let (model, transport) = await coach([(200, receiptWaiting)] + Array(repeating: (200, receiptWaiting), count: CoachModel.watchAtMost + 5))
        await model.watchConnection()
        try expectEqual(transport.sent.filter { $0.path.hasPrefix("/v1/tafs/taf-coach/conversation") }.count, 1 + CoachModel.watchAtMost)
        try expectEqual(model.receipt, nil)
        let (cancelled, sent) = await coach([(200, receiptWaiting), (200, receiptConnected)])
        let task = Task { @MainActor in await cancelled.watchConnection() }
        task.cancel()
        await task.value
        try expectEqual(sent.sent.filter { $0.path.hasPrefix("/v1/tafs/taf-coach/conversation") }.count, 1)
    }),
    Test("Disconnect is drawn for whoever manages the Cards, and a tap says to approve on another device, asking nothing", awaiting: { @MainActor in
        let receipt = ConnectReceipt(id: "k", heading: "Connect Qonto", line: "Qonto is connected (read only)")
        let words = receiptWords()
        let manages = receiptSize(ConnectReceiptSheet(receipt: receipt, done: {}).environment(\.words, words)).height
        let doesNot = receiptSize(ConnectReceiptSheet(receipt: receipt, managesCards: false, done: {}).environment(\.words, words)).height
        let tapped = receiptSize(ConnectReceiptSheet(receipt: receipt, disconnecting: true, done: {}).environment(\.words, words)).height
        try expect(manages > doesNot, "Disconnect only for whoever manages the Cards: \(manages) against \(doesNot)")
        try expect(tapped > manages, "after a tap, the gate's words under it: \(tapped) against \(manages)")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, language, dark) in [("connect-receipt-disconnect-en-light", "en", false), ("connect-receipt-disconnect-fr-dark", "fr", true)] {
            let view = ConnectReceiptSheet(receipt: receipt, disconnecting: true, done: {}).environment(\.words, receiptWords(language))
            guard let bitmap = Snapshot.bitmap(of: view, size: receiptSize(view), dark: dark), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG for \(name)") }
            try png.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }),
    Test("a receipt with no heading of its own heads with its line, else Connected, never empty", awaiting: { @MainActor in
        let words = receiptWords("fr")
        let named = receiptSize(ConnectReceiptSheet(receipt: ConnectReceipt(id: "k", heading: "Google Sheets", line: nil), done: {}).environment(\.words, words)).height
        let bare = receiptSize(ConnectReceiptSheet(receipt: ConnectReceipt(id: "k", heading: nil, line: nil), done: {}).environment(\.words, words)).height
        // The bare one heads with "Connecté" and drops the line under it, so it's one line shorter, never headless.
        try expect(bare < named && bare > named - 60, "bare \(bare), named \(named)")
    }),
    Test("the receipt draws board 5, tafs cloud's line or the shared Connected, and Done, on the theme's ground in light and dark", awaiting: { @MainActor in
        for dark in [false, true] {
            let view = ConnectReceiptSheet(receipt: ConnectReceipt(id: "k", heading: "Connect Qonto", line: "Qonto is connected (read only)"), done: {})
                .environment(\.words, receiptWords())
            let size = receiptSize(view)
            try expect(size.height > 250, "board 5, the heading, the line and Done: \(size.height)")
            guard let bitmap = Snapshot.bitmap(of: view, size: size, dark: dark) else { throw Failure(description: "no bitmap") }
            try expect(receiptNear(bitmap, x: 3, y: 3, dark ? Palette.background.dark : Palette.background.light), "the ground, dark: \(dark)")
            // Done is the brand's button across the foot, white on its fill: never the ground there.
            try expect(!receiptNear(bitmap, x: Int(size.width) / 2 - 60, y: Int(size.height) - 30, dark ? Palette.background.dark : Palette.background.light), "Done, dark: \(dark)")
        }
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let shots: [(String, ConnectReceipt, String, Bool)] = [
            ("connect-receipt-light", ConnectReceipt(id: "k", heading: "Connect Qonto", line: "Qonto is connected (read only)"), "en", false),
            ("connect-receipt-dark", ConnectReceipt(id: "k", heading: "Connect Qonto", line: "Qonto is connected (read only)"), "en", true),
            ("connect-receipt-plain-fr-light", ConnectReceipt(id: "k", heading: "Google Sheets", line: nil), "fr", false),
            ("connect-receipt-plain-fr-dark", ConnectReceipt(id: "k", heading: nil, line: nil), "fr", true),
        ]
        for (name, receipt, language, dark) in shots {
            let view = ConnectReceiptSheet(receipt: receipt, done: {}).environment(\.words, receiptWords(language))
            guard let bitmap = Snapshot.bitmap(of: view, size: receiptSize(view), dark: dark), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG for \(name)") }
            try png.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }),
]

import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let strings = URL(fileURLWithPath: ".shared/app/strings")
private let shots = URL(fileURLWithPath: "build/screenshots")

/// A call with a KIFF receipt; `read` marks it a read of data, as KIFF's `call.read_only`.
private func call(_ id: String, at: String, kind: String = "done", title: String, amount: String? = nil, taf: String = "taf_1", name: String = "Refunds", read: Bool = false) -> String {
    let text = amount.map { #","amount_text":"\#($0)""# } ?? ""
    // KIFF's own amount on the call, as the euros the line says: what a day's spend sums.
    let money = amount.map { #","amount":{"value":"\#($0.dropFirst())","unit":"EUR"}"# } ?? ""
    return #"{"id":"\#(id)","at":"\#(at)","kind":"\#(kind)","title":"\#(title)","detail":"Done, within its Card","time":"\#(at.dropFirst(11).prefix(5))","taf":{"id":"\#(taf)","name":"\#(name)"},"call":{"proposal_id":"\#(id)","read_only":\#(read),"receipt":{"trace_id":"01K\#(id)","status":"signed"}\#(money)}\#(text)}"#
}

/// Two days of calls, each with its reads.
private let page: String = {
    let calls = [
        call("c1", at: "2026-11-15T09:12:00Z", title: "Refund a payment", amount: "€120.00"),
        call("r1", at: "2026-11-15T09:10:00Z", title: "Read a case", read: true),
        call("r2", at: "2026-11-15T09:05:00Z", title: "Read a payment", read: true),
        call("c2", at: "2026-11-15T08:40:00Z", kind: "not_done", title: "Refund a payment", amount: "€40.00"),
        call("r3", at: "2026-11-15T08:30:00Z", title: "List invoices", taf: "taf_2", name: "Invoices", read: true),
        call("c3", at: "2026-11-14T16:00:00Z", kind: "refused", title: "Refund a payment", amount: "€900.00"),
        call("r4", at: "2026-11-14T15:00:00Z", title: "Read a case", read: true),
    ].joined(separator: ",")
    return #"{"hint":"Search by order, invoice, amount or action","entries":[\#(calls)],"groups":[]}"#
}()

private let home = #"{"tafs":[{"id":"taf_1","name":"Refunds","kiff_agent":"a1","color":1,"state":"working"},{"id":"taf_2","name":"Invoices","kiff_agent":"a2","color":4,"state":"idle"}]}"#
private let everyTaf = #"{"agents":{"a1":{"use":true,"oversee":true,"manage":false},"a2":{"use":true,"oversee":false,"manage":true}}}"#

@MainActor
private func reading(cloud: [(Int, String)], kiff: [(Int, String)] = []) -> (RecordModel, CannedTransport) {
    let transport = CannedTransport(cloud)
    let model = RecordModel(cloud: CloudClient(transport: transport, session: session),
                            account: AccountClient(transport: CannedTransport(kiff), session: session))
    return (model, transport)
}

@MainActor
private func shoot<V: View>(_ view: V, _ name: String, dark: Bool, height: CGFloat = 820) throws {
    try FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
    let words = Words.load(folder: strings, preferred: ["en"])
    guard let bitmap = Snapshot.bitmap(of: view.environment(\.words, words), size: CGSize(width: 980, height: height), dark: dark),
          let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG for \(name)") }
    try png.write(to: shots.appendingPathComponent("\(name).png"))
}

private let tafs: [Home.Taf] = (try? JSONDecoder().decode(Home.Page.self, from: Data(home.utf8)))?.tafs ?? []

let recordReadsScreenTests: [Test] = [
    Test("a day's reads fold into one line under All, Show shows them and Hide folds them; a filter shows no fold", awaiting: { @MainActor in
        let (model, _) = reading(cloud: [(200, page)])
        await model.load()
        let paris = AccountTime("Europe/Paris").calendar
        let days = Record.days(model.shown, calendar: paris, foldingReads: model.filter == .all)
        try expectEqual(days.map { $0.entries.map(\.id) }, [["c1", "c2"], ["c3"]])
        try expectEqual(days.map { $0.reads.map(\.id) }, [["r1", "r2", "r3"], ["r4"]])
        model.toggleReads(days[0].start)
        try expectEqual(model.openReads, [days[0].start])
        model.toggleReads(days[0].start)
        try expectEqual(model.openReads, [])
        model.filter = .moneyMoved
        try expectEqual(Record.days(model.shown, calendar: paris, foldingReads: model.filter == .all).flatMap(\.reads), [])
    }),
    Test("Export receipts shows only once KIFF says this person oversees or manages every taf", awaiting: { @MainActor in
        let (model, _) = reading(cloud: [], kiff: [(200, everyTaf)])
        try expectEqual(Record.seesEveryTaf(tafs, access: model.access), false)
        await model.loadAccess()
        try expectEqual(Record.seesEveryTaf(tafs, access: model.access), true)
        let (unread, _) = reading(cloud: [], kiff: [(500, "")])
        await unread.loadAccess()
        try expectEqual(unread.access, nil)
    }),
    Test("Export receipts reads the account's last days and saves both files in the folder chosen; cancelled, nothing is saved", awaiting: { @MainActor in
        let body = #"{"from":"2026-11-11","to":"2026-11-17","receipts":[],"csv":"day,taf\n","missing":1}"#
        let transport = CannedTransport([(200, body), (200, body), (403, #"{"error":"forbidden","words":"Only someone who sees every taf can export."}"#)])
        let exports = ReceiptsExportModel(cloud: CloudClient(transport: transport, session: session))
        exports.today = { ISO8601DateFormatter().date(from: "2026-11-17T10:00:00Z")! }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("record-export-mac-\(UUID().uuidString)")
        var asked: [String] = []
        exports.choose = { name in asked.append(name); return folder.appendingPathComponent(name) }
        let words = Words.load(folder: strings, preferred: ["en"])
        exports.open = true
        await exports.export(7, calendar: AccountTime("Europe/Paris").calendar, words: words)
        try expectEqual(transport.sent[0].path, "/v1/record/receipts?from=2026-11-11&to=2026-11-17")
        try expectEqual(asked, ["receipts-2026-11-11-to-2026-11-17"])
        try expectEqual(exports.saved?.map(\.lastPathComponent), ["receipts-2026-11-11-to-2026-11-17.json", "receipts-2026-11-11-to-2026-11-17.csv"])
        try expectEqual(try Data(contentsOf: exports.saved![0]), Data(body.utf8))
        try expectEqual(exports.missing, 1)
        try expectEqual(exports.open, false)
        try expectEqual(exports.why, nil)
        try? FileManager.default.removeItem(at: folder)
        // Cancelled: read, but nothing written.
        exports.choose = { _ in nil }
        await exports.export(30, calendar: AccountTime("Europe/Paris").calendar, words: words)
        try expectEqual(transport.sent[1].path, "/v1/record/receipts?from=2026-10-19&to=2026-11-17")
        try expectEqual(FileManager.default.fileExists(atPath: folder.path), false)
        // Refused: tafs cloud's words, in the shared line.
        await exports.export(90, calendar: AccountTime("Europe/Paris").calendar, words: words)
        try expectEqual(exports.why, "They couldn't be exported. Only someone who sees every taf can export.")
    }),
    Test("the screenshots: the Record with a day's reads folded, and shown, in light and dark", awaiting: { @MainActor in
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            let (model, _) = reading(cloud: [(200, page), (200, page)], kiff: [(200, everyTaf), (200, everyTaf)])
            await model.load()
            await model.loadAccess()
            try shoot(RecordView(model: model, tafs: tafs, timeZone: "Europe/Paris"), "record-reads-folded-\(mode)", dark: dark)
            let days = Record.days(model.shown, calendar: AccountTime("Europe/Paris").calendar, foldingReads: true)
            model.toggleReads(days[0].start)
            try shoot(RecordView(model: model, tafs: tafs, timeZone: "Europe/Paris"), "record-reads-shown-\(mode)", dark: dark, height: 1040)
        }
    }),
    Test("the screenshots: Export receipts with its ranges, and what the last export left, in light and dark", awaiting: { @MainActor in
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            let body = #"{"from":"2026-11-11","to":"2026-11-17","receipts":[],"csv":"","missing":2}"#
            let (model, _) = reading(cloud: [(200, page), (200, page)], kiff: [(200, everyTaf), (200, everyTaf)])
            await model.load()
            await model.loadAccess()
            let exports = ReceiptsExportModel(cloud: CloudClient(transport: CannedTransport([(200, body)]), session: session))
            exports.choose = { _ in nil }
            await exports.export(7, calendar: AccountTime("Europe/Paris").calendar, words: Words.load(folder: strings, preferred: ["en"]))
            exports.open = true
            try shoot(VStack(alignment: .leading) { ExportReceiptsRow(model: exports, timeZone: "Europe/Paris"); Spacer() }
                        .padding(Look.inset).frame(maxWidth: .infinity, alignment: .leading).background(Theme.background),
                      "record-export-row-\(mode)", dark: dark, height: 200)
            try shoot(RecordView(model: model, tafs: tafs, timeZone: "Europe/Paris"), "record-export-\(mode)", dark: dark)
        }
    }),
]

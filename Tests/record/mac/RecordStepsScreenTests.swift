import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let strings = URL(fileURLWithPath: ".shared/app/strings")
private let shots = URL(fileURLWithPath: "build/screenshots")

/// sha256("foo"), the value the signed fixture's decision step acted on (`onHashSignedReceipt`).
private let fooHash = "sha256:2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae"

/// A line whose call KIFF hashed what it acted on; `next` is tafs cloud's next step.
private func hashedLine(_ id: String, kind: String = "done", proposal: String = "p1", taf: String = "taf_1", name: String = "Refunds",
                        detail: String = "Done, within its Card", next: String? = nil) -> String {
    let after = next.map { #","next":\#($0)"# } ?? ""
    return #"{"id":"\#(id)","at":"2026-10-21T00:41:03Z","kind":"\#(kind)","title":"Refund a payment","detail":"\#(detail)","time":"02:41","amount_text":"€150.00","about":"Order 1042","taf":{"id":"\#(taf)","name":"\#(name)"},"call":{"proposal_id":"\#(proposal)","entity_id":"tc-a","on_hash":"\#(fooHash)","on_arg":"payment_intent","amount":{"value":"150.00","unit":"EUR"},"receipt":{"trace_id":"01KTRACE","status":"signed"}}\#(after)}"#
}

private func page(_ lines: [String]) -> String {
    #"{"hint":"Search by order, invoice, amount or action","entries":[\#(lines.joined(separator: ","))],"groups":[]}"#
}

private let home = #"{"tafs":[{"id":"taf_1","name":"Refunds","kiff_agent":"a1","color":1,"state":"working"}]}"#

@MainActor
private func reading(cloud: [(Int, String)], kiff: [(Int, String)] = []) -> (RecordModel, CannedTransport, CannedTransport) {
    let cloudTransport = CannedTransport(cloud)
    let kiffTransport = CannedTransport(kiff)
    let model = RecordModel(cloud: CloudClient(transport: cloudTransport, session: session),
                            account: AccountClient(transport: kiffTransport, session: session))
    return (model, cloudTransport, kiffTransport)
}

private func write(_ view: some View, _ name: String, size: CGSize) throws {
    try FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
    guard let bitmap = Snapshot.bitmap(of: view, size: size), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
    try png.write(to: shots.appendingPathComponent("\(name).png"))
}

let recordStepsScreenTests: [Test] = [
    Test("the list's lines are named from their taf's calls, only by the value KIFF hashed, best effort", awaiting: { @MainActor in
        let (model, cloud, _) = reading(cloud: [(200, page([hashedLine("e1"), hashedLine("e2", taf: "taf_2")])),
                                               (200, #"{"calls":[{"invocation":"tc-a","value":"foo"}]}"#), (503, "")])
        await model.list(["taf_1", "taf_2"])
        await model.load()
        try expectEqual(cloud.sent.map(\.path), ["/v1/record?q=", "/v1/tafs/taf_1/calls", "/v1/tafs/taf_2/calls"])
        try expectEqual(cloud.sent[1].method, "GET")
        // taf_1's calls name its line; taf_2's couldn't be read, but its key is the same, so the value
        // KIFF hashed names it too (refs are by KIFF's key, as the iPad's).
        try expectEqual(model.groups.flatMap(\.entries).map(\.onValue), ["foo", "foo"])
        let (other, _, _) = reading(cloud: [(200, page([hashedLine("e1")])), (200, #"{"calls":[{"invocation":"tc-a","value":"bar"}]}"#)])
        await other.list(["taf_1"])
        await other.load()
        try expectEqual(other.groups[0].entries[0].onValue, nil)
    }),
    Test("a taf the person only oversees is never read to name its lines; one listed later is", awaiting: { @MainActor in
        let (model, cloud, _) = reading(cloud: [(200, page([hashedLine("e1"), hashedLine("e2", taf: "taf_9", name: "Payouts")])),
                                               (200, #"{"calls":[{"invocation":"tc-a","value":"foo"}]}"#)])
        await model.list(["taf_1"])
        await model.load()
        try expectEqual(cloud.sent.map(\.path), ["/v1/record?q=", "/v1/tafs/taf_1/calls"])
        try expectEqual(model.groups.flatMap(\.entries).map(\.onValue), ["foo", "foo"])
        let (late, lateCloud, _) = reading(cloud: [(200, page([hashedLine("e1")])), (200, #"{"calls":[{"invocation":"tc-a","value":"foo"}]}"#)])
        await late.load()
        try expectEqual(lateCloud.sent.map(\.path), ["/v1/record?q="])
        await late.list(["taf_1"])
        try expectEqual(lateCloud.sent.map(\.path), ["/v1/record?q=", "/v1/tafs/taf_1/calls"])
        try expectEqual(late.groups[0].entries[0].onValue, "foo")
    }),
    Test("a held line is no longer waiting only once KIFF's held list, read after the lines, is without it", awaiting: { @MainActor in
        let held = #"{"exceptions":[{"id":"ex1","subject":"a1","action":"refund","created_at":"2026-10-21T00:41:03Z","proposal_id":"p2"}]}"#
        let (model, _, kiff) = reading(cloud: [(200, page([hashedLine("e1", kind: "held")]))], kiff: [(200, held), (500, "")])
        let unread = try AccountClient.decoder.decode(Record.Entry.self, from: Data(hashedLine("e1", kind: "held").utf8))
        try expect(model.isWaiting(unread), "unread: waiting")
        await model.load()
        let entry = model.groups[0].entries[0]
        try expectEqual(kiff.sent.map(\.path), ["/v1/me/card-exceptions?status=held"])
        try expect(!model.isWaiting(entry), "KIFF holds p2 only")
        await model.loadHeld()
        try expect(model.isWaiting(entry), "a failed read: waiting again")
    }),
    Test("after a 409 the lines are read again and KIFF's held list after them: a call held since still waits", awaiting: { @MainActor in
        let none = #"{"exceptions":[]}"#
        let heldP5 = #"{"exceptions":[{"id":"ex5","subject":"a1","action":"refund","created_at":"2026-10-21T00:41:03Z","proposal_id":"p5"}]}"#
        let first = #"{"hint":"","entries":[\#(hashedLine("e1"))],"groups":[],"next_cursor":"c1"}"#
        let (model, _, kiff) = reading(cloud: [(200, first), (409, #"{"error":"cursor_stale"}"#),
                                               (200, page([hashedLine("e5", kind: "held", proposal: "p5"), hashedLine("e1")]))],
                                       kiff: [(200, none), (200, heldP5)])
        await model.load()
        try expect(model.canContinue, "a next page")
        await model.more()
        try expectEqual(kiff.sent.count, 2)
        guard let line = model.groups.flatMap(\.entries).first(where: { $0.id == "e5" }) else { throw Failure(description: "no e5") }
        try expect(model.isWaiting(line), "held since the first read: still waiting")
    }),
    Test("the screenshots: a named line no longer waiting; the receipt's facts; a payment KIFF didn't sign; a case's steps", awaiting: { @MainActor in
        let words = Words.load(folder: strings, preferred: ["en"])
        let tafs = (try? JSONDecoder().decode(Home.Page.self, from: Data(home.utf8)))?.tafs ?? []
        let (list, _, _) = reading(cloud: [(200, page([hashedLine("e1", kind: "held", detail: "Waiting for you"), hashedLine("e2")])),
                                           (200, #"{"calls":[{"invocation":"tc-a","value":"foo"}]}"#)],
                                   kiff: [(200, #"{"exceptions":[]}"#)])
        await list.list(["taf_1"])
        await list.load()
        try expect(list.groups[0].entries.allSatisfy { $0.onValue == "foo" }, "named")
        try write(RecordView(model: list, tafs: tafs, timeZone: "Europe/Paris").environment(\.words, words), "record-row-on-en", size: CGSize(width: 980, height: 760))
        for (name, value) in [("receipt-facts-en", "foo"), ("receipt-payment-mismatch-en", "bar")] {
            let (model, _, _) = reading(cloud: [], kiff: [(200, onHashSignedReceipt)])
            model.receiptSigner = onHashTestSigner
            var entry = try AccountClient.decoder.decode(Record.Entry.self, from: Data(hashedLine("e1").utf8))
            entry.onValue = value
            await model.openReceipt(entry)
            try expectEqual(model.receiptCheck, .verified(signer: onHashTestSigner))
            let key = ReceiptSteps(model.receiptRaw!).mismatchKey(onValue: entry.onValue, amount: entry.amount, answer: entry.answer, sha256: PasskeyCrypto.sha256)
            try expectEqual(key, value == "foo" ? nil : "receipt.check.payment_mismatch")
            let sheet = ReceiptSheet(model: model, entry: entry, tafs: tafs, timeZone: "Europe/Paris")
                .environment(\.words, words).environment(\.openTaf, { (_: Home.Taf) in })
            try write(sheet, name, size: CGSize(width: 600, height: 640))
        }
        let (steps, _, _) = reading(cloud: [])
        let next = #"{"kind":"reconnect","words":"Connect Stripe again to refund it","tool":"stripe_create_refund"}"#
        let entries = try [hashedLine("e1", kind: "not_done", detail: "Not sent: Stripe signed tafs out", next: next),
                           hashedLine("e2", taf: "taf_9", name: "Payouts")].map { try AccountClient.decoder.decode(Record.Entry.self, from: Data($0.utf8)) }
        try expectEqual(entries[0].next?.words, "Connect Stripe again to refund it")
        let view = VStack(alignment: .leading, spacing: 10) {
            RecordStepRow(model: steps, entry: entries[0], listed: true, opensCase: false)
            RecordStepRow(model: steps, entry: entries[1], listed: false, opensCase: false)
        }
        .padding(20).background(Theme.background).environment(\.words, words)
        try write(view, "record-case-steps-en", size: CGSize(width: 560, height: 360))
    }),
]

import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

/// A Record line whose call has a KIFF receipt, for the fixture's trace; `answer` and `amount` are its
/// call's.
private func line(trace: String = "01KTRACE", status: String = "signed", amount: String = "", answer: String = "", at: String = "2026-10-21T00:41:03Z") throws -> Record.Entry {
    let extra = [amount.isEmpty ? nil : #""amount":\#(amount)"#, answer.isEmpty ? nil : #""answer":{"decision":"\#(answer)"}"#].compactMap { $0 }.map { "," + $0 }.joined()
    let json = #"{"id":"e1","at":"\#(at)","kind":"done","title":"Refund a payment","detail":"Within its Card","time":"02:41","amount_text":"€150.00","taf":{"id":"taf_1","name":"Refunds"},"about":"Order 1042","call":{"proposal_id":"p","receipt":{"trace_id":"\#(trace)","status":"\#(status)"}\#(extra)}}"#
    return try AccountClient.decoder.decode(Record.Entry.self, from: Data(json.utf8))
}

@MainActor
private func model(kiff: [(Int, String)], signer: String = receiptTestSigner) -> (RecordModel, CannedTransport) {
    let transport = CannedTransport(kiff)
    let model = RecordModel(cloud: CloudClient(transport: CannedTransport([]), session: session),
                            account: AccountClient(transport: transport, session: session))
    model.receiptSigner = signer
    return (model, transport)
}

let receiptSheetTests: [Test] = [
    Test("a line's receipt is read from KIFF by its escaped trace, and checked on this Mac with CryptoKit's SHA-256", awaiting: { @MainActor in
        let (model, transport) = model(kiff: [(200, signedReceipt)])
        await model.openReceipt(try line(trace: "01K/TRACE"))
        try expectEqual(transport.sent.count, 1)
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "GET /v1/receipts/01K%2FTRACE")
        try expectEqual(transport.sent[0].headers["Authorization"], "Bearer tok")
        try expectEqual(model.receiptCheck, .verified(signer: receiptTestSigner))
        try expectEqual(model.receiptRaw, Data(signedReceipt.utf8))
        // CryptoKit's SHA-256 is the Core tests' own, over KIFF's vector.
        try expectEqual(PasskeyCrypto.sha256(Data("abc".utf8)), testSHA256(Data("abc".utf8)))
    }),
    Test("in production the pinned signer is KIFF's: a receipt by another key isn't KIFF's", awaiting: { @MainActor in
        let (model, _) = model(kiff: [(200, signedReceipt)], signer: ReceiptCheck.kiffSigner)
        try expectEqual(RecordModel(cloud: CloudClient(transport: CannedTransport([]), session: session)).receiptSigner, ReceiptCheck.kiffSigner)
        await model.openReceipt(try line())
        try expectEqual(model.receiptCheck, .failed(.notKiff))
    }),
    Test("a line with no receipt opens nothing and reads nothing", awaiting: { @MainActor in
        let (model, transport) = model(kiff: [])
        let json = #"{"id":"e2","at":"2026-10-21T00:41:03Z","kind":"done","title":"Refund","detail":"","time":"02:41","taf":{"id":"taf_1","name":"Refunds"},"call":{"proposal_id":"p"}}"#
        await model.openReceipt(try AccountClient.decoder.decode(Record.Entry.self, from: Data(json.utf8)))
        try expectEqual(model.receiptEntry, nil)
        try expectEqual(transport.sent.count, 0)
    }),
    Test("KIFF's refusal says why in plain words, and Try again reads it again", awaiting: { @MainActor in
        let (model, transport) = model(kiff: [(503, #"{"error":"unavailable"}"#), (200, signedReceipt)])
        await model.openReceipt(try line())
        try expectEqual(model.receiptCheck, nil)
        try expect(model.receiptError?.isEmpty == false)
        try expect(model.receiptError?.range(of: "unavailable") == nil, "never KIFF's code")
        await model.loadReceipt()
        try expectEqual(model.receiptError, nil)
        try expectEqual(model.receiptCheck, .verified(signer: receiptTestSigner))
        try expectEqual(transport.sent.count, 2)
    }),
    Test("what happened shows only for a checked receipt that matches the line: not for another amount or answer, nor unsigned or changed", awaiting: { @MainActor in
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        let (verified, _) = model(kiff: [(200, signedReceipt)])
        await verified.openReceipt(try line())
        let steps = ReceiptSteps(verified.receiptRaw!)
        try expect(ReceiptCheck.showsWhatHappened(verified.receiptCheck, mismatch: steps.amountMismatch(nil) || steps.answerMismatch(nil)))
        // A receipt whose decision step signed another amount than the line's, and one that refused.
        let signedAmount = Data(#"{"causal_chain":[{"kind":"decision","data":{"amount":{"value":"20.00","unit":"EUR"}}},{"kind":"hold_settled","data":{"answer":"reject"}}]}"#.utf8)
        let other = ReceiptSteps(signedAmount)
        try expect(other.amountMismatch(try line(amount: #"{"value":"150.00","unit":"EUR"}"#).amount))
        try expect(other.answerMismatch(try line(answer: "approved_once").answer))
        let pending = signedReceipt.replacingOccurrences(of: #""attestation":\{[^}]*\}"#, with: #""attestation":null"#, options: .regularExpression)
        let (unsigned, _) = model(kiff: [(200, pending)])
        await unsigned.openReceipt(try line())
        try expectEqual(unsigned.receiptCheck, .notSignedYet)
        try expect(!ReceiptCheck.showsWhatHappened(unsigned.receiptCheck, mismatch: false))
        let changed = signedReceipt.replacingOccurrences(of: #""data_hash":"bb""#, with: #""data_hash":"bc""#)
        let (failed, _) = model(kiff: [(200, changed)])
        await failed.openReceipt(try line())
        try expectEqual(failed.receiptCheck, .failed(.signatureMismatch))
        try expect(!ReceiptCheck.showsWhatHappened(failed.receiptCheck, mismatch: false))
        try expectEqual(words(ReceiptCheck.Failure.signatureMismatch.key), "The signature doesn't match these steps.")
    }),
    Test("the screenshots: KIFF's receipt checked (English and French), not signed yet, and changed (French)", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pending = signedReceipt.replacingOccurrences(of: #""attestation":\{[^}]*\}"#, with: #""attestation":null"#, options: .regularExpression)
        let changed = signedReceipt.replacingOccurrences(of: #""data_hash":"bb""#, with: #""data_hash":"bc""#)
        let cases: [(String, String, String)] = [
            ("receipt-checked-en", signedReceipt, "en"), ("receipt-not-signed-en", pending, "en"),
            ("receipt-changed-fr", changed, "fr"), ("receipt-checked-fr", signedReceipt, "fr"),
        ]
        for (name, receipt, language) in cases {
            let (model, _) = model(kiff: [(200, receipt)])
            let entry = try line()
            await model.openReceipt(entry)
            let view = ReceiptSheet(model: model, entry: entry).environment(\.words, Words.load(folder: strings, preferred: [language]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 600, height: 640)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }),
]

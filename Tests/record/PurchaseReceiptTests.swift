import Foundation

/// The contract's receipt (`contracts/purchase.json`, `receipt.value`) as the bytes the app would read.
private func contractReceipt(_ change: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
    let data = try Data(contentsOf: URL(fileURLWithPath: ".shared/contracts/purchase.json"))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          var receipt = (object["receipt"] as? [String: Any])?["value"] as? [String: Any] else { throw Failure(description: "purchase.json has no receipt") }
    change(&receipt)
    return try JSONSerialization.data(withJSONObject: receipt)
}

let recordPurchaseReceiptTests: [Test] = [
    Test("the contract's receipt reads: the case, how it was paid, who approved and how, the three states and every word") {
        let r = try AccountClient.decoder.decode(PurchaseReceipt.self, from: try contractReceipt())
        try expect(PurchaseReceipt.paths.contains(r.path), "a known path: \(r.path)")
        try expect(r.approver.isSelf && r.approver.method != nil, "approved by this person, and how")
        try expect(r.amounts.captured <= r.amounts.approvedMax, "captured within what was approved")
        try expect(!r.states.case.isEmpty && !r.states.money.isEmpty && !r.states.order.isEmpty, "three states, apart")
        try expect(r.words.state != nil && r.words.allowed != nil && r.words.card != nil && r.words.order != nil && r.words.refunds != nil,
                   "the receipt's words beyond its line")
    },
    Test("the order's line is `order`, and a receipt issued before the rename still shows it from `shipping`") {
        func words(_ w: [String: Any]) throws -> PurchaseReceipt.Words {
            try AccountClient.decoder.decode(PurchaseReceipt.self, from: try contractReceipt { $0["words"] = w }).words
        }
        try expectEqual(try words(["line": "Bought", "order": "Ships to Lyon"]).order, "Ships to Lyon")
        try expectEqual(try words(["line": "Bought", "shipping": "Ships to Lyon"]).order, "Ships to Lyon")
        try expectEqual(try words(["line": "Bought", "order": "New", "shipping": "Old"]).order, "New")
        try expect(try words(["line": "Bought"]).order == nil, "none sent, none shown")
    },
    Test("what KIFF signed is the receipt's canonical JSON without its sig, from the bytes as received") {
        let raw = try contractReceipt()
        let signed = try PurchaseReceipt.signedBytes(raw)
        let text = String(decoding: signed, as: UTF8.self)
        try expect(!text.contains("\"sig\""), "no sig in what's signed")
        try expect(text.contains("\"case_id\"") && text.contains("\"words\""), "the rest is there")
        // Canonical: the same receipt with its keys in another order signs the same bytes.
        let reordered = try JSONSerialization.data(withJSONObject: try JSONSerialization.jsonObject(with: raw), options: [.sortedKeys])
        try expectEqual(try PurchaseReceipt.signedBytes(reordered), signed)
    },
    Test("a receipt checks out only for the case approved, and only with KIFF's signature") {
        let raw = try contractReceipt()
        let r = try AccountClient.decoder.decode(PurchaseReceipt.self, from: raw)
        var asked: (String, Data, String)?
        let ok = PurchaseReceipt.check(raw, read: r, caseID: r.caseID, digest: r.digest) { sig, msg, kid in asked = (sig, msg, kid); return true }
        try expect(ok == nil, "checks out")
        try expectEqual(asked?.2, r.kid)
        try expectEqual(asked?.1, try PurchaseReceipt.signedBytes(raw))
        try expectEqual(PurchaseReceipt.check(raw, read: r, caseID: r.caseID, digest: String(repeating: "0", count: 64)) { _, _, _ in true }, .notThisCase)
        try expectEqual(PurchaseReceipt.check(raw, read: r, caseID: r.caseID, digest: r.digest) { _, _, _ in false }, .badSignature)
    },
    Test("a receipt naming a path this app doesn't know, or a case that can't be read, isn't read at all") {
        for change in [{ (r: inout [String: Any]) in r["path"] = "wire" }, { r in r["case_id"] = "pc:1" }, { r in r["digest"] = "abc" }] {
            do { _ = try AccountClient.decoder.decode(PurchaseReceipt.self, from: try contractReceipt(change)); throw Failure(description: "read") } catch is DecodingError {}
        }
    },
]

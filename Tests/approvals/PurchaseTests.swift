import Foundation

/// tafs's purchase contract (`contracts/purchase.json`), read from the shared files at the pin.
private func contract() throws -> [String: Any] {
    let data = try Data(contentsOf: URL(fileURLWithPath: ".shared/contracts/purchase.json"))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure(description: "purchase.json isn't an object") }
    return object
}

private func section(_ name: String, _ key: String = "value") throws -> [String: Any] {
    guard let part = try contract()[name] as? [String: Any], let value = part[key] as? [String: Any] else {
        throw Failure(description: "purchase.json has no \(name).\(key)")
    }
    return value
}

/// A held call carrying the contract's purchase, as KIFF's held list serves it.
private func heldPurchase(_ purchase: Any) throws -> Data {
    let one: [String: Any] = ["id": "exc_7f3a", "subject": "agent_shop", "action": "buy", "created_at": "2026-11-28T09:14:00Z",
                              "accounting_version": 1, "purchase": purchase]
    return try JSONSerialization.data(withJSONObject: ["exceptions": [one]])
}

private struct Held: Decodable { let exceptions: [HeldCall] }

let approvalsPurchaseTests: [Test] = [
    Test("the contract's approval reads as a purchase: the shop, the total, the lines and charges, every word as sent") {
        let approval = try section("approval")
        let p = try AccountClient.decoder.decode(Purchase.self, from: JSONSerialization.data(withJSONObject: approval))
        try expectEqual(p.version, 1)
        try expect(Purchase.isDigest(p.digest), "the digest is 64 hex")
        try expect(p.words.title.hasPrefix("Buy from "), "the shop: \(p.words.title)")
        try expect(!p.words.total.isEmpty && p.words.totalNote != nil, "the total, and what it includes")
        try expect(!p.words.lines.isEmpty && p.words.lines.allSatisfy { !$0.name.isEmpty && !$0.amount.isEmpty }, "each line as parts")
        try expect(!p.words.charges.isEmpty, "the charges, so the open list adds up")
        try expect(p.words.grant != nil && p.words.priceRule != nil && p.words.buysNow != nil, "what the approval allows, beside it")
        try expect(p.words.nothingUntil != nil && p.words.prompt != nil, "and what's said before the answer")
    },
    Test("the answer to a purchase's hold is the contract's vector, byte for byte: kiff.answer.v1's lines, then the purchase line") {
        let answer = try section("answer")
        guard let vector = (try contract()["answer"] as? [String: Any])?["vector"] as? [String: Any],
              let purchase = answer["purchase"] as? [String: Any],
              let caseID = purchase["case_id"] as? String, let version = purchase["version"] as? Int, let digest = purchase["digest"] as? String
        else { throw Failure(description: "purchase.json's answer has no vector") }
        let approval = try section("approval")
        var withWords = approval
        withWords["case_id"] = caseID
        withWords["version"] = version
        withWords["digest"] = digest
        let p = try AccountClient.decoder.decode(Purchase.self, from: JSONSerialization.data(withJSONObject: withWords))
        let message = KIFFMessage.answer(tenant: vector["tenant"] as? String ?? "", callID: vector["exception_id"] as? String ?? "",
                                         answer: .approveOnce, nextStep: nil, accountingVersion: vector["hold_version"] as? Int ?? 0,
                                         signedAt: vector["signed_at"] as? String ?? "", purchase: p)
        try expectEqual(message, vector["message"] as? String ?? "")
        try expect(message.hasSuffix("\npurchase:\(caseID):\(version):\(digest)"), "the purchase line comes last")
    },
    Test("a held purchase is drawn as one, and a refusal signs its purchase line too") {
        let approval = try section("approval")
        let calls = try AccountClient.decoder.decode(Held.self, from: try heldPurchase(approval)).exceptions
        let call = try calls.first ?? { throw Failure(description: "no call") }()
        try expect(call.purchase != nil && !call.purchaseUnreadable, "read as a purchase")
        var signed = ""
        let transport = CannedTransport([(200, "{}")])
        let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")
        let client = AccountClient(transport: transport, session: session, signMessage: { signed = $0; return "SIG" })
        try await client.refuse(call, at: ISO8601DateFormatter().date(from: "2026-11-28T09:15:09Z")!)
        try expect(signed.hasSuffix("\n" + (call.purchase?.signedLine ?? "?")), "the refusal binds the case too: \(signed)")
    },
    Test("a purchase this app can't sign as sent is never answered here: a bad id, digest or version, or no shop or total") {
        let approval = try section("approval")
        func with(_ change: (inout [String: Any]) -> Void) throws -> HeldCall {
            var p = approval
            change(&p)
            return try AccountClient.decoder.decode(Held.self, from: try heldPurchase(p)).exceptions[0]
        }
        let broken: [(String, (inout [String: Any]) -> Void)] = [
            ("a colon in the id", { $0["case_id"] = "pc_1:2" }),
            ("a new line in the id", { $0["case_id"] = "pc_1\npurchase:x" }),
            ("a digest that isn't 64 hex", { $0["digest"] = "ABC" }),
            ("version 0", { $0["version"] = 0 }),
            ("no total", { p in var w = p["words"] as? [String: Any] ?? [:]; w["total"] = " "; p["words"] = w }),
            ("a line that doesn't read", { p in var w = p["words"] as? [String: Any] ?? [:]; w["lines"] = [["name": "x"]]; p["words"] = w }),
        ]
        for (why, change) in broken {
            let call = try with(change)
            try expect(call.purchase == nil && call.purchaseUnreadable, why)
            let transport = CannedTransport([(200, "{}")])
            let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")
            let client = AccountClient(transport: transport, session: session, signMessage: { _ in "SIG" })
            do { try await client.refuse(call); throw Failure(description: "\(why): it was sent") } catch let error as KIFFError {
                try expectEqual(error, .refused(status: 0, code: "purchase_unreadable"))
            }
            try expect(transport.sent.isEmpty, "\(why): nothing sent")
        }
    },
    Test("a call with no purchase is as before: no purchase line in what's signed") {
        let message = KIFFMessage.answer(tenant: "t1", callID: "exc_1", answer: .reject, nextStep: nil, accountingVersion: 3, signedAt: "2026-11-28T09:15:09Z")
        try expectEqual(message, "kiff.answer.v1\nt1\nexc_1\nreject\n\n\n3\n2026-11-28T09:15:09Z")
    },
]

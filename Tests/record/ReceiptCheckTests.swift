import Foundation

/// A receipt signed the way KIFF signs, written by the receipts endpoint's encoder, with a test key: the
/// iPad's fixture (`ReceiptCheckTests.signed`), signed by KIFF's own Go signer. Its chain has what a
/// re-encoding would change: escaped <, > and &, a map's sorted keys, and Go's 1e+21.
let signedReceipt = #"{"schema_version":"0.1","trace_id":"01KTRACE","tenant_id":"t_1","entity_id":"pi_3Q_test","entity_type":"Payment","action_name":"stripe_create_refund","outcome":"allowed","issued_at":"2026-10-21T00:41:03.12Z","causal_chain":[{"sequence":1,"kind":"decision","actor_id":"agt_refunds","occurred_at":"2026-10-21T00:41:03.12Z","message":"held: over \u003c€100\u003e \u0026 more","data_hash":"aa"},{"sequence":2,"kind":"settled","occurred_at":"2026-10-21T00:41:04.12Z","data_hash":"bb","data":{"amount":15000,"answer":"approved_once","big":1e+21,"tool":{"status":"done"}}}],"attestation":{"algorithm":"secp256k1+keccak256","signature":"79917d81e09b24ef196e5b71c72ea1c5cc8951e628b63922072ef59832d0a43e4a0b198bead4ddad1312fe7f1e9b6d41b5f617fe08c5aed59abcd9e5b225a2ce01","wallet_address":"0x2c7536e3605d9c16a7a3d7b1898e529396a65c23","anchor_tx_hash":"","anchored_at":"2026-10-21T00:41:03.12Z"},"risk_score":null,"compliance_map":null,"insurer_envelope":null}"#
let receiptTestSigner = "0x2c7536e3605d9c16a7a3d7b1898e529396a65c23"

private func check(_ receipt: String, signer: String = receiptTestSigner) -> ReceiptCheck {
    ReceiptCheck.check(Data(receipt.utf8), signer: signer, sha256: testSHA256)
}

private func hex(_ data: Data) -> String { ReceiptCheck.hexEncode(data) }
private func bytes(_ hex: String) -> Data { ReceiptCheck.hexDecode(hex)! }

/// Recovery vectors from python-ecdsa 0.19 (SECP256k1, RFC 6979 signatures), the address from
/// pycryptodome's Keccak-256: secret 1, a small secret, and n − 1. Each with its digest, r ‖ s ‖ v, and
/// the same signature with a high s (n − s, its parity flipped), which libsecp256k1 takes too.
private let vectors: [(digest: String, signature: String, high: String, address: String)] = [
    ("405839d62904fd64a901c2443d79f712f403395dea5652b22f01e62211b8a735",
     "5c3a4bcc8502240a0fd0f36f53cd894c0adda9839c8e81365f50af54b120a278644e220addfc76abf25e982ef4268e07d7008cac9df8be2f1c25671e047555d001",
     "5c3a4bcc8502240a0fd0f36f53cd894c0adda9839c8e81365f50af54b120a2789bb1ddf5220389540da167d10bd971f6e3ae503a114fe20ca3acf76ecbc0eb7100",
     "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf"),
    ("08cce00198fa027b6f8622147d9633cedf91f1cef2a4d97d4f5a6f910f7e178e",
     "23d425c7dc9f869cd87e7b5b13dd12216503c452b21b522ec40acafdbeb6395e2a5af91d63726eafe1ceb284060c2d3bf09a8c187dfdd79d3f8923e7fac57d5401",
     "23d425c7dc9f869cd87e7b5b13dd12216503c452b21b522ec40acafdbeb6395ed5a506e29c8d91501e314d7bf9f3d2c2ca1450ce314ac89e80493aa4d570c3ed00",
     "0xab615a1598370c1f9756290ea874faa4b2185abd"),
    ("de7c559cd629d79d230c0694b1c38429f66763aff1362dbc8129d42f5c5111cc",
     "bbe8862181c51db52199e7406463334518b0fd909b980bf6c5400fb29e83cd3440b23aa9889da38aad7ff2e7cff6fea86066aea6318a2575ebf23fe9ef97e1a200",
     "bbe8862181c51db52199e7406463334518b0fd909b980bf6c5400fb29e83cd34bf4dc55677625c7552800d18300901565a482e407dbe7ac5d3e01ea2e09e5f9f01",
     "0x80c0dbf239224071c59dd8970ab9d542e3414ab2"),
]

let receiptCheckTests: [Test] = [
    Test("Keccak-256 matches the standard vectors and Go's, either side of a block") {
        try expectEqual(hex(Keccak.hash256(Data())), "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
        try expectEqual(hex(Keccak.hash256(Data("abc".utf8))), "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")
        try expectEqual(hex(Keccak.hash256(Data(repeating: 0x61, count: 135))), "34367dc248bbd832f4e3e69dfaac2f92638bd0bbd18f2912ba4ef454919cf446")
        try expectEqual(hex(Keccak.hash256(Data(repeating: 0x61, count: 136))), "a6c4d403279fe3e0af03729caada8374b5ca54d8065329a3ebcaeb4b60aa386e")
        try expectEqual(hex(Keccak.hash256(Data(repeating: 0x61, count: 300))), "5b7e0e47a96f32a88b4f14ca177982790807c40e1a105742ba0fc1babe1ef826")
    },
    Test("secp256k1 recovers the signer of another library's signatures, with v as 0–1 or 27–28, and a high s") {
        for vector in vectors {
            let digest = bytes(vector.digest), signature = bytes(vector.signature)
            try expectEqual(Secp256k1.recoverAddress(digest: digest, signature: signature), vector.address)
            var v27 = signature
            v27[64] += 27
            try expectEqual(Secp256k1.recoverAddress(digest: digest, signature: v27), vector.address)
            try expectEqual(Secp256k1.recoverAddress(digest: digest, signature: bytes(vector.high)), vector.address)
            // The other parity is another key, never this one.
            var flipped = signature
            flipped[64] ^= 1
            try expect(Secp256k1.recoverAddress(digest: digest, signature: flipped) != vector.address)
            // Another digest recovers another key.
            var other = digest
            other[0] ^= 1
            try expect(Secp256k1.recoverAddress(digest: other, signature: signature) != vector.address)
        }
    },
    Test("a signature that can't be read recovers nothing, and stops nothing") {
        let digest = Data(repeating: 1, count: 32)
        try expectEqual(Secp256k1.recoverAddress(digest: digest, signature: Data(repeating: 0, count: 65)), nil)
        try expectEqual(Secp256k1.recoverAddress(digest: digest, signature: Data(repeating: 0xFF, count: 65)), nil)
        try expectEqual(Secp256k1.recoverAddress(digest: digest, signature: Data(repeating: 1, count: 64)), nil)
        try expectEqual(Secp256k1.recoverAddress(digest: Data(repeating: 1, count: 31), signature: bytes(vectors[0].signature)), nil)
        // r = n, and s = n: neither is below n.
        let n = "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141"
        try expectEqual(Secp256k1.recoverAddress(digest: digest, signature: bytes(n + String(vectors[0].signature.dropFirst(64)))), nil)
        try expectEqual(Secp256k1.recoverAddress(digest: digest, signature: bytes(String(vectors[0].signature.prefix(64)) + n + "00")), nil)
        // v outside 0–3 (and 27–30).
        var v = bytes(vectors[0].signature)
        v[64] = 4
        try expectEqual(Secp256k1.recoverAddress(digest: digest, signature: v), nil)
    },
    Test("a receipt KIFF signed checks out, as the iPad's fixture does") {
        try expectEqual(check(signedReceipt), .verified(signer: receiptTestSigner))
    },
    Test("the chain is hashed as written, never re-encoded") {
        let chain = String(data: ReceiptJSON.value(of: "causal_chain", in: Data(signedReceipt.utf8))!, encoding: .utf8)!
        try expect(chain.hasPrefix(#"[{"sequence":1,"kind":"decision""#))
        // As Go wrote it, escaped: a decoder and re-encoder would write "<€100> & more".
        try expect(chain.range(of: #"\u003c€100\u003e \u0026 more"#) != nil)
        try expect(chain.hasSuffix(#""big":1e+21,"tool":{"status":"done"}}}]"#))
        try expectEqual(ReceiptJSON.value(of: "missing", in: Data(signedReceipt.utf8)), nil)
    },
    Test("a receipt that repeats a key, at its top or in its attestation, couldn't be read") {
        try expectEqual(ReceiptJSON.keys(of: Data(#"{"a":1,"b":{"a":2},"c":[{"a":3}]}"#.utf8)), ["a", "b", "c"])
        try expect(ReceiptJSON.keysAreUnique(in: Data(signedReceipt.utf8)))
        let twice = String(signedReceipt.dropLast()) + #","causal_chain":[{"sequence":1,"kind":"decision","message":"refund €5"}]}"#
        try expectEqual(check(twice), .failed(.unreadable))
        let signer = signedReceipt.replacingOccurrences(of: #""algorithm":"secp256k1+keccak256","#,
                                                        with: #""algorithm":"secp256k1+keccak256","wallet_address":"0x0","#)
        try expect(signer != signedReceipt)
        try expectEqual(check(signer), .failed(.unreadable))
        try expectEqual(check(signedReceipt), .verified(signer: receiptTestSigner))
    },
    Test("a changed byte in the chain doesn't match its signature") {
        let changed = signedReceipt.replacingOccurrences(of: #""data_hash":"bb""#, with: #""data_hash":"bc""#)
        try expect(changed != signedReceipt)
        try expectEqual(check(changed), .failed(.signatureMismatch))
        let amount = signedReceipt.replacingOccurrences(of: #""amount":15000"#, with: #""amount":95000"#)
        try expectEqual(check(amount), .failed(.signatureMismatch))
    },
    Test("a receipt signed by another key isn't KIFF's: production pins KIFF's signer") {
        try expectEqual(ReceiptCheck.check(Data(signedReceipt.utf8), sha256: testSHA256), .failed(.notKiff))
        try expectEqual(ReceiptCheck.kiffSigner, "0x2f297affd7b62ef712a1e3158421ccb4bf2efcbe")
    },
    Test("not signed yet isn't a failure, and an unknown algorithm or a short signature fails") {
        let pending = signedReceipt.replacingOccurrences(of: #""attestation":\{[^}]*\}"#, with: #""attestation":null"#, options: .regularExpression)
        try expect(pending != signedReceipt)
        try expectEqual(check(pending), .notSignedYet)
        let other = signedReceipt.replacingOccurrences(of: "secp256k1+keccak256", with: "ed25519")
        try expectEqual(check(other), .failed(.unknownSignature))
        let short = signedReceipt.replacingOccurrences(of: #""signature":"[0-9a-f]+""#, with: #""signature":"00""#, options: .regularExpression)
        try expectEqual(check(short), .failed(.malformedSignature))
        try expectEqual(check("not json"), .failed(.unreadable))
        let noChain = signedReceipt.replacingOccurrences(of: #""causal_chain""#, with: #""steps""#)
        try expectEqual(check(noChain), .failed(.noSteps))
    },
    Test("each failure says why in the shared words") {
        try expectEqual(ReceiptCheck.Failure.unreadable.key, "receipt.check.unreadable")
        try expectEqual(ReceiptCheck.Failure.notKiff.key, "receipt.check.not_kiff")
        try expectEqual(ReceiptCheck.Failure.signatureMismatch.key, "receipt.check.signature_mismatch")
        try expectEqual(ReceiptCheck.Failure.malformedSignature.key, "receipt.check.malformed_signature")
        try expectEqual(ReceiptCheck.Failure.unknownSignature.key, "receipt.check.unknown_signature")
        try expectEqual(ReceiptCheck.Failure.noSteps.key, "receipt.check.no_steps")
    },
    Test("what happened is drawn only for a receipt this Mac checked as KIFF's, and only when it matches the line") {
        try expect(ReceiptCheck.showsWhatHappened(.verified(signer: receiptTestSigner), mismatch: false))
        try expect(!ReceiptCheck.showsWhatHappened(.verified(signer: receiptTestSigner), mismatch: true), "KIFF's, but another line's")
        try expect(!ReceiptCheck.showsWhatHappened(.failed(.notKiff), mismatch: false))
        try expect(!ReceiptCheck.showsWhatHappened(.notSignedYet, mismatch: false))
        try expect(!ReceiptCheck.showsWhatHappened(nil, mismatch: false), "still checking")
    },
    Test("the receipt's steps, its issue time, and the line's amount and answer against them") {
        let steps = ReceiptSteps(Data(signedReceipt.utf8))
        try expectEqual(steps.steps.map(\.words), ["held: over <€100> & more", "settled"])
        try expectEqual(steps.steps.map(\.kind), ["decision", "settled"])
        try expect(steps.issuedAt != nil)
        try expect(steps.signature?.hasPrefix("79917d81") == true)
        let withAmount = Data(#"{"causal_chain":[{"kind":"decision","data":{"amount":{"value":"150.00","unit":"EUR"}}},{"kind":"hold_settled","data":{"answer":"reject"}}]}"#.utf8)
        let signed = ReceiptSteps(withAmount)
        try expect(!signed.amountMismatch(Record.Amount(value: "150", unit: "eur")), "the same number, in the same unit")
        try expect(signed.amountMismatch(Record.Amount(value: "150.01", unit: "EUR")))
        try expect(signed.amountMismatch(Record.Amount(value: "150", unit: "USD")))
        try expect(!signed.amountMismatch(nil), "a line with no amount isn't another's")
        try expect(!signed.answerMismatch("refused"), "KIFF records a refusal as reject")
        try expect(signed.answerMismatch("approved_once"))
        try expect(!signed.answerMismatch(nil))
    },
    Test("amounts match as numbers in the same unit, as the iPad's and Windows'") {
        try expect(Record.Amount(value: "150.00", unit: "EUR").same(as: Record.Amount(value: "150", unit: "EUR")))
        try expect(Record.Amount(value: "3.5", unit: "eur").same(as: Record.Amount(value: "3.50", unit: "EUR")))
        try expect(!Record.Amount(value: "150.01", unit: "EUR").same(as: Record.Amount(value: "150", unit: "EUR")))
        try expect(!Record.Amount(value: "150", unit: "EUR").same(as: Record.Amount(value: "150", unit: nil)))
        try expect(!Record.Amount(value: "150abc", unit: "EUR").same(as: Record.Amount(value: "150", unit: "EUR")))
        try expect(Record.Amount(value: "n/a", unit: nil).same(as: Record.Amount(value: "n/a", unit: nil)))
    },
    Test("a Record line carries its call's receipt, amount and answer; a part that doesn't read is left out") {
        let line = #"{"id":"e1","at":"2026-11-14T17:30:00Z","kind":"done","title":"Refund","detail":"Within its Card","time":"18:30","taf":{"id":"taf_1","name":"Refunds"},"call":{"proposal_id":"p","receipt":{"trace_id":"01KTRACE","status":"signed"},"amount":{"value":"150.00","unit":"EUR"},"answer":{"decision":"refused"}}}"#
        let decoder = AccountClient.decoder
        let entry = try decoder.decode(Record.Entry.self, from: Data(line.utf8))
        try expectEqual(entry.receipt, Record.Receipt(traceID: "01KTRACE", status: "signed"))
        try expectEqual(entry.amount, Record.Amount(value: "150.00", unit: "EUR"))
        try expectEqual(entry.answer, "refused")
        let odd = line.replacingOccurrences(of: #""amount":{"value":"150.00","unit":"EUR"}"#, with: #""amount":150"#)
            .replacingOccurrences(of: #""receipt":{"trace_id":"01KTRACE","status":"signed"}"#, with: #""receipt":null"#)
        let plain = try decoder.decode(Record.Entry.self, from: Data(odd.utf8))
        try expectEqual(plain.receipt, nil)
        try expectEqual(plain.amount, nil)
        try expectEqual(plain.title, "Refund")
    },
]

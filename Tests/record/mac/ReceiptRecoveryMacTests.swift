import Foundation

private func bytes(_ hex: String) -> Data { ReceiptCheck.hexDecode(hex)! }

/// A deterministic stream of bytes, so a failure names inputs that can be run again.
private struct Bytes {
    var state: UInt64
    mutating func next(_ count: Int) -> Data {
        var out = Data(capacity: count)
        for _ in 0..<count {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            out.append(UInt8(truncatingIfNeeded: state >> 33))
        }
        return out
    }
}

let receiptRecoveryMacTests: [Test] = [
    Test("libsecp256k1 recovers the fixtures' signers, high s and v 27–28 included, as the oracle does") {
        for vector in receiptRecoveryVectors {
            let digest = bytes(vector.digest)
            for signature in [bytes(vector.signature), bytes(vector.high)] {
                for v in [signature[64], signature[64] + 27] {
                    var sig = signature
                    sig[64] = v
                    try expectEqual(ReceiptSigner.address(digest: digest, signature: sig, recover: ReceiptRecovery.recover), vector.address)
                    try expectEqual(ReceiptSigner.address(digest: digest, signature: sig, recover: Secp256k1.recover), vector.address)
                }
            }
        }
    },
    Test("libsecp256k1 and the oracle agree on random signatures, ids 0–3, and on r or s at n, zero or above") {
        var random = Bytes(state: 0x7AF5_2026_1116)
        var recovered = 0
        for _ in 0..<400 {
            let digest = random.next(32), compact = random.next(64)
            for id: Int32 in 0...3 {
                let library = ReceiptRecovery.recover(digest: digest, compact: compact, recoveryID: id)
                let oracle = Secp256k1.recover(digest: digest, compact: compact, recoveryID: id)
                try expectEqual(library, oracle)
                if library != nil { recovered += 1 }
            }
        }
        // Most random r ‖ s recover a key with id 0 or 1, so the comparison isn't only nil against nil.
        try expect(recovered > 250)
        let n = bytes("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141")
        let digest = random.next(32), half = random.next(32)
        for compact in [n + half, half + n, Data(count: 32) + half, half + Data(count: 32), Data(repeating: 0xFF, count: 64)] {
            for id: Int32 in 0...3 {
                try expectEqual(ReceiptRecovery.recover(digest: digest, compact: compact, recoveryID: id), nil)
                try expectEqual(Secp256k1.recover(digest: digest, compact: compact, recoveryID: id), nil)
            }
        }
    },
    Test("the receipt KIFF's Go signer signed checks out through libsecp256k1, and each failure fails") {
        let check = { (receipt: String) in
            ReceiptCheck.check(Data(receipt.utf8), signer: receiptTestSigner, sha256: PasskeyCrypto.sha256, recover: ReceiptRecovery.recover)
        }
        try expectEqual(check(signedReceipt), .verified(signer: receiptTestSigner))
        try expectEqual(ReceiptCheck.check(Data(signedReceipt.utf8), sha256: PasskeyCrypto.sha256, recover: ReceiptRecovery.recover), .failed(.notKiff))
        try expectEqual(check(signedReceipt.replacingOccurrences(of: #""data_hash":"bb""#, with: #""data_hash":"bc""#)), .failed(.signatureMismatch))
        try expectEqual(check(signedReceipt.replacingOccurrences(of: #""signature":"[0-9a-f]+""#, with: #""signature":"00""#, options: .regularExpression)), .failed(.malformedSignature))
        try expectEqual(check(String(signedReceipt.dropLast()) + #","causal_chain":[]}"#), .failed(.unreadable))
    },
]

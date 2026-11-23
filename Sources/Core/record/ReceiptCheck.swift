import Foundation

/// Checks a KIFF receipt on this Mac (the iPad's `ReceiptCheck`), as KIFF's own verification does: the
/// signed digest is keccak256(ascii(sha256hex(causal_chain))), and the signer recovered from the 65-byte
/// signature must be KIFF's.
///
/// The chain's bytes are taken from the answer as KIFF wrote them, never re-encoded:
/// `GET /v1/receipts/{trace_id}` writes the stored receipt with Go's encoder, so its `causal_chain` is
/// byte for byte what KIFF hashed. Only the chain is signed: what the sheet shows as checked comes from
/// its steps.
enum ReceiptCheck: Equatable {
    /// The signature recovers to KIFF's signer over this chain.
    case verified(signer: String)
    /// KIFF signs in its next sweep, about 30 s after the decision.
    case notSignedYet
    /// It doesn't check out, and why.
    case failed(Failure)

    /// Why a receipt doesn't check out, each in the shared words.
    enum Failure: String, Equatable {
        case unreadable, unknownSignature, noSteps, malformedSignature, signatureMismatch, notKiff

        var key: String {
            switch self {
            case .unreadable: return "receipt.check.unreadable"
            case .unknownSignature: return "receipt.check.unknown_signature"
            case .noSteps: return "receipt.check.no_steps"
            case .malformedSignature: return "receipt.check.malformed_signature"
            case .signatureMismatch: return "receipt.check.signature_mismatch"
            case .notKiff: return "receipt.check.not_kiff"
            }
        }
    }

    /// KIFF's receipt signer in production: one key for every account, the deployer of KIFF's anchor
    /// contract and the sender of its anchor transactions. A rotation ships in a new build first. The
    /// same address as the iPad's `ReceiptCheck.kiffSigner` and Linux's `KIFF_SIGNER`.
    static let kiffSigner = "0x2f297affd7b62ef712a1e3158421ccb4bf2efcbe"

    static let algorithm = "secp256k1+keccak256"

    /// The receipt in `response`, checked against `expected`. `sha256` is passed in (CryptoKit's in the
    /// app), as Core builds on Linux without it.
    static func check(_ response: Data, signer expected: String = kiffSigner, sha256: (Data) -> Data,
                      recover: ReceiptRecover) -> ReceiptCheck {
        guard let receipt = (try? JSONSerialization.jsonObject(with: response)) as? [String: Any] else {
            return .failed(.unreadable)
        }
        // A key written twice is read as one copy here and maybe the other elsewhere: the chain hashed
        // could differ from the one shown. KIFF's encoder never repeats a key, so a receipt that does, at
        // its top or in its attestation, isn't one KIFF wrote. An attestation that isn't an object yet
        // (null: not signed yet) has no keys to repeat.
        let attestationKeys = ReceiptJSON.value(of: "attestation", in: response).flatMap(ReceiptJSON.keys(of:)) ?? []
        guard ReceiptJSON.keysAreUnique(in: response), Set(attestationKeys).count == attestationKeys.count else {
            return .failed(.unreadable)
        }
        guard let attestation = receipt["attestation"] as? [String: Any] else { return .notSignedYet }
        guard attestation["algorithm"] as? String == algorithm else { return .failed(.unknownSignature) }
        guard let chain = ReceiptJSON.value(of: "causal_chain", in: response) else { return .failed(.noSteps) }
        guard let signature = (attestation["signature"] as? String).flatMap(hexDecode), signature.count == 65 else {
            return .failed(.malformedSignature)
        }
        let declared = (attestation["wallet_address"] as? String ?? "").lowercased()

        let chainHash = hexEncode(sha256(chain))
        let digest = Keccak.hash256(Data(chainHash.utf8))
        guard let recovered = ReceiptSigner.address(digest: digest, signature: signature, recover: recover) else {
            return .failed(.signatureMismatch)
        }
        guard recovered == declared else { return .failed(.signatureMismatch) }
        guard recovered == expected.lowercased() else { return .failed(.notKiff) }
        return .verified(signer: recovered)
    }

    /// "What happened" is what KIFF signed for this line: drawn only once this Mac checked KIFF's
    /// signature and the receipt matches the line. Not signed yet, not checking out, or still being
    /// checked, its steps aren't drawn as what happened.
    static func showsWhatHappened(_ check: ReceiptCheck?, mismatch: Bool) -> Bool {
        if case .verified = check { return !mismatch }
        return false
    }

    static func hexEncode(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    static func hexDecode(_ string: String) -> Data? {
        var s = Substring(string)
        if s.hasPrefix("0x") { s = s.dropFirst(2) }
        guard s.count % 2 == 0 else { return nil }
        var out = Data(capacity: s.count / 2)
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let byte = UInt8(s[i..<j], radix: 16) else { return nil }
            out.append(byte)
            i = j
        }
        return out
    }
}

/// How a receipt's signer is recovered: from the 32-byte digest, r ‖ s (64 bytes) and the recovery id
/// 0–3, the public key's X ‖ Y (64 bytes), or nil. The app passes libsecp256k1's, built from pinned
/// source (`ReceiptRecovery`, scripts/fido.sh), as the iPad links it; Core builds on Linux without it.
typealias ReceiptRecover = (_ digest: Data, _ compact: Data, _ recoveryID: Int32) -> Data?

/// The address that signed a receipt, as the iPad's `ReceiptCheck.recoverAddress` reads it.
enum ReceiptSigner {
    /// "0x" and the last 20 bytes of keccak256 of the recovered key, or nil when the signature can't be
    /// read or recovers no key. `signature` is r ‖ s ‖ v, 65 bytes.
    ///
    /// v as the iPad reads it: 27 and up has 27 taken off, and libsecp256k1 then takes a recovery id of
    /// 0–3. So v is 0–3 or 27–30, as there. Any other v is refused here, before the library is asked:
    /// libsecp256k1 treats a recovery id outside 0–3 as a caller's error, not a bad signature.
    static func address(digest: Data, signature: Data, recover: ReceiptRecover) -> String? {
        guard digest.count == 32, signature.count == 65 else { return nil }
        let bytes = [UInt8](signature)
        var v = Int32(bytes[64])
        if v >= 27 { v -= 27 }
        guard (0...3).contains(v) else { return nil }
        guard let key = recover(Data(digest), Data(bytes[0..<64]), v), key.count == 64 else { return nil }
        return "0x" + ReceiptCheck.hexEncode(Keccak.hash256(key).suffix(20))
    }
}

/// A receipt's signed steps and its facts, as the sheet shows them (the iPad's `ReceiptView.steps`).
struct ReceiptSteps: Equatable {
    struct Step: Equatable {
        /// What "What happened" shows: KIFF's `step_words` for this step when it sent some, else `message`.
        let words: String
        /// KIFF's signed message for it, in KIFF's English, else its kind in words: what the full receipt shows.
        var message: String = ""
        let at: Date?
        /// The step's data hash, shortened as the iPad shows it ("aa12…ef34").
        let hash: String
        let kind: String
        /// The amount the decision step signed, when it has one.
        let amount: Record.Amount?
        /// A hold_settled step's answer, as KIFF records it ("reject" for a refusal).
        let answer: String?
        /// What the step acted on, as KIFF signed it (`data.on_hash`): "sha256:<hex>" of the value.
        var onHash: String? = nil
    }

    let steps: [Step]
    let issuedAt: Date?
    let signature: String?

    init(_ raw: Data) {
        let object = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
        issuedAt = (object?["issued_at"] as? String).flatMap(Self.date)
        signature = (object?["attestation"] as? [String: Any])?["signature"] as? String
        guard let chain = ReceiptJSON.value(of: "causal_chain", in: raw),
              let list = (try? JSONSerialization.jsonObject(with: chain)) as? [[String: Any]] else {
            steps = []
            return
        }
        let stepWords = ReceiptStepWords.read(from: raw)
        // Each step's own whole-number sequence, read as `step_words`' are: never a boolean or a fraction.
        let sequences = ReceiptStepWords.sequences(of: chain)
        steps = list.enumerated().map { i, s in
            let kind = s["kind"] as? String ?? ""
            let signed = (s["message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let message = signed ?? kind.replacingOccurrences(of: "_", with: " ")
            let sequence = i < sequences.count ? sequences[i] : nil
            let hash = s["data_hash"] as? String ?? ""
            let data = s["data"] as? [String: Any]
            let amount = (data?["amount"] as? [String: Any]).flatMap { a in
                (a["value"] as? String).map { Record.Amount(value: $0, unit: a["unit"] as? String) }
            }
            return Step(words: sequence.flatMap { stepWords[$0] } ?? message, message: message,
                        at: (s["occurred_at"] as? String).flatMap(Self.date),
                        hash: hash.count > 8 ? "\(hash.prefix(4))…\(hash.suffix(4))" : hash,
                        kind: kind, amount: amount, answer: data?["answer"] as? String,
                        onHash: data?["on_hash"] as? String)
        }
    }

    /// The signed decision step names an amount, and the line's isn't it: as numbers in the same unit.
    func amountMismatch(_ line: Record.Amount?) -> Bool {
        guard let line, let signed = steps.compactMap(\.amount).first else { return false }
        return !line.same(as: signed)
    }

    /// The signed chain has the answer (its hold_settled step), and the line's isn't it: KIFF records a
    /// refusal as "reject".
    func answerMismatch(_ decision: String?) -> Bool {
        guard let decision, let signed = steps.first(where: { $0.kind == "hold_settled" })?.answer else { return false }
        return (decision == "refused") != (signed == "reject")
    }

    /// The signed chain names what the call acted on (its first step with an `on_hash`), and the
    /// line's value isn't it, as the iPad's `ReceiptView.onMismatch`. A line not named (no value) or a
    /// chain with no `on_hash` compares nothing: no mismatch, and nothing said about the payment.
    func onMismatch(_ onValue: String?, sha256: (Data) -> Data) -> Bool {
        guard let onValue, let signed = steps.compactMap(\.onHash).first else { return false }
        return !Record.isOn(onValue, hash: signed, sha256: sha256)
    }

    /// The first way the line isn't what KIFF signed, in the iPad's order (RecordView.swift:491-496):
    /// its payment, then its amount, then its answer, as the shared key the sheet says it in; nil
    /// when it matches. Drawn only on a receipt this Mac verified.
    func mismatchKey(onValue: String?, amount: Record.Amount?, answer: String?, sha256: (Data) -> Data) -> String? {
        if onMismatch(onValue, sha256: sha256) { return "receipt.check.payment_mismatch" }
        if amountMismatch(amount) { return "receipt.check.amount_mismatch" }
        if answerMismatch(answer) { return "receipt.check.answer_mismatch" }
        return nil
    }

    /// RFC 3339, with or without fractional seconds, as Go writes times.
    static func date(_ s: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

/// KIFF's own words for a receipt's steps, sent beside the receipt and outside its signature (`step_words`:
/// `[{sequence, code, words}]`, in the reader's language), as the iPad's `ReceiptStepWords` (tafs#1709). Only an entry
/// with a whole-number `sequence` and words that aren't blank counts; the signed message is what a step reads as
/// without one. Read with `Decodable`, which refuses `true` and `1.5` as an `Int` on a Mac and on Linux alike.
enum ReceiptStepWords {
    private struct Entry: Decodable {
        let sequence: Int?
        let words: String?
        init(from decoder: Decoder) throws {
            enum Keys: String, CodingKey { case sequence, words }
            let c = try? decoder.container(keyedBy: Keys.self)
            sequence = (try? c?.decodeIfPresent(Int.self, forKey: .sequence)) ?? nil
            words = (try? c?.decodeIfPresent(String.self, forKey: .words)) ?? nil
        }
    }
    private struct Top: Decodable {
        let stepWords: [Entry]?
        enum CodingKeys: String, CodingKey { case stepWords = "step_words" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            stepWords = (try? c.decodeIfPresent([Entry].self, forKey: .stepWords)) ?? nil
        }
    }

    /// Each step's `sequence` in a `causal_chain`, in order: nil where it isn't a whole number.
    static func sequences(of chain: Data) -> [Int?] {
        ((try? JSONDecoder().decode([Entry].self, from: chain)) ?? []).map(\.sequence)
    }

    static func read(from raw: Data) -> [Int: String] {
        guard let top = try? JSONDecoder().decode(Top.self, from: raw) else { return [:] }
        var words: [Int: String] = [:]
        for entry in top.stepWords ?? [] {
            guard let n = entry.sequence, let text = entry.words?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { continue }
            words[n] = text
        }
        return words
    }
}

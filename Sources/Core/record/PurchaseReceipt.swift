import Foundation

/// KIFF's signed receipt for a purchase (Thune), kept in the Record: tafs's `contracts/purchase.json`, `receipt.value`.
/// What was decided and what happened, `unknown` said as unknown, every line in KIFF's words. Signed by KIFF (Ed25519,
/// `kid`) over the canonical JSON of the receipt without its `sig` (`signedBytes`).
struct PurchaseReceipt: Decodable, Equatable {
    let receiptID: String
    let caseID: String
    let version: Int
    let digest: String
    /// How it was paid: `token` (the card's number reached no one) or `card_fill` (KIFF's payment worker typed it,
    /// test mode only). The receipt's card line says which, never one sentence for both.
    let path: String
    let approver: Approver
    let amounts: Amounts
    let states: States
    let order: Order?
    let merchant: Merchants?
    /// The card issuer's check: `authenticated`, `exempted` or `required`, as KIFF records it.
    let verification: String?
    let issuedAt: String
    let words: Words
    let kid: String
    let sig: String

    struct Approver: Decodable, Equatable {
        let role: String
        /// Whether this person approved it ("Approved by you").
        let isSelf: Bool
        /// How: the device key behind biometrics, or a security key. The app says it in the device's own words.
        let method: String?
        enum CodingKeys: String, CodingKey { case role, isSelf = "self", method }
    }

    /// Minor units in `currency`.
    struct Amounts: Decodable, Equatable {
        let approvedMax: Int64
        let authorized: Int64
        let captured: Int64
        let refunded: Int64
        let currency: String
        enum CodingKeys: String, CodingKey {
            case approvedMax = "approved_max", authorized, captured, refunded, currency
        }
    }

    /// The case's, the money's and the order's states, apart: `unknown` is never shown as bought.
    struct States: Decodable, Equatable {
        let `case`: String
        let money: String
        let order: String
    }

    struct Order: Decodable, Equatable {
        let reference: String?
        let confirmedAt: String?
        enum CodingKeys: String, CodingKey { case reference, confirmedAt = "confirmed_at" }
    }

    /// The case's merchant and the issuer's, side by side, so a mismatch is visible.
    struct Merchants: Decodable, Equatable {
        let `case`: Merchant?
        let issuer: Merchant?
    }

    struct Merchant: Decodable, Equatable {
        let name: String?
        let category: String?
    }

    /// KIFF's words for the receipt, each drawn as sent.
    struct Words: Decodable, Equatable {
        let line: String
        let state: String?
        let allowed: String?
        let card: String?
        let shipping: String?
        let refunds: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func text(_ key: CodingKeys) -> String? {
                guard let value = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil else { return nil }
                let shown = Words.withoutDirection(value)
                return shown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : shown
            }
            guard let line = text(.line) else {
                throw DecodingError.dataCorruptedError(forKey: .line, in: c, debugDescription: "a receipt with no line")
            }
            self.line = line
            state = text(.state)
            allowed = text(.allowed)
            card = text(.card)
            shipping = text(.shipping)
            refunds = text(.refunds)
        }
        enum CodingKeys: String, CodingKey { case line, state, allowed, card, shipping, refunds }

        private static func withoutDirection(_ s: String) -> String { BidiFree.text(s) }
    }

    enum CodingKeys: String, CodingKey {
        case receiptID = "receipt_id", caseID = "case_id", version, digest, path, approver, amounts, states, order, merchant
        case verification, issuedAt = "issued_at", words, kid, sig
    }

    /// The two ways a purchase is paid, the only ones a receipt may name.
    static let paths: Set<String> = ["token", "card_fill"]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        receiptID = try c.decode(String.self, forKey: .receiptID)
        caseID = try c.decode(String.self, forKey: .caseID)
        version = try c.decode(Int.self, forKey: .version)
        digest = try c.decode(String.self, forKey: .digest)
        path = try c.decode(String.self, forKey: .path)
        approver = try c.decode(Approver.self, forKey: .approver)
        amounts = try c.decode(Amounts.self, forKey: .amounts)
        states = try c.decode(States.self, forKey: .states)
        order = try c.decodeIfPresent(Order.self, forKey: .order)
        merchant = try c.decodeIfPresent(Merchants.self, forKey: .merchant)
        verification = try c.decodeIfPresent(String.self, forKey: .verification)
        issuedAt = try c.decode(String.self, forKey: .issuedAt)
        words = try c.decode(Words.self, forKey: .words)
        kid = try c.decode(String.self, forKey: .kid)
        sig = try c.decode(String.self, forKey: .sig)
        // A path this app doesn't know can't say how the card was used: the receipt isn't read rather than guessed.
        guard Self.paths.contains(path), Purchase.isCaseID(caseID), Purchase.isDigest(digest), version >= 1 else {
            throw DecodingError.dataCorruptedError(forKey: .path, in: c, debugDescription: "a receipt this app can't read as sent")
        }
    }

    /// What KIFF signed: the receipt's canonical JSON (RFC 8785) without its `sig`, from its own bytes as received.
    static func signedBytes(_ receipt: Data) throws -> Data {
        guard case .object(var fields) = try JCS.parse(receipt) else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "a receipt isn't an object")) }
        fields["sig"] = nil
        return try JCS.canonical(.object(fields))
    }

    /// Why a receipt doesn't check out, or nil when it does: it must be for the case the person approved (its id and
    /// digest), and KIFF's signature over `signedBytes` must verify with the key named by `kid`. The check itself is
    /// passed in (CryptoKit's Ed25519 on the Mac), as Core builds without it.
    enum Problem: Equatable { case notThisCase, badSignature }

    static func check(_ receipt: Data, read: PurchaseReceipt, caseID: String, digest: String,
                      verify: (_ signature: String, _ message: Data, _ kid: String) -> Bool) -> Problem? {
        guard read.caseID == caseID, read.digest == digest else { return .notThisCase }
        guard let message = try? signedBytes(receipt), verify(read.sig, message, read.kid) else { return .badSignature }
        return nil
    }
}

import Foundation

/// A held purchase (Thune), as KIFF serves it on the hold: tafs's `contracts/purchase.json`, `approval.value`. Its words
/// are KIFF's, drawn as sent: the shop, the total, the lines behind Show more, the price rule, what the card allows, and why
/// it waits. Approving it signs this case's version and digest (`signedLine`), so an answer counts only for the case the
/// person saw.
struct Purchase: Decodable, Equatable {
    let caseID: String
    let version: Int
    let digest: String
    let words: Words

    /// One line the checkout lists ("A4 paper, 80 g, 5 reams", "× 2", "€59.80").
    struct Line: Decodable, Equatable {
        let name: String
        let quantity: String?
        let amount: String
    }

    /// A charge beside the lines (shipping, tax), so the open list adds up to the total.
    struct Charge: Decodable, Equatable {
        let name: String
        let amount: String
    }

    /// KIFF's words for the approval, every one as sent.
    struct Words: Decodable, Equatable {
        let title: String
        let subtitle: String?
        let total: String
        let totalNote: String?
        let delivery: String?
        let showMore: String?
        let lines: [Line]
        let charges: [Charge]
        let priceRule: String?
        let grant: String?
        let buysNow: String?
        let nothingUntil: String?
        let reason: String?
        /// What the approval prompt names: the shop and the total.
        let prompt: String?

        enum CodingKeys: String, CodingKey {
            case title, subtitle, total, totalNote = "total_note", delivery, showMore = "show_more", lines, charges
            case priceRule = "price_rule", grant, buysNow = "buys_now", nothingUntil = "nothing_until", reason, prompt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func text(_ key: CodingKeys) -> String? {
                guard let value = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil else { return nil }
                return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
            }
            // The shop and the total are what's approved: without them there is nothing to show, so nothing to sign.
            guard let title = text(.title), let total = text(.total) else {
                throw DecodingError.dataCorruptedError(forKey: .title, in: c, debugDescription: "a purchase with no shop or total")
            }
            self.title = title
            self.total = total
            subtitle = text(.subtitle)
            totalNote = text(.totalNote)
            delivery = text(.delivery)
            showMore = text(.showMore)
            priceRule = text(.priceRule)
            grant = text(.grant)
            buysNow = text(.buysNow)
            nothingUntil = text(.nothingUntil)
            reason = text(.reason)
            prompt = text(.prompt)
            // A list that doesn't read is refused whole: the open list must be every line the case signs, never part of it.
            lines = try c.decodeIfPresent([Line].self, forKey: .lines) ?? []
            charges = try c.decodeIfPresent([Charge].self, forKey: .charges) ?? []
        }
    }

    enum CodingKeys: String, CodingKey { case caseID = "case_id", version, digest, words }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        caseID = try c.decode(String.self, forKey: .caseID)
        version = try c.decode(Int.self, forKey: .version)
        digest = try c.decode(String.self, forKey: .digest)
        words = try c.decode(Words.self, forKey: .words)
        // What goes into the signed line is checked first: an id or digest that could carry a colon or a new line is
        // refused, so the line signed is always exactly one `purchase:` line.
        guard Self.isCaseID(caseID), version >= 1, Self.isDigest(digest) else {
            throw DecodingError.dataCorruptedError(forKey: .digest, in: c, debugDescription: "a purchase that can't be signed as sent")
        }
    }

    static func isCaseID(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 64 && s.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "_" || $0 == "-" }
    }

    static func isDigest(_ s: String) -> Bool {
        s.count == 64 && s.unicodeScalars.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    /// The line an answer to this purchase's hold ends with: `purchase:<case_id>:<version>:<digest>`. KIFF refuses an answer
    /// without it, or with a version or digest that isn't the case's current one.
    var signedLine: String { "purchase:\(caseID):\(version):\(digest)" }
}

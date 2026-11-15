import Foundation

/// One KIFF Card of a taf, as tafs cloud sends it with the list (`card.cards`): what the taf
/// may do on its own, and how much of it is left. The limits and what was used are KIFF's
/// numbers; the app only takes one from the other and writes the result.
struct TafCard: Decodable, Identifiable, Equatable {
    /// An amount in its smallest unit, with what KIFF says it means ("EUR", 2).
    struct Amount: Decodable, Equatable {
        let minor: Int64
        let unit: String?
        let scale: Int
    }

    /// A total for a window, and what has been used of it; `used` is nil when KIFF couldn't read it.
    struct Total<Value: Decodable & Equatable>: Decodable, Equatable {
        let limit: Value
        let used: Value?
        /// The window in the person's words, as tafs cloud sends them: "a day", "today".
        let each: String?
        let now: String?

        enum CodingKeys: String, CodingKey { case limit, used, words = "window_words" }
        enum WordsKeys: String, CodingKey { case each, now }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            limit = try c.decode(Value.self, forKey: .limit)
            used = (try? c.decodeIfPresent(Value.self, forKey: .used)) ?? nil
            let words = try? c.nestedContainer(keyedBy: WordsKeys.self, forKey: .words)
            each = words.flatMap { (try? $0.decodeIfPresent(String.self, forKey: .each)) ?? nil }
            now = words.flatMap { (try? $0.decodeIfPresent(String.self, forKey: .now)) ?? nil }
        }
    }

    /// One thing the Card lets the taf do, in KIFF's words, and what happens outside it.
    struct Rule: Decodable, Equatable {
        let label: String
        /// `refused` or `held`: what KIFF does with a call outside the Card.
        let outside: String
        /// The most calls in its window, when the rule has such a limit.
        let countPerWindow: Int?
        let each: String?

        enum CodingKeys: String, CodingKey { case label, outside, countPerWindow = "count_per_window", words = "window_words" }
        enum WordsKeys: String, CodingKey { case each }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            label = try c.decode(String.self, forKey: .label)
            outside = ((try? c.decodeIfPresent(String.self, forKey: .outside)) ?? nil) ?? ""
            countPerWindow = (try? c.decodeIfPresent(Int.self, forKey: .countPerWindow)) ?? nil
            each = (try? c.nestedContainer(keyedBy: WordsKeys.self, forKey: .words)).flatMap { (try? $0.decodeIfPresent(String.self, forKey: .each)) ?? nil }
        }
    }

    let id: String
    let title: String
    let active: Bool
    let expires: Date?
    let rules: [Rule]
    let total: Total<Amount>?
    let calls: Total<Int>?

    enum CodingKeys: String, CodingKey { case id, title, active, expires, rules, total, calls }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        active = ((try? c.decodeIfPresent(Bool.self, forKey: .active)) ?? nil) ?? true
        expires = (try? c.decodeIfPresent(Date.self, forKey: .expires)) ?? nil
        rules = ((try? c.decodeIfPresent([Rule].self, forKey: .rules)) ?? nil) ?? []
        total = (try? c.decodeIfPresent(Total<Amount>.self, forKey: .total)) ?? nil
        calls = (try? c.decodeIfPresent(Total<Int>.self, forKey: .calls)) ?? nil
    }

    /// The Card's large figure: what is left, of its money when it has a total, else of its
    /// calls. Nil when KIFF couldn't say what was used: the app then shows no figure, never a guess.
    enum Figure: Equatable {
        case calls(left: Int, limit: Int, window: String)
        case money(left: Amount, limit: Amount, window: String)
    }

    var figure: Figure? {
        if let total, let used = total.used, total.limit.unit == used.unit, total.limit.scale == used.scale {
            let left = Amount(minor: max(0, total.limit.minor - used.minor), unit: total.limit.unit, scale: total.limit.scale)
            return .money(left: left, limit: total.limit, window: total.now ?? "")
        }
        if let calls, let used = calls.used {
            return .calls(left: max(0, calls.limit - used), limit: calls.limit, window: calls.now ?? "")
        }
        return nil
    }
}

extension TafCard.Amount {
    /// The amount as the language writes money: "€1,960", "€12.50". A unit that isn't a
    /// currency's code follows the number as written; no unit is the bare number.
    func written(language: String) -> String {
        let places = max(0, min(scale, 6))
        var divisor = Decimal(1)
        for _ in 0..<places { divisor *= 10 }
        let value = Decimal(minor) / divisor
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: language)
        // Whole amounts are written without their zeros, as the apps write money everywhere.
        let whole = places == 0 || minor % Int64(truncating: NSDecimalNumber(decimal: divisor)) == 0
        formatter.minimumFractionDigits = whole ? 0 : places
        formatter.maximumFractionDigits = whole ? 0 : places
        if let unit, unit.count == 3, unit == unit.uppercased(), unit.allSatisfy(\.isLetter) {
            formatter.numberStyle = .currency
            formatter.currencyCode = unit
            return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value) \(unit)"
        }
        formatter.numberStyle = .decimal
        let number = formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
        return unit.map { "\(number) \($0)" } ?? number
    }
}

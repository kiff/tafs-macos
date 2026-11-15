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
        /// What KIFF does with a call outside the Card, as tafs cloud names it.
        enum Outside: Equatable {
            /// `hold`: held for the person.
            case hold
            /// `refuse`: refused.
            case refuse
            /// A word this app doesn't know: nothing is said about it.
            case unknown
        }

        let label: String
        let outside: Outside
        /// The most calls in its window, when the rule has such a limit.
        let countPerWindow: Int?
        /// tafs cloud's words for the window: "a day", and "today".
        let each: String?
        var now: String?
        /// KIFF's limits: each call, and the total for the window with the room it has now.
        var perAction: Amount?
        var perWindow: Amount?
        /// Of the total, the extra room given on a held call, and the Card's own limit.
        var extraRoom: Amount?
        var baseLimit: Amount?

        enum CodingKeys: String, CodingKey {
            case label, outside, countPerWindow = "count_per_window", words = "window_words"
            case perAction = "per_action", perWindow = "per_window", extraRoom = "extra_room", baseLimit = "base_limit"
        }
        enum WordsKeys: String, CodingKey { case each, now }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            label = try c.decode(String.self, forKey: .label)
            switch (try? c.decodeIfPresent(String.self, forKey: .outside)) ?? nil {
            case "hold": outside = .hold
            case "refuse": outside = .refuse
            default: outside = .unknown
            }
            countPerWindow = (try? c.decodeIfPresent(Int.self, forKey: .countPerWindow)) ?? nil
            let windowWords = try? c.nestedContainer(keyedBy: WordsKeys.self, forKey: .words)
            each = windowWords.flatMap { (try? $0.decodeIfPresent(String.self, forKey: .each)) ?? nil }
            now = windowWords.flatMap { (try? $0.decodeIfPresent(String.self, forKey: .now)) ?? nil }
            perAction = (try? c.decodeIfPresent(Amount.self, forKey: .perAction)) ?? nil
            perWindow = (try? c.decodeIfPresent(Amount.self, forKey: .perWindow)) ?? nil
            extraRoom = (try? c.decodeIfPresent(Amount.self, forKey: .extraRoom)) ?? nil
            baseLimit = (try? c.decodeIfPresent(Amount.self, forKey: .baseLimit)) ?? nil
        }

        /// The rule's limits in one line, as the iPad's `CardRule.summary`, in the shared words:
        /// held above them ("up to €150 each; more asks you first · €2,000 in total a day, then
        /// it asks you"), or refused above them ("≤ €150 each · €2,000 a day · 20 calls a day").
        /// The Card's own total, with its extra room apart, never one sum.
        func summary(_ words: Words) -> String {
            let window = each ?? ""
            // The room apart only with the Card's own total beside it: `per_window` already holds
            // the room, so with no `base_limit` it is the one sum, said once.
            let own = baseLimit != nil && extraRoom != nil ? baseLimit : perWindow
            let room = baseLimit == nil ? nil : extraRoom.map { words("card.extra_room", ["extra": $0.written(language: words.language), "window": now ?? ""]) }
            var parts: [String] = []
            switch outside {
            case .hold:
                if let each = perAction { parts.append(words("card.rule.up_to_each", ["amount": each.written(language: words.language)])) }
                if let own { parts.append(words("card.rule.total_then_asks", ["amount": own.written(language: words.language), "window": window])) }
                if let room { parts.append(room) }
                if let count = countPerWindow {
                    parts.append(count == 0 ? words("card.held.each_call_asks") : words.count("card.rule.calls_then_asks", count, ["window": window]))
                }
            case .refuse, .unknown:
                if let each = perAction { parts.append(words("card.rule.at_most_each", ["amount": each.written(language: words.language)])) }
                if let own { parts.append(own.written(language: words.language) + " " + window) }
                if let room { parts.append(room) }
                if let count = countPerWindow { parts.append(words.count("card.calls_window", count, ["window": window])) }
            }
            return parts.joined(separator: " · ")
        }

        /// The first of a rule's facts on the Card's face: its limit for each call.
        func eachFact(_ words: Words) -> String? {
            guard let each = perAction else { return nil }
            let amount = each.written(language: words.language)
            return outside == .hold ? words("card.rule.up_to_each", ["amount": amount]) : words("card.rule.at_most_each", ["amount": amount])
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
        // A Card with a money total says what is left of its money, or nothing: never its
        // calls in place of money it couldn't read.
        if let total {
            guard let used = total.used, total.limit.unit == used.unit, total.limit.scale == used.scale else { return nil }
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

extension TafCard {
    /// The Card in one line, as the Overview's Card column and the Activity tab say it: what is
    /// left of its money ("€1,960 left today of €2,000"), else of its calls. Nil with no figure.
    func line(_ words: Words) -> String? {
        switch figure {
        case .money(let left, let limit, let window)?:
            return left.written(language: words.language) + " " + words("card.hero.left_of", ["window": window, "limit": limit.written(language: words.language)])
        case .calls(let left, let limit, let window)?:
            // The line holds no number: the figure goes before it, as the Card's face puts it.
            return words.number(left) + " " + words.count("card.hero.calls_left_of", left, ["window": window, "limit": words.number(limit)])
        case nil:
            return nil
        }
    }
}

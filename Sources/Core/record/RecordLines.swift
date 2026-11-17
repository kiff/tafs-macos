import Foundation

/// A Record row's second line, as the iPad's `RecordRow.detail`, `decidedLine` and `resultLine`
/// (RecordView.swift:216-259, 314-329): who decided, then what became of it at the tool, in the
/// shared words ("within its Card · done").
extension Record.Entry {
    /// "<who decided> · <result at the tool>" for a call with a KIFF receipt or an answer, as the
    /// iPad's; any other line reads as tafs cloud words it. A held call keeps tafs cloud's line too:
    /// the iPad says "no longer waiting" once KIFF holds it no more, which the Record doesn't tell
    /// this Mac, so tafs cloud's words, which do, stand.
    func line(_ words: Words) -> String {
        guard kind != "held", receipt != nil || answer != nil else { return detail }
        return [decidedLine(words), resultLine(words)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Who decided: its Card, the owner or another person (approving or refusing), or KIFF's refusal.
    func decidedLine(_ words: Words) -> String {
        if let answer {
            let who = answerer(words)
            return answer == "refused" ? words("record.decided.refused_by", ["who": who]) : words("record.decided.approved_by", ["who": who])
        }
        switch kind {
        case "refused": return words("record.decided.refused_by_card")
        case "held": return words("record.decided.waiting_for_you")
        case "revoked": return words("card.card_revoked")
        case "started": return words("record.decided.card_issued")
        default: return ownerApproved ? words("record.decided.approved_by_you") : words("record.decided.within_card")
        }
    }

    /// What became of it at the tool.
    func resultLine(_ words: Words) -> String {
        switch kind {
        case "done", "approved": return words("record.result.done")
        case "refused", "revoked": return words("record.nothing_sent")
        case "not_done": return words("record.result.not_done")
        case "held": return words("record.result.nothing_sent_yet")
        case "sending": return words("record.result.no_answer_yet")
        case "started": return words("record.result.started")
        case "in_tafs": return ""
        default: return words("record.result.unknown")
        }
    }

    /// Who answered, in words: "you", or by KIFF's role for them ("an admin").
    func answerer(_ words: Words) -> String {
        if answeredByYou { return words("record.answerer.you") }
        guard let role = answerBy, !role.isEmpty else { return words("record.answerer.someone_else") }
        switch role {
        case "admin": return words("people.role_phrase.admin")
        case "approver": return words("people.role_phrase.approver")
        case "editor": return words("people.role_phrase.editor")
        case "member": return words("people.role_phrase.member")
        case "manager": return words("people.role_phrase.manager")
        case "owner": return words("people.role_phrase.owner")
        case "viewer": return words("people.role_phrase.viewer")
        default: return words("people.role_phrase.other", ["role": role.replacingOccurrences(of: "_", with: " ")])
        }
    }
}

extension Record {
    /// The money a day moved, as the iPad's `RecordView.spent` (RecordView.swift:107-124): a sum for
    /// each currency, in the order first met, of the calls Money moved keeps, each at the larger
    /// number of decimals of its parts. Empty when none moved money. An amount whose unit isn't a
    /// currency (a count of anything) isn't money, and isn't summed. Not drawn yet: the words for a
    /// day's title, "{amount} spent" (`record.day_spent`), aren't in the shared words at the pin.
    static func spent(_ entries: [Entry]) -> [Amount] {
        var sums: [String: (minor: Int64, scale: Int)] = [:]
        var order: [String] = []
        for entry in entries where Filter.moneyMoved.keeps(entry) {
            guard let amount = entry.amount, let unit = amount.unit, isCurrency(unit), let money = minor(amount.value) else { continue }
            if let sum = sums[unit] {
                let scale = max(sum.scale, money.scale)
                func at(_ x: (minor: Int64, scale: Int)) -> Int64 { x.minor * power(scale - x.scale) }
                sums[unit] = (at(sum) + at(money), scale)
            } else {
                sums[unit] = money
                order.append(unit)
            }
        }
        return order.compactMap { unit in sums[unit].map { Amount(value: written($0.minor, scale: $0.scale), unit: unit) } }
    }

    /// An ISO 4217 code, as the iPad's `money`: three capitals that name a currency.
    static func isCurrency(_ unit: String) -> Bool {
        unit.count == 3 && unit == unit.uppercased() && Locale.isoCurrencyCodes.contains(unit)
    }

    /// A plain decimal ("150", "-3.50") as a whole number of its smallest part, and how many
    /// decimals it has.
    private static func minor(_ value: String) -> (minor: Int64, scale: Int)? {
        guard value.range(of: #"^-?[0-9]{1,15}(\.[0-9]{1,6})?$"#, options: .regularExpression) != nil else { return nil }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        let scale = parts.count > 1 ? parts[1].count : 0
        return Int64(parts.joined()).map { ($0, scale) }
    }

    private static func power(_ n: Int) -> Int64 { (0..<max(n, 0)).reduce(1) { acc, _ in acc * 10 } }

    /// A whole number of the smallest part, written back as a decimal with `scale` decimals.
    private static func written(_ minor: Int64, scale: Int) -> String {
        guard scale > 0 else { return String(minor) }
        let sign = minor < 0 ? "-" : ""
        let digits = String(minor.magnitude)
        let padded = String(repeating: "0", count: max(0, scale + 1 - digits.count)) + digits
        return sign + padded.dropLast(scale) + "." + padded.suffix(scale)
    }

    /// Whether this person sees every taf's Record, as the iPad's `seesEveryTaf`: each taf on tafs
    /// cloud is one they oversee or manage, by KIFF's answer for its agent. Export receipts is
    /// theirs; tafs cloud still decides (403). Without KIFF's answer, it isn't shown.
    static func seesEveryTaf(_ tafs: [Home.Taf], access: [String: Access]?) -> Bool {
        let onCloud = tafs.filter { $0.tafID != nil }
        guard let access, !onCloud.isEmpty else { return false }
        return onCloud.allSatisfy { taf in access[taf.kiffAgent].map { $0.oversee || $0.manage } ?? false }
    }
}

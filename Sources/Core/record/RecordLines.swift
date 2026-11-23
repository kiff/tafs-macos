import Foundation

/// A Record row's second line, as the iPad's `RecordRow.detail`, `decidedLine` and `resultLine`
/// (RecordView.swift:216-259, 314-329): who decided, then what became of it at the tool, in the
/// shared words ("within its Card · done").
extension Record.Entry {
    /// The iPad's `RecordRow.detail` (RecordView.swift:317-330), joined with " · ": first what the
    /// call acted on (`onText`), when the line is named; then, for a held call KIFF no longer holds
    /// (`waiting` false), "no longer waiting · nothing sent"; else, for a call with a KIFF receipt or
    /// an answer, "<who decided> · <result at the tool>"; else tafs cloud's words for it. `waiting`
    /// is true until KIFF's held list is read (`Record.isWaiting`), as the iPad's.
    func line(_ words: Words, waiting: Bool = true) -> String {
        var parts: [String] = []
        if let on = onText(words) { parts.append(on) }
        if kind == "held", !waiting {
            parts += [words("record.no_longer_waiting"), words("record.nothing_sent")]
        } else if receipt != nil || answer != nil {
            parts += [decidedLine(words), resultLine(words)].filter { !$0.isEmpty }
        } else {
            parts.append(detail)
        }
        return parts.joined(separator: " · ")
    }

    /// "payment …QbstR": what the call acted on, by its argument's name ("it" without one), once
    /// `Record.naming` named it, as the iPad's `RecordEntry.onText` (RecordView.swift:206-212). A
    /// value longer than 6 shows its last 5.
    func onText(_ words: Words) -> String? {
        guard let value = onValue else { return nil }
        let noun = (onArg ?? words("record.on.it")).replacingOccurrences(of: "_", with: " ")
        return value.count > 6 ? "\(noun) …\(value.suffix(5))" : "\(noun) \(value)"
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

    /// The receipt's decision, in its facts line, as the iPad's `ReceiptView.decisionWords`
    /// (`RecordView.swift:705-715`): who answered a held call, else what its Card did.
    func decisionWords(_ words: Words) -> String {
        if let answer {
            let who = answerer(words)
            return answer == "refused" ? words("receipt.decision.held_refused_by", ["who": who]) : words("receipt.decision.held_approved_once_by", ["who": who])
        }
        switch kind {
        case "refused": return words("receipt.decision.refused_by_card")
        // Still waiting: the Card held it, it didn't allow it.
        case "held": return words("receipt.decision.held_by_card")
        default: return ownerApproved ? words("receipt.decision.held_approved_by_you") : words("receipt.decision.allowed_by_card")
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

    /// The receipt sheet's state line, as the iPad's `ReceiptView.stateLabel` (RecordView.swift:689-694):
    /// the owner's answer and who gave it, else how the call went (`RecordEntry.Kind.label`).
    func receiptLabel(_ words: Words) -> String {
        if let answer {
            let who = answerer(words)
            return answer == "refused" ? words("receipt.refused_by", ["who": who]) : words("receipt.approved_once_by", ["who": who])
        }
        switch kind {
        case "done": return words("receipt.label.done")
        case "approved": return words("receipt.label.approved")
        case "refused": return words("record.filter.refused")
        case "held": return words("receipt.label.held")
        case "not_done": return words("receipt.label.not_done")
        case "sending": return words("receipt.label.sending")
        case "revoked": return words("card.card_revoked")
        case "started": return words("receipt.label.started")
        case "in_tafs": return words("receipt.label.in_tafs")
        default: return words("receipt.label.unknown")
        }
    }

    /// The receipt's Outcome fact, as the iPad's `ReceiptView.outcome` (RecordView.swift:696-703).
    func receiptOutcome(_ words: Words) -> String {
        switch kind {
        case "done", "approved":
            guard amount != nil, let money = amountText else { return words("receipt.outcome.done") }
            return words("receipt.outcome.moved", ["amount": money])
        case "refused":
            return answer == "refused" ? words("receipt.outcome.refused_by", ["who": answerer(words)]) : words("receipt.outcome.card_refused")
        case "held": return words("receipt.outcome.waiting")
        default: return detail
        }
    }

    /// The receipt's Decided by fact, as the iPad's `ReceiptView.decidedBy` (RecordView.swift:717-731),
    /// in KIFF's mode, this Mac's only one. The iPad's refusal signed on the device itself is never a
    /// Record line here: this Mac signs none.
    func receiptDecidedBy(_ words: Words) -> String {
        if answer != nil {
            let who = answerer(words)
            var how = answeredByYou ? words("receipt.decided_by.you") : who.prefix(1).uppercased() + who.dropFirst()
            if answerSigned {
                how = words("receipt.decided_by.signed_on", ["who": how, "device": answerDevice ?? words("receipt.decided_by.your_device")])
            }
            return how
        }
        switch kind {
        case "approved": return words("receipt.decided_by.you_approving_once")
        case _ where ownerApproved: return words("receipt.decided_by.you_approving_once")
        case "revoked": return words("receipt.decided_by.you_revoking")
        case "started": return words("receipt.decided_by.you_issuing")
        default: return words("receipt.decided_by.kiff")
        }
    }

    /// The receipt's On fact, as the iPad's (RecordView.swift:395-397): the argument's name and the
    /// whole value, once the line is named; nil otherwise.
    var receiptOn: String? {
        guard let value = onValue else { return nil }
        return "\((onArg ?? "").replacingOccurrences(of: "_", with: " ")) \(value)"
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
    /// One of a taf's calls, as tafs cloud keeps it (`GET /v1/tafs/{id}/calls`): KIFF's key for it
    /// (`invocation`) and the value it acted on.
    struct CallRef: Decodable, Equatable {
        let invocation: String
        let value: String
    }

    /// Whether `value` is what KIFF's hash names, as the iPad's `KIFFMapping.isOn`: "sha256:" and the
    /// lowercase hex SHA-256 of its UTF-8 bytes, untrimmed, in its own case, compared exactly. `sha256`
    /// is passed in (CryptoKit's in the app), as Core builds on Linux without it.
    static func isOn(_ value: String, hash: String, sha256: (Data) -> Data) -> Bool {
        hash == "sha256:" + sha256(Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The tafs (by their id at tafs cloud) whose calls name a line: each with a line KIFF hashed
    /// what it acted on and that isn't named yet, as the iPad's `nameRecordLines`. Each once, in order.
    /// Only the person's own listed tafs (`listed`), as the iPad reads calls only for a taf it has as
    /// its own (`cloudTaf(for:)`): a taf they only oversee is never read, and its lines stay unnamed.
    static func tafsToName(_ groups: [Group], listed: Set<String>) -> [String] {
        var out: [String] = []
        for entry in groups.flatMap(\.entries) where entry.onHash != nil && entry.onValue == nil
            && listed.contains(entry.taf.id) && !out.contains(entry.taf.id) {
            out.append(entry.taf.id)
        }
        return out
    }

    /// The lines with what each acted on, from the tafs' calls by KIFF's key (`refs`), as the iPad's
    /// `KIFFMapping.naming`: only a value whose hash is KIFF's, so a line never names a payment KIFF
    /// didn't.
    static func naming(_ groups: [Group], refs: [String: String], sha256: (Data) -> Data) -> [Group] {
        groups.map { group in
            Group(id: group.id, title: group.title, entries: group.entries.map { e in
                var e = e
                if let key = e.entityID, let hash = e.onHash, let value = refs[key], isOn(value, hash: hash, sha256: sha256) { e.onValue = value }
                return e
            })
        }
    }

    /// A line's colour by its kind, as the iPad's `RecordEntry.Kind.color`: started is good, a call
    /// done in tafs is dim, anything unknown amber. Not a taf's Activity's (`TafActivity.Entry.tone`).
    enum Tone: Equatable { case ok, amber, no, dim }

    static func tone(of kind: String) -> Tone {
        switch kind {
        case "done", "approved", "started": return .ok
        case "refused", "revoked", "not_done": return .no
        case "in_tafs": return .dim
        default: return .amber
        }
    }

    /// Whether a line of the list opens its sheet, as the iPad's `RecordRow`: every line but one done
    /// in tafs, which isn't a call (kiff/tafs#236), receipt or not.
    static func opensSheet(_ entry: Entry) -> Bool { entry.kind != "in_tafs" }

    /// Whether a held line still waits, as the iPad's `AppModel.isWaiting`: until KIFF's held list is
    /// read (`held` nil: unread or failed) it does; after, only while some held call is its call (by
    /// KIFF's proposal id, `HeldCall.heldProposals`). A line without a proposal id still waits: it is
    /// never said to be no longer waiting without KIFF's word.
    static func isWaiting(_ entry: Entry, held: Set<String>?) -> Bool {
        guard let held, let proposal = entry.proposalID else { return true }
        return held.contains(proposal)
    }

    /// A line from KIFF as the Record draws it, as the iPad's `KIFFMapping.visible`: no direction
    /// character (U+202A–U+202E, U+2066–U+2069, U+200E, U+200F, U+061C), and any other control
    /// character a space.
    static func visible(_ text: String) -> String {
        var kept = String.UnicodeScalarView()
        for scalar in Words.withoutDirection(text).unicodeScalars {
            kept.append(scalar.properties.generalCategory == .control ? " " : scalar)
        }
        return String(kept)
    }

    /// "€640 spent": a day's money moved, a sum for each currency joined with " + ", in the app's
    /// language (`record.day_spent`, where the amount's place differs by language), as the iPad's
    /// `RecordView.spent` (RecordView.swift:107-125). Nil when the day moved none.
    static func spentWords(_ entries: [Entry], words: Words) -> String? {
        let sums = spent(entries).compactMap { amount -> String? in
            let parts = amount.value.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count <= 2, let whole = parts.first, !whole.isEmpty else { return nil }
            let fraction = parts.count == 2 ? String(parts[1]) : ""
            guard let minor = Int64(String(whole) + fraction) else { return nil }
            return TafCard.Amount(minor: minor, unit: amount.unit, scale: fraction.count).written(language: words.language)
        }
        guard !sums.isEmpty else { return nil }
        return words("record.day_spent", ["amount": sums.joined(separator: " + ")])
    }

    /// A day's heading, as the iPad's (`RecordView.swift:48-49`): its title, then what it spent,
    /// joined with " · ", and the whole in capitals in the app's language (the iPad's
    /// `.textCase(.uppercase)` on the joined text): "TODAY · 17 NOV · €640 SPENT".
    static func dayHeading(title: String, spent: String?, language: String) -> String {
        [title, spent].compactMap { $0 }.joined(separator: " · ").uppercased(with: Locale(identifier: language))
    }

    /// The money a day moved, as the iPad's `RecordView.spent` (RecordView.swift:107-124): a sum for
    /// each currency, in the order first met, of the calls Money moved keeps, each at the larger
    /// number of decimals of its parts. Empty when none moved money. An amount whose unit isn't a
    /// currency (a count of anything) isn't money, and isn't summed.
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

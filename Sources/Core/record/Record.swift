import Foundation

/// The Record across the person's tafs (`GET /v1/record`): every call, newest first, found
/// by what it is about, its action or its amount. Every word on it is tafs cloud's.
enum Record {
    /// One call in the Record, as its taf's Activity words it.
    struct Entry: Decodable, Identifiable, Equatable {
        struct Taf: Decodable, Equatable {
            let id: String
            let name: String

            enum CodingKeys: String, CodingKey { case id, name }
            init(id: String, name: String) { self.id = id; self.name = name }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try c.decode(String.self, forKey: .id)
                name = ((try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? ""
            }
        }

        let id: String
        let at: Date
        /// How it went, as tafs cloud names it: done, held, refused…
        let kind: String
        let title: String
        let detail: String
        /// When, in the person's language and zone, as sent.
        let time: String
        /// The money it moved, as sent ("€150.00"); nil when it moved none.
        let amountText: String?
        let taf: Taf
        /// What the call is about, the taf's business reference ("Order 1042"): it opens the case.
        let about: String?
        /// KIFF's receipt for the call, from its `call`: signed, or pending until KIFF's next sweep.
        /// Nil for a line with none.
        let receipt: Receipt?
        /// The money the call moved, as KIFF names it in its `call`: what its receipt is checked against.
        let amount: Amount?
        /// The owner's answer to a held call, from its `call` ("approved_once", "refused").
        let answer: String?
        /// Who answered it, by KIFF's role for them ("admin"), never who they are; nil when KIFF
        /// doesn't say. `answeredByYou`: the person reading answered it themselves.
        let answerBy: String?
        let answeredByYou: Bool
        /// A read of data, as KIFF marks the call (`call.read_only`): a day's reads fold into one line.
        let readOnly: Bool
        /// The owner approved it, a held call that KIFF then allowed, whatever the tool did: the
        /// iPad's `ownerApproved` (`outcome` allowed and `held`), or a call tafs cloud names approved.
        let ownerApproved: Bool
        /// KIFF's id for the call (`call.proposal_id`): what a held call is matched by in KIFF's held list.
        let proposalID: String?
        /// KIFF's key for what the call acted on (`call.entity_id`, the gateway's "tc-…"), what the taf's
        /// calls name it by; drawn only through `Record.visible`.
        let entityID: String?
        /// What it acted on, as KIFF signs it: "sha256:<hex>" of the value (`call.on_hash`), and the name
        /// of the argument it came from (`call.on_arg`, "payment").
        let onHash: String?
        let onArg: String?
        /// Why it wasn't sent, in KIFF's words (`call.reason`), through `Record.visible`.
        let reason: String?
        /// The owner's answer was signed on a device, and which (`call.answer.signed`, `.device`).
        let answerSigned: Bool
        let answerDevice: String?
        /// What the call acted on ("pi_3US…08Vgp"): never sent, set only by `Record.naming` from the
        /// taf's own calls when its value is the one KIFF hashed.
        var onValue: String? = nil
        /// The owner's next step for a call that wasn't done, as tafs cloud says it (`next`).
        let next: NextStep?
        /// KIFF's call names the taf that made it (`call.actor_id`): what the iPad's `SourceActivityRow`
        /// needs to open the call's sheet (its `evidence`), receipt or not.
        let hasActor: Bool

        enum CodingKeys: String, CodingKey { case id, at, kind, title, detail, time, amountText = "amount_text", taf, about, call, next
            case report, reportedAt = "reported_at"
        }

        /// "Report this payment" (docs/record.md): its receipt's id and when the payment was made, only where tafs cloud
        /// offers it (a payment this reader may report, not reported yet); nil draws no button.
        let report: ReportOffer?
        /// When this payment was reported, as KIFF keeps it on its receipt: it takes the button away.
        let reportedAt: Date?

        /// tafs cloud's offer to report a payment: the receipt's id for `POST /v1/record/{trace_id}/report`, and when the
        /// payment was made, which the sheet writes as its date.
        struct ReportOffer: Decodable, Equatable {
            let traceID: String
            var at: Date?
            enum CodingKeys: String, CodingKey { case traceID = "trace_id", at }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                traceID = try c.decode(String.self, forKey: .traceID)
                at = (try? c.decodeIfPresent(String.self, forKey: .at)).flatMap { $0.flatMap(Record.time) }
            }
        }

        /// The button shows where tafs cloud sent an offer, and the payment isn't reported yet (here or before).
        func offersReport(reportedNow: Bool = false) -> Bool {
            guard let report, !report.traceID.isEmpty else { return false }
            return reportedAt == nil && !reportedNow
        }


        /// The part of KIFF's call the receipt sheet reads. Each part that doesn't read is left out, and
        /// the line still reads.
        private struct Call: Decodable {
            struct Answer: Decodable {
                let decision: String
                var by: String?
                var you: Bool?
                var signed: Bool?
                var device: String?
                enum CodingKeys: String, CodingKey { case decision, by, you, signed, device }
                init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    decision = try c.decode(String.self, forKey: .decision)
                    by = (try? c.decodeIfPresent(String.self, forKey: .by)) ?? nil
                    you = (try? c.decodeIfPresent(Bool.self, forKey: .you)) ?? nil
                    signed = (try? c.decodeIfPresent(Bool.self, forKey: .signed)) ?? nil
                    device = (try? c.decodeIfPresent(String.self, forKey: .device)) ?? nil
                }
            }
            var receipt: Receipt?
            var amount: Amount?
            var answer: Answer?
            var readOnly: Bool?
            var outcome: String?
            var held: Bool?
            var proposalID: String?
            var entityID: String?
            var onHash: String?
            var onArg: String?
            var reason: String?
            var actorID: String?
            enum CodingKeys: String, CodingKey {
                case receipt, amount, answer, readOnly = "read_only", outcome, held
                case proposalID = "proposal_id", entityID = "entity_id", onHash = "on_hash", onArg = "on_arg", reason
                case actorID = "actor_id"
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                receipt = (try? c.decodeIfPresent(Receipt.self, forKey: .receipt)) ?? nil
                amount = (try? c.decodeIfPresent(Amount.self, forKey: .amount)) ?? nil
                answer = (try? c.decodeIfPresent(Answer.self, forKey: .answer)) ?? nil
                readOnly = (try? c.decodeIfPresent(Bool.self, forKey: .readOnly)) ?? nil
                outcome = (try? c.decodeIfPresent(String.self, forKey: .outcome)) ?? nil
                held = (try? c.decodeIfPresent(Bool.self, forKey: .held)) ?? nil
                proposalID = (try? c.decodeIfPresent(String.self, forKey: .proposalID)) ?? nil
                entityID = (try? c.decodeIfPresent(String.self, forKey: .entityID)) ?? nil
                onHash = (try? c.decodeIfPresent(String.self, forKey: .onHash)) ?? nil
                onArg = (try? c.decodeIfPresent(String.self, forKey: .onArg)) ?? nil
                reason = (try? c.decodeIfPresent(String.self, forKey: .reason)) ?? nil
                actorID = (try? c.decodeIfPresent(String.self, forKey: .actorID)) ?? nil
            }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            at = try c.decode(Date.self, forKey: .at)
            kind = try c.decode(String.self, forKey: .kind)
            title = try c.decode(String.self, forKey: .title)
            detail = try c.decode(String.self, forKey: .detail)
            time = try c.decode(String.self, forKey: .time)
            taf = try c.decode(Taf.self, forKey: .taf)
            func text(_ key: CodingKeys) -> String? {
                guard let value = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil else { return nil }
                return value.trimmingCharacters(in: .whitespaces).isEmpty ? nil : value
            }
            amountText = text(.amountText)
            about = text(.about)
            let call = (try? c.decodeIfPresent(Call.self, forKey: .call)) ?? nil
            receipt = call?.receipt.flatMap { $0.traceID.isEmpty ? nil : $0 }
            amount = call?.amount
            answer = call?.answer?.decision
            answerBy = call?.answer?.by
            answeredByYou = call?.answer?.you == true
            readOnly = call?.readOnly == true
            ownerApproved = kind == "approved" || (call?.outcome == "allowed" && call?.held == true)
            report = (try? c.decodeIfPresent(ReportOffer.self, forKey: .report)) ?? nil
            reportedAt = text(.reportedAt).flatMap(Record.time)
            proposalID = call?.proposalID
            entityID = call?.entityID.map(Record.visible)
            onHash = call?.onHash
            onArg = call?.onArg
            reason = call?.reason.map(Record.visible)
            answerSigned = call?.answer?.signed == true
            answerDevice = call?.answer?.device
            next = (try? c.decodeIfPresent(NextStep.self, forKey: .next)) ?? nil
            hasActor = call?.actorID != nil
        }
    }

    /// The owner's next step for a call that wasn't done, as tafs cloud says it (the iPad's
    /// `TafsCloud.NextStep`): `kind` is `reconnect`, `ask_coach` or `try_later`, `words` its button's,
    /// or its line's. One without a kind or words isn't one.
    struct NextStep: Decodable, Equatable {
        let kind: String
        let words: String
        var tool: String?
        var taf: String?
        var message: String?

        enum CodingKeys: String, CodingKey { case kind, words, tool, taf, message }
        init(kind: String, words: String, tool: String? = nil, taf: String? = nil, message: String? = nil) {
            self.kind = kind; self.words = words; self.tool = tool; self.taf = taf; self.message = message
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = try c.decode(String.self, forKey: .kind)
            words = try c.decode(String.self, forKey: .words)
            guard !kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .words, in: c, debugDescription: "a next step needs its kind and words")
            }
            tool = (try? c.decodeIfPresent(String.self, forKey: .tool)) ?? nil
            taf = (try? c.decodeIfPresent(String.self, forKey: .taf)) ?? nil
            message = (try? c.decodeIfPresent(String.self, forKey: .message)) ?? nil
        }
    }

    /// An RFC 3339 time as tafs cloud writes it, with or without fractions of a second.
    static func time(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// A call's KIFF receipt: its id, and whether KIFF has signed it yet.
    struct Receipt: Decodable, Equatable {
        let traceID: String
        let status: String
        enum CodingKeys: String, CodingKey { case traceID = "trace_id", status }
    }

    /// Money as KIFF writes it: a decimal string and its unit ("150.00", "EUR"). A gateway call's
    /// integer amount has no unit.
    struct Amount: Decodable, Equatable {
        let value: String
        var unit: String?

        /// The same amount as `other`: the same number, whatever its trailing zeros ("150.00" and "150"),
        /// in the same unit, whatever its case. A value that isn't a plain decimal is compared as written.
        func same(as other: Amount) -> Bool {
            guard (unit ?? "").uppercased() == (other.unit ?? "").uppercased() else { return false }
            guard let a = Self.decimal(value), let b = Self.decimal(other.value) else { return value == other.value }
            return a == b
        }

        /// A plain decimal ("150", "-3.50"), never a prefix of something else ("150abc").
        private static func decimal(_ s: String) -> Decimal? {
            guard s.range(of: #"^-?[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
            return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
        }
    }

    struct Group: Decodable, Identifiable, Equatable {
        let id: String
        let title: String
        let entries: [Entry]

        enum CodingKeys: String, CodingKey { case id, title, entries }
        init(id: String, title: String, entries: [Entry]) { self.id = id; self.title = title; self.entries = entries }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = ((try? c.decodeIfPresent(String.self, forKey: .title)) ?? nil) ?? ""
            entries = try c.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        }
    }

    /// One page of a search. The search box's words (`hint`), "nothing matched" and the
    /// end's words are tafs cloud's.
    struct Page: Decodable, Equatable {
        let hint: String
        let entries: [Entry]
        let groups: [Group]
        let nextCursor: String?
        let endWords: String?
        let noneWords: String?

        enum CodingKeys: String, CodingKey { case hint, entries, groups, nextCursor = "next_cursor", endWords = "end_words", noneWords = "none_words" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            hint = ((try? c.decodeIfPresent(String.self, forKey: .hint)) ?? nil) ?? ""
            // The entries are the page: one that doesn't read makes the page unreadable.
            entries = try c.decode([Entry].self, forKey: .entries)
            groups = try c.decodeIfPresent([Group].self, forKey: .groups) ?? []
            nextCursor = (try? c.decodeIfPresent(String.self, forKey: .nextCursor)) ?? nil
            endWords = (try? c.decodeIfPresent(String.self, forKey: .endWords)) ?? nil
            noneWords = (try? c.decodeIfPresent(String.self, forKey: .noneWords)) ?? nil
        }

        /// tafs cloud's groups, or every entry as one group when it sent none.
        var shown: [Group] {
            groups.isEmpty && !entries.isEmpty ? [Group(id: "all", title: "", entries: entries)] : groups
        }
        var isEmpty: Bool { entries.isEmpty && groups.allSatisfy { $0.entries.isEmpty } }
    }

    /// One case: every call about the same thing, oldest first.
    struct Case: Decodable, Equatable {
        /// Its own next step is decoded, as the iPad's; each step's `next` is the retry drawn.
        struct Failed: Decodable, Equatable {
            let id: String
            let words: String?
            let next: NextStep?
            enum CodingKeys: String, CodingKey { case id, words, next }
            init(id: String, words: String?, next: NextStep? = nil) { self.id = id; self.words = words; self.next = next }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try c.decode(String.self, forKey: .id)
                words = (try? c.decodeIfPresent(String.self, forKey: .words)) ?? nil
                next = (try? c.decodeIfPresent(NextStep.self, forKey: .next)) ?? nil
            }
        }
        let about: String
        let steps: [Entry]
        /// The latest step that didn't go through, in tafs cloud's words.
        let failed: Failed?

        enum CodingKeys: String, CodingKey { case about, steps, failed }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            about = try c.decode(String.self, forKey: .about)
            steps = try c.decodeIfPresent([Entry].self, forKey: .steps) ?? []
            failed = (try? c.decodeIfPresent(Failed.self, forKey: .failed)) ?? nil
        }
    }

    /// The groups with only one taf's calls, by its id at tafs cloud; nil keeps every taf's. A
    /// group left with none is left out.
    static func only(taf: String?, in groups: [Group]) -> [Group] {
        guard let taf else { return groups }
        return groups.compactMap { group in
            let kept = group.entries.filter { $0.taf.id == taf }
            return kept.isEmpty ? nil : Group(id: group.id, title: group.title, entries: kept)
        }
    }

    /// One day of the Record: its start, in the account's calendar, and its calls, newest first;
    /// with its reads apart, to fold into one line, as the iPad's `Day.lines` and `Day.reads`.
    struct Day: Identifiable, Equatable {
        let start: Date
        var entries: [Entry]
        var reads: [Entry] = []
        var id: Date { start }
    }

    /// The calls by day, newest first, as the iPad's `RecordView.days` (RecordView.swift:126-144):
    /// every call shown, whichever group tafs cloud sent it in, under the day it was made in the
    /// account's calendar. With `foldingReads` (the iPad folds them under All only), a day's reads
    /// go apart, in `reads`.
    static func days(_ groups: [Group], calendar: Calendar, foldingReads: Bool = false) -> [Day] {
        var out: [Day] = []
        for entry in groups.flatMap(\.entries).sorted(by: { $0.at > $1.at }) {
            let start = calendar.startOfDay(for: entry.at)
            if out.last?.start != start { out.append(Day(start: start, entries: [])) }
            if foldingReads && entry.readOnly {
                out[out.count - 1].reads.append(entry)
            } else {
                out[out.count - 1].entries.append(entry)
            }
        }
        return out
    }

    /// The Record's filters, the iPad's: each keeps the calls of some kinds.
    enum Filter: String, CaseIterable, Identifiable {
        case all, moneyMoved, stopped, waiting

        var id: String { rawValue }

        /// The shared key of its name.
        var titleKey: String {
            switch self {
            case .all: return "record.filter.all"
            case .moneyMoved: return "record.filter.money_moved"
            case .stopped: return "record.filter.stopped"
            case .waiting: return "record.filter.waiting"
            }
        }

        func keeps(_ entry: Entry) -> Bool {
            switch self {
            case .all: return true
            case .moneyMoved: return entry.amountText != nil && ["done", "approved"].contains(entry.kind)
            case .stopped: return ["refused", "not_done", "revoked"].contains(entry.kind)
            case .waiting: return ["held", "sending", "unknown"].contains(entry.kind)
            }
        }

        /// The groups with only the calls it keeps; a group left with none is left out.
        func keeping(_ groups: [Group]) -> [Group] {
            guard self != .all else { return groups }
            return groups.compactMap { group in
                let kept = group.entries.filter(keeps)
                return kept.isEmpty ? nil : Group(id: group.id, title: group.title, entries: kept)
            }
        }
    }

    /// The longest search tafs cloud takes.
    static let longestSearch = 100
}

extension CloudClient {
    /// Reports a payment the person didn't expect (`POST /v1/record/{trace_id}/report`, no body): KIFF marks its receipt
    /// and tafs cloud halts the taf, as the halt button does. It only takes authority away, so nothing is signed and no key
    /// is asked; resuming stays behind an approval. Reporting again answers the same. A refusal is tafs cloud's
    /// (`CloudRefusal`).
    func reportPayment(traceID: String) async throws {
        _ = try await post("/v1/record/\(Self.escaped(traceID))/report", [:])
    }

    /// The Record searched by `q` (an order, an invoice, an amount or an action); `cursor`
    /// continues the same search.
    func record(_ q: String = "", cursor: String? = nil, saying: Bool = false) async throws -> Record.Page {
        var query = ["q=\(Self.query(String(q.prefix(Record.longestSearch))))"]
        if let cursor { query.append("cursor=\(Self.query(cursor))") }
        return try await get("/v1/record?" + query.joined(separator: "&"), saying: saying)
    }

    /// One case: every call about `about`. A 404 says no call of the person's is about it.
    func recordCase(_ about: String) async throws -> Record.Case {
        try await get("/v1/record/cases/\(Self.escaped(about))", saying: true)
    }

    /// One taf's calls, by KIFF's key and the value it acted on, as the iPad's `TafsCloud.calls`
    /// (`GET /v1/tafs/{id}/calls`): what names a Record line's payment. Read whole or not at all: a
    /// ref that doesn't read makes the answer unreadable.
    func calls(_ tafID: String) async throws -> [Record.CallRef] {
        struct Answer: Decodable { let calls: [Record.CallRef] }
        let answer: Answer = try await get("/v1/tafs/\(Self.escaped(tafID))/calls")
        return answer.calls
    }
}

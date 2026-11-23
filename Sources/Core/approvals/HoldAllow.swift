import Foundation

/// "Allow this from now on" on a held call (kiff/tafs `docs/allow-from-now-on.md`), as the iPad's `HoldAllow`. Whether
/// to offer it is the app's own rule, from the held call KIFF sent, with no request. What it offers is tafs cloud's.
/// What's signed is KIFF's draft, which this Mac reads itself and signs, with its security key, only when it is what
/// was offered.
enum HoldAllow {
    /// The breaches a Card change can lift. A "never" is refused, not held, so it never shows here.
    static let liftable: Set<String> = ["per_action_exceeded", "limit_reached", "resource_not_on_card"]

    /// A hold (not Coach's install, which a confirm answers on its own) whose every breach a Card change can lift. Never a
    /// fill in Chrome: allowing it from now on would allow it without the phone's release, as Approve once would.
    static func allowable(_ call: HeldCall) -> Bool {
        guard !call.fillsInChrome, call.action != "version_install", call.kind != "card_unit",
              let outcomes = call.breachOutcomes, !outcomes.isEmpty else {
            return false
        }
        return outcomes.allSatisfy(liftable.contains)
    }

    /// The Mac signs what the person saw. KIFF's draft is for `agent` (and, when KIFF says, made from held call `hold`).
    /// It retires no Card and adds none. Each Card it changes is one the offer names, and reads exactly as that Card in
    /// force with the one offered change made: a per-call cap on the held `action` or a total moved from its figure
    /// before to its figure after, in the same unit (and window, when the offer names one); or, for a `resource` change,
    /// the held action's scope with the one offered value added. Every other term is the same (`Terms`). A Card marked
    /// unchanged must read as in force too. Anything else isn't what was offered, and nothing is signed.
    static func matches(_ draft: AccountClient.Draft, _ offer: CloudClient.AllowOffer, agent: String?, hold: String?, action: String) -> Bool {
        guard let agent, !agent.isEmpty, draft.agentID == agent else { return false }
        if let from = draft.fromHold, from != hold { return false }
        guard (draft.retires ?? []).isEmpty else { return false }
        let named = Set(offer.changes.map(\.mandateID))
        guard !named.isEmpty, let cards = draft.cards else { return false }
        var changed = Set<String>()
        for card in cards {
            guard let revises = card.revises, let current = card.current else { return false }
            // A draft that sets how long a hold waits, or revokes, changes more than a limit.
            guard (card.holdExpiry ?? "").isEmpty, card.revokedAt == nil else { return false }
            let inForce = Terms(current)
            let terms = Terms(card, over: current)
            if card.unchanged == true {
                guard terms == inForce else { return false }
                continue
            }
            guard named.contains(revises), !changed.contains(revises) else { return false }
            var expected: Set<Terms> = [inForce]
            for change in offer.changes where change.mandateID == revises {
                expected = Set(expected.flatMap { applied($0, change, action: action) })
            }
            guard expected.contains(terms) else { return false }
            changed.insert(revises)
        }
        return changed == named
    }

    /// Every term of a Card that decides what its taf may do, in an order of their own, as KIFF writes them in a draft's
    /// Card and in the Card in force. KIFF's lines and a grant's title are words, not terms. What a draft may leave out
    /// reads as KIFF fills it: a total's measure (attempts for a count, effects for a sum), and the Card's holders when
    /// the draft names only the same first holder.
    struct Terms: Hashable {
        struct Cap: Hashable { var quantity: String; var max: Int64; var unit: String?; var scale: Int? }
        struct Grant: Hashable {
            var action: String
            var caps: [Cap]
            /// The scope's parameter, and its values sorted; nil for a grant with no scope.
            var scopeOf: String?
            var scope: [String]
            var states: [String]
            var nextSteps: [String]
        }
        struct Total: Hashable {
            var quantity: String; var limit: Int64; var window: String; var unit: String?; var scale: Int?
            var measure: String; var per: String
        }
        var grants: [Grant]
        var totals: [Total]
        var onExceed: String?
        var holders: [String]
        var domain: String
        var environment: String
        var location: String
        /// When it starts and ends, as the instants KIFF's times name (`instant`): "" for none.
        var validFrom: String
        var validUntil: String

        /// The Card in force.
        init(_ current: AccountClient.Draft.Card.Terms) {
            self.init(grants: Self.grants(current.grants), totals: Self.totals(current.aggregates), onExceed: current.onExceed,
                      holders: Self.holders(current.subject, current.subjects), domain: current.domain, environment: current.environment,
                      location: current.location, validFrom: Self.instant(current.validFrom), validUntil: Self.instant(current.validUntil))
        }

        /// A draft's Card, read over the Card in force it revises: a draft that names no holders keeps the Card's, when
        /// its first holder is the same.
        init(_ card: AccountClient.Draft.Card, over current: AccountClient.Draft.Card.Terms) {
            var holders = Self.holders(card.subject, card.subjects)
            if (card.subjects ?? []).isEmpty, let subject = card.subject, subject == Self.holders(current.subject, current.subjects).first {
                holders = Self.holders(current.subject, current.subjects)
            }
            self.init(grants: Self.grants(card.grants), totals: Self.totals(card.aggregates), onExceed: card.onExceed,
                      holders: holders, domain: card.domain, environment: card.environment,
                      location: card.location, validFrom: Self.instant(card.validFrom), validUntil: Self.instant(card.validUntil))
        }

        init(grants: [Grant], totals: [Total], onExceed: String?, holders: [String], domain: String?, environment: String?,
             location: String?, validFrom: String, validUntil: String) {
            self.grants = grants.map { g in
                var g = g
                g.caps = g.caps.sorted { Self.capKey($0) < Self.capKey($1) }
                g.scope = g.scope.sorted()
                return g
            }.sorted { Self.grantKey($0) < Self.grantKey($1) }
            self.totals = totals.sorted { Self.totalKey($0) < Self.totalKey($1) }
            self.onExceed = onExceed
            self.holders = holders
            self.domain = (domain ?? "").lowercased()
            self.environment = (environment ?? "").lowercased()
            self.location = location ?? ""
            // Already read as instants by the two initializers above: never read twice.
            self.validFrom = validFrom
            self.validUntil = validUntil
        }

        /// A time as KIFF writes it, as the instant it names, so the same moment written with another offset or
        /// precision is the same term. None is "". Every other text is parsed: one that can't be read as a time is kept
        /// as written behind a mark no instant has, so it equals only the same unreadable text, and never a time.
        static func instant(_ time: String?) -> String {
            guard let time, !time.isEmpty else { return "" }
            let precise = ISO8601DateFormatter()
            precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = precise.date(from: time) ?? ISO8601DateFormatter().date(from: time) else { return "?" + time }
            return "@" + String(Int64((date.timeIntervalSince1970 * 1000).rounded()))
        }

        private static func grants(_ grants: [AccountClient.Draft.Card.Grant]?) -> [Grant] {
            (grants ?? []).map { g in
                Grant(action: g.action, caps: (g.perActionMax ?? []).map { Cap(quantity: $0.quantity, max: $0.max, unit: $0.unit, scale: $0.scale) },
                      scopeOf: g.resources?.parameter, scope: g.resources?.values ?? [], states: g.entityStates ?? [], nextSteps: g.nextSteps ?? [])
            }
        }

        private static func totals(_ aggregates: [AccountClient.Draft.Card.Aggregate]?) -> [Total] {
            (aggregates ?? []).map { a in
                // Left out, KIFF counts attempts for a count and effects for a sum.
                let measure = (a.measure ?? "").isEmpty ? (a.quantity == "count" ? "attempts" : "effects") : (a.measure ?? "")
                return Total(quantity: a.quantity, limit: a.limit, window: a.window, unit: a.unit, scale: a.scale, measure: measure, per: a.per ?? "")
            }
        }

        /// Every holder, the first being the subject.
        private static func holders(_ subject: String?, _ subjects: [String]?) -> [String] {
            if let subjects, !subjects.isEmpty { return subjects }
            return subject.map { [$0] } ?? []
        }

        private static func capKey(_ c: Cap) -> String { "\(c.quantity)|\(c.unit ?? "")|\(c.max)|\(c.scale.map(String.init) ?? "")" }
        private static func grantKey(_ g: Grant) -> String {
            "\(g.action)|\(g.caps.map(capKey).joined(separator: ";"))|\(g.scopeOf ?? "")|\(g.scope.joined(separator: ","))|\(g.states.joined(separator: ","))|\(g.nextSteps.joined(separator: ","))"
        }
        private static func totalKey(_ t: Total) -> String {
            "\(t.quantity)|\(t.window)|\(t.per)|\(t.measure)|\(t.unit ?? "")|\(t.limit)|\(t.scale.map(String.init) ?? "")"
        }

        /// These terms with their grants or totals replaced, put back in order.
        func with(grants: [Grant]? = nil, totals: [Total]? = nil) -> Terms {
            Terms(grants: grants ?? self.grants, totals: totals ?? self.totals, onExceed: onExceed, holders: holders, domain: domain,
                  environment: environment, location: location, validFrom: validFrom, validUntil: validUntil)
        }
    }

    /// Every way `change` can apply to `terms`: one limit of its kind, at its figure before and in its unit, moved to
    /// its figure after; or one value added to the scope of the held call's `action`. A per-call cap is the held
    /// `action`'s. A kind the contract doesn't name applies in no way.
    static func applied(_ terms: Terms, _ change: CloudClient.AllowOffer.Change, action: String) -> [Terms] {
        switch change.kind {
        case "per_action":
            guard let before = change.before, let after = change.after else { return [] }
            var all: [Terms] = []
            for (g, grant) in terms.grants.enumerated() where grant.action == action {
                for (c, cap) in grant.caps.enumerated() where cap.max == before && cap.unit == change.unit {
                    var grants = terms.grants
                    grants[g].caps[c].max = after
                    all.append(terms.with(grants: grants))
                }
            }
            return all
        case "total", "count":
            guard let before = change.before, let after = change.after else { return [] }
            var all: [Terms] = []
            for (t, total) in terms.totals.enumerated()
            where total.limit == before && total.unit == change.unit && (change.window == nil || change.window == total.window) {
                var totals = terms.totals
                totals[t].limit = after
                all.append(terms.with(totals: totals))
            }
            return all
        case "resource":
            // Exactly the values in force plus this one, on the held action's scope for this parameter.
            guard let parameter = change.parameter, !parameter.isEmpty, let value = change.value, !value.isEmpty else { return [] }
            var all: [Terms] = []
            for (g, grant) in terms.grants.enumerated() where grant.action == action && grant.scopeOf == parameter && !grant.scope.contains(value) {
                var grants = terms.grants
                grants[g].scope.append(value)
                all.append(terms.with(grants: grants))
            }
            return all
        default:
            return []
        }
    }

    /// What reading the offer came to: tafs cloud's answer, KIFF's draft as this Mac read it, and whether it's what was
    /// offered.
    struct Read: Equatable {
        let answer: CloudClient.AllowAnswer
        let draft: AccountClient.Draft?
        let matches: Bool
    }

    /// tafs cloud's offer for a held call, then KIFF's draft, read by this Mac, and whether the draft is what was
    /// offered. A `none` reads no draft.
    static func read(offer: (Bool) async throws -> CloudClient.AllowAnswer, draft: (String) async throws -> AccountClient.Draft,
                     call: HeldCall, round: Bool) async throws -> Read {
        let answer = try await offer(round)
        guard let made = answer.offer, !made.draft.isEmpty else { return Read(answer: answer, draft: nil, matches: false) }
        let read = try await draft(made.draft)
        return Read(answer: answer, draft: read, matches: matches(read, made, agent: call.subject, hold: call.id, action: call.action))
    }

    /// What the security key signs: KIFF's draft at the version this Mac read, a plain confirm that names no held call.
    /// KIFF answers a held call inside a confirm only for Coach's install (`confirm_hold.go`): a refund, or any call that
    /// moves something, is answered on its own, with its own approval (`NeedsYouModel.allowAndSend`).
    static func confirm(_ draft: AccountClient.Draft) -> KeyAct {
        .confirmDraft(id: draft.id, version: draft.version)
    }
}

extension CloudClient {
    /// `POST /v1/tafs/{id}/holds/{exception}/allow` (docs/allow-from-now-on.md), as the iPad's `TafsCloud.AllowAnswer`:
    /// tafs cloud's offer to change the Card so calls like a held one go on their own, or why there's none (`none`, with
    /// tafs cloud's `words`). A `none` this app doesn't know reads as any other: its words, and nothing to sign.
    struct AllowAnswer: Decodable, Equatable {
        var offer: AllowOffer?
        var none: String?
        var words: String?
    }

    /// The offer: the narrowest change, what it would have let go over the last 30 days, and the draft KIFF holds for it.
    struct AllowOffer: Decodable, Equatable {
        /// One limit the offer changes: on which Card, what kind, from what to what, and in tafs cloud's words.
        struct Change: Decodable, Equatable {
            let mandateID: String
            let kind: String
            var before: Int64?
            var after: Int64?
            var unit: String?
            var window: String?
            /// For a `resource` change: the parameter whose scope grows, and the one value added.
            var parameter: String?
            var value: String?
            var wordsBefore: String?
            var wordsAfter: String?
            var rounded: Bool?
            enum CodingKeys: String, CodingKey {
                case mandateID = "mandate_id", kind, before, after, unit, window, parameter, value, rounded
                case wordsBefore = "words_before", wordsAfter = "words_after"
            }
        }
        struct Would: Decodable, Equatable {
            var calls: Int?
            var words: String?
        }
        /// What rounding would give, named before any tap. The app never rounds.
        struct Round: Decodable, Equatable {
            var after: Int64?
            var words: String?
        }
        let changes: [Change]
        /// Left out when KIFF's replay couldn't be read: the change is still offered.
        var would: Would?
        let draft: String
        var confirmKey: String?
        var sendHeld: Bool?
        /// Absent when rounding changes nothing.
        var round: Round?
        enum CodingKeys: String, CodingKey { case changes, would, draft, confirmKey = "confirm_key", sendHeld = "send_held", round }
    }

    /// Asks tafs cloud for the offer on a held call, made on the tap and never before: the exact figure, or the rounded
    /// one when `round`.
    func allowOffer(taf: String, exception: String, round: Bool) async throws -> AllowAnswer {
        let body = round ? ["round": true] : [String: Bool]()
        return try decoded(try await post("/v1/tafs/\(Self.escaped(taf))/holds/\(Self.escaped(exception))/allow", body: body))
    }
}

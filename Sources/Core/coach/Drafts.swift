import Foundation

/// KIFF's draft of a taf's Cards, as an approval card in Coach names it (`component.draft`), as the
/// iPad's `KIFFClient.AgentDraft` and `DraftCard` (KIFFClient.swift:1197-1395). Read as the session
/// with `GET /v1/me/agent-drafts/{id}`, the iPad's `draft(id:)`, and only read: confirming a draft
/// issues its Cards, which is signed, on the phone.
extension AccountClient {
    struct Draft: Decodable, Equatable {
        /// One Card of a draft, as far as its lines go.
        struct Card: Decodable, Equatable {
            struct Grant: Decodable, Equatable {
                struct PerAction: Decodable, Equatable {
                    let quantity: String
                    let max: Int64
                    var unit: String?
                    var scale: Int?
                }
                let action: String
                var title: String?
                var perActionMax: [PerAction]?
                enum CodingKeys: String, CodingKey { case action, title, perActionMax = "per_action_max" }
            }
            struct Aggregate: Decodable, Equatable {
                let quantity: String
                let limit: Int64
                let window: String
                var unit: String?
                var scale: Int?
            }
            var grants: [Grant]?
            var aggregates: [Aggregate]?
            /// What KIFF does with a call past a limit: `owner` holds it for the owner.
            var onExceed: String?
            /// KIFF's own words for the Card, shown as they come.
            var kiffLines: [String]?
            enum CodingKeys: String, CodingKey { case grants, aggregates, onExceed = "on_exceed", kiffLines = "lines" }

            var asksPastLimits: Bool { onExceed == "owner" }
        }

        let id: String
        let agentID: String
        /// draft, confirming, confirmed, rolling_back, failed, discarding, discarded, claimed.
        let status: String
        let version: String
        var cards: [Card]?
        /// An agent that holds no tools: Setup.
        var noTools: Bool?
        /// The name it was submitted with, such as the taf's ("Refunds assistant").
        var label: String?
        enum CodingKeys: String, CodingKey { case id, status, version, cards, label, agentID = "agent_id", noTools = "no_tools" }

        var confirmed: Bool { status == "confirmed" }
        /// KIFF took the owner's signature for it: confirmed, or confirmed and its key claimed since.
        var signed: Bool { status == "confirmed" || status == "claimed" }
        /// An agent that holds tools: Setup's own draft holds none.
        var holdsTools: Bool { noTools != true }

        /// "Refunds assistant's Card": the name it was submitted with, never its agent id, as the
        /// iPad's `cardTitle`.
        func cardTitle(_ words: Words) -> String {
            // Through `visible`, as every other server text here (agentgabo's review): no direction mark can reorder it.
            let name = CallNames.visible(label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? words("card.the_tafs_card") : words("coach.card_of", ["owner": name])
        }

        /// Every Card's lines in one list, as the iPad's `lines`: two grants that read alike, on one
        /// Card or two, each add their action in words.
        func lines(_ words: Words) -> [String] {
            let all = cards ?? []
            let alike = Self.alike(all.flatMap { $0.grants ?? [] })
            return all.flatMap { Self.lines(of: $0, alike: alike, words) }
        }

        /// The names, ignoring case, that more than one of these grants reads as.
        static func alike(_ grants: [Card.Grant]) -> Set<String> {
            var seen: Set<String> = [], twice: Set<String> = []
            for g in grants {
                let name = CallNames.name(g.action, title: g.title).lowercased()
                if !seen.insert(name).inserted { twice.insert(name) }
            }
            return twice
        }

        /// A Card's lines, as the iPad's `DraftCard.lines(alike:)`: KIFF's own when it sends them;
        /// else each action by its title with its caps, then each total in KIFF's own window. An
        /// amount's unit is KIFF's, or the number says it has none: never a guessed currency.
        static func lines(of card: Card, alike: Set<String>, _ words: Words) -> [String] {
            // KIFF's own lines say what an approval grants: through `visible`, so a direction override can't make a cap
            // read otherwise than it is (agentgabo's review).
            if let own = card.kiffLines, !own.isEmpty { return own.map(CallNames.visible) }
            var out: [String] = []
            for g in card.grants ?? [] {
                let name = CallNames.name(g.action, title: g.title)
                let caps = (g.perActionMax ?? []).map { cap in
                    words("card.line.up_to_each", ["amount": isSum(cap.quantity) ? money(cap.max, unit: cap.unit, scale: cap.scale, words) : String(cap.max)])
                }
                let action = alike.contains(name.lowercased()) ? "\(name) · \(CallNames.toolWords(g.action))" : name
                let more = card.asksPastLimits ? words("card.line.more_asks") : ""
                out.append(caps.isEmpty ? action : "\(action): " + caps.joined(separator: ", ") + more)
            }
            let then = card.asksPastLimits ? words("card.line.then_asks") : ""
            for a in card.aggregates ?? [] {
                let window = Window(a.window, words)
                if isSum(a.quantity) {
                    out.append("\(money(a.limit, unit: a.unit, scale: a.scale, words)) \(window.sumLabel)\(then)")
                } else if card.asksPastLimits && a.limit == 0 {
                    out.append(words("card.held.each_call_asks"))
                } else {
                    out.append(words.count("card.line.calls_in_window", Int(a.limit), ["window": window.label, "then": then]))
                }
            }
            return out
        }

        /// A summed quantity: an amount, never a count.
        static func isSum(_ quantity: String) -> Bool { quantity.lowercased().hasPrefix("sum(") }

        /// An amount in the unit KIFF declares for it, as the iPad's `KIFFMapping.money` and
        /// `Money.formatted`: with none, the bare number says it has no currency.
        static func money(_ minor: Int64, unit: String?, scale: Int?, _ words: Words) -> String {
            guard let unit, !unit.isEmpty else { return words("card.no_currency", ["amount": words.number(Int(minor))]) }
            return TafCard.Amount(minor: minor, unit: unit, scale: scale ?? 0).written(language: words.language)
        }

        /// KIFF's spending window, as the iPad's `Window`: its five names in the shared words, any
        /// other as sent, never read as a day.
        struct Window {
            let raw: String
            let label: String
            let sumLabel: String
            init(_ raw: String, _ words: Words) {
                let raw = raw == "day" ? "calendar_day" : raw
                let known = ["calendar_day": "card.window.a_day", "week": "card.window.a_week", "rolling_24h": "card.window.any_day",
                             "rolling_7d": "card.window.any_week", "rolling_1h": "card.window.any_hour", "lifetime": "card.window.in_total"]
                self.raw = raw
                label = known[raw].map { words($0) } ?? raw
                sumLabel = raw == "calendar_day" ? words("card.window.in_total_window", ["window": label]) : label
            }
        }
    }

    /// A draft as it is now, as the iPad's `KIFFClient.draft(id:)` (KIFFClient.swift:1410): a read
    /// with the session, never signed.
    func draft(id: String) async throws -> Draft {
        try read(try await send("GET", "/v1/me/agent-drafts/\(CloudClient.escaped(id))"))
    }
}

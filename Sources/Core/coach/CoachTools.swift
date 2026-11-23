import Foundation

/// Coach's tools as tafs cloud reads them from KIFF (`GET /v1/setup`'s `tools`), as the iPad's
/// `TafsCloud.CoachTools` (TafsCloud.swift:2446-2557): `given`, `to_give`, `taken` or `unknown`,
/// and the words of the step that asks for them, every one tafs cloud's or KIFF's. Only the words
/// are kept: giving the tools signs tafs cloud's bodies with the approval key, which is the
/// phone's, so this Mac keeps no body and sends nothing from here.
struct CoachTools: Equatable {
    /// KIFF's own words for each of Coach's Cards.
    struct CardWords: Equatable {
        var title = ""
        var lines: [String] = []
    }

    /// The step's words, every one tafs cloud's, in the person's language. A line missing, or not
    /// text, is none.
    struct Step: Equatable {
        struct Tool: Equatable {
            var name = ""
            var does = ""
            var why = ""
        }
        struct Group: Equatable {
            var name = ""
            var line = ""
            var tools: [Tool] = []
        }
        var title = ""
        var intro = ""
        var groups: [Group] = []
        var details = ""
        var ask = ""
        var give = ""
        var notNow = ""
        var row = ""
    }

    var state = "unknown"
    /// With `taken`: the name a vendor's tool holds.
    var taken: String?
    /// A line per tool of the batch of connections, when tafs cloud sends one.
    var connectLines: [String]?
    /// Coach's Cards' draft, in KIFF's words: its title and each Card.
    var cardTitle: String?
    var cards: [CardWords]?
    var step: Step?

    var toGive: Bool { state == "to_give" }
    var given: Bool { state == "given" }

    /// Read from `GET /v1/setup`'s answer; nil from a tafs cloud that sends no `tools`. Read as the
    /// iPad reads it: the batch's lines and the Cards only beside the body they'd sign.
    static func read(_ body: Data) -> CoachTools? {
        guard let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let fields = root["tools"] as? [String: Any] else { return nil }
        var tools = CoachTools()
        tools.state = fields["state"] as? String ?? "unknown"
        tools.taken = fields["taken"] as? String
        if let connect = fields["connect"] as? [String: Any], connect["body"] != nil {
            tools.connectLines = (connect["lines"] as? [Any])?.compactMap { $0 as? String } ?? []
        }
        if let card = fields["card"] as? [String: Any], card["body"] != nil {
            tools.cardTitle = card["card_title"] as? String
            tools.cards = (card["cards"] as? [Any] ?? []).compactMap { item in
                guard let c = item as? [String: Any] else { return nil }
                let title = (c["title"] as? String) ?? (c["card_title"] as? String) ?? (c["label"] as? String)
                let lines = (c["lines"] as? [Any])?.compactMap { $0 as? String } ?? []
                // A Card the app can't read is left out.
                if title == nil && lines.isEmpty { return nil }
                return CardWords(title: title ?? "", lines: lines)
            }
        }
        if let step = fields["coach_tools_step"] as? [String: Any] { tools.step = Self.step(step) }
        return tools
    }

    private static func text(_ fields: [String: Any], _ key: String) -> String { fields[key] as? String ?? "" }

    /// The step, read leniently as the iPad's `Step`: a group or tool that isn't an object is left
    /// out, and a tool with no name too.
    private static func step(_ f: [String: Any]) -> Step {
        var step = Step(title: text(f, "title"), intro: text(f, "intro"), details: text(f, "details"), ask: text(f, "ask"),
                        give: text(f, "give"), notNow: text(f, "not_now"), row: text(f, "row"))
        step.groups = (f["groups"] as? [Any] ?? []).compactMap { item in
            guard let g = item as? [String: Any] else { return nil }
            let tools: [Step.Tool] = (g["tools"] as? [Any] ?? []).compactMap { item in
                guard let t = item as? [String: Any] else { return nil }
                let tool = Step.Tool(name: text(t, "name"), does: text(t, "does"), why: text(t, "why"))
                return tool.name.isEmpty ? nil : tool
            }
            return Step.Group(name: text(g, "name"), line: text(g, "line"), tools: tools)
        }
        return step
    }

    /// tafs cloud's words where it sends them; the app's own only for a tafs cloud from before
    /// them, as the iPad's `CoachToolsSheet.said`.
    static func said(_ server: String?, _ own: String) -> String {
        guard let server, !server.trimmingCharacters(in: .whitespaces).isEmpty else { return own }
        return server
    }

    /// The row above Coach's conversation: shown while tafs cloud says the tools aren't given.
    var showsRow: Bool { !given }

    /// The row's line, as the iPad's `CoachToolsRow.words`.
    func rowWords(_ words: Words) -> String { Self.said(step?.row, words("coach.tools.title")) }

    /// The step's title, as the iPad's `CoachToolsSheet.title`.
    func title(_ words: Words) -> String { Self.said(step?.title, words("coach.tools.title")) }

    /// Not now's words.
    func notNow(_ words: Words) -> String { Self.said(step?.notNow, words("common.not_now")) }

    /// What the step says for a state other than `to_give`: which name is taken, or that it
    /// isn't known. Nil for `to_give`, which draws the step.
    func stateLine(_ words: Words) -> String? {
        switch state {
        case "taken": return taken.map { words("coach.taken.named", ["name": $0]) } ?? words("coach.taken.unnamed")
        case "to_give": return nil
        default: return words("coach.tools_unknown")
        }
    }
}

extension CloudClient {
    /// The account's Coach and its tools, from one `GET /v1/setup`: the same read as `coach()`, its
    /// answer's `tools` read too. A plain read: it sends no time zone, so it changes nothing.
    func coachAndTools() async throws -> (Coach?, CoachTools?) {
        struct Answer: Decodable { let setup: Coach? }
        let body = try await read("/v1/setup")
        let answer: Answer = try decoded(body)
        return (answer.setup, CoachTools.read(body))
    }
}

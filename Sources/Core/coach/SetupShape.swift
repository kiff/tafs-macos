import Foundation

/// What Coach's conversation has made so far, for the "Taking shape" panel beside it on a wide
/// Coach, as the iPad's `SetupShape` (Model/SetupShape.swift, kiff/tafs#85): the taf's name, the
/// plan, the tools it connects and the Card KIFF drafted. Read only from what Coach already holds:
/// the thread, planque's grants and KIFF's drafts. Nothing here asks a server for more.
struct SetupShape: Equatable {
    struct Step: Equatable {
        enum State: Equatable { case done, needsYou, now, toDo, failed, skipped }
        let label: String
        let state: State

        /// The plan's mark for it, as the iPad's `SetupShapePanel.mark`.
        var mark: String {
            switch state {
            case .done: return "done"
            case .failed: return "failed"
            case .needsYou, .now: return "active"
            case .toDo, .skipped: return "pending"
            }
        }
    }

    /// A vendor the conversation connects, from planque's grant.
    struct Tool: Equatable, Identifiable {
        enum State: Equatable { case connected, signedIn, waiting, failed(String?) }
        let id: String
        let vendor: String
        let state: State
        /// The tools the taf calls through it, once connected.
        let actions: [String]
    }

    /// The taf's Cards as KIFF drafted them: a draft until the owner confirms it.
    struct Card: Equatable {
        let title: String
        let lines: [String]
        let confirmed: Bool
    }

    var name: String?
    /// The plan's title, such as "Connect Stripe".
    var title: String?
    var steps: [Step] = []
    var tools: [Tool] = []
    var card: Card?

    var isEmpty: Bool { name == nil && steps.isEmpty && tools.isEmpty && card == nil }

    /// The kinds of card that ask something of the person, as the iPad's `SetupThread.needsOwner`.
    static let asks: Set<String> = ["confirm", "questions", "approval", "sign_in", "drive"]

    /// The card waiting for the person, by key, as the iPad's `setupWaiting`: the latest ask that
    /// still waits, an approval or a sign-in only while it needs them.
    static func waiting(in page: Thread.Page, grants: [AppConnections.Grant]) -> String? {
        page.cards.last { card in
            guard asks.contains(card.type), card.waitsForPerson else { return false }
            let grant = grants.first { $0.id == card.grant }
            switch card.type {
            case "approval": return ApprovalLines.state(card, grant: grant) == .needsYou
            case "sign_in": return ApprovalLines.signInState(card, grant: grant) == .needsYou
            default: return true
            }
        }?.key
    }

    init(page: Thread.Page, grants: [AppConnections.Grant], drafts: [String: AccountClient.Draft], _ words: Words) {
        let shown = page.cards
        let waiting = Self.waiting(in: page, grants: grants)
        name = shown.last { $0.type == "result" && $0.tafName != nil }?.tafName

        if let plan = shown.last(where: { $0.type == "steps" }) {
            // The plan, as Coach keeps it. Its step at work waits for the person when a card does.
            title = plan.title
            var waited = false
            steps = plan.plan.map { step in
                switch step.status {
                case "done": return Step(label: step.label, state: .done)
                case "failed": return Step(label: step.label, state: .failed)
                case "skipped": return Step(label: step.label, state: .skipped)
                case "active":
                    let needsYou = waiting != nil && !waited
                    waited = waited || needsYou
                    return Step(label: step.label, state: needsYou ? .needsYou : .now)
                default: return Step(label: step.label, state: .toDo)
                }
            }
        } else {
            // No plan shown: what Coach asked of the person, and where each stands.
            steps = shown.filter { Self.asks.contains($0.type) }.map { c in
                let grant = grants.first { $0.id == c.grant }
                let vendor = grant?.vendor ?? c.service
                let label: String
                switch c.type {
                case "approval": label = words("coach.shape.approve_named", ["vendor": vendor ?? words("coach.shape.the_connection")])
                case "sign_in": label = vendor.map { words("coach.sign_in.at", ["vendor": $0]) } ?? words("coach.sign_in.at_vendor")
                default: label = c.text ?? c.title ?? words("needs_you.answer")
                }
                if c.key == waiting { return Step(label: label, state: .needsYou) }
                if c.type == "confirm" {
                    // Answered, or written past: the conversation went on without it.
                    return Step(label: label, state: c.answerState == "answered" ? .done : .skipped)
                }
                let state: ApprovalLines.State
                switch c.type {
                case "approval": state = ApprovalLines.state(c, grant: grant)
                case "sign_in": state = ApprovalLines.signInState(c, grant: grant)
                default: state = .needsYou
                }
                switch state {
                case .done: return Step(label: label, state: .done)
                case .declined: return Step(label: label, state: .skipped)
                case .failed: return Step(label: label, state: .failed)
                case .needsYou: return Step(label: label, state: .toDo)
                }
            }
        }

        // The grants the conversation's cards name, in the order they came, each once.
        var seen: Set<String> = []
        tools = shown.compactMap { c -> Tool? in
            guard let id = c.grant, !seen.contains(id), let grant = grants.first(where: { $0.id == id }) else { return nil }
            seen.insert(id)
            let state: Tool.State
            if grant.connected {
                state = .connected
            } else if grant.failed {
                // planque's words for its state, never its `reason` (English, for the log).
                state = .failed(grant.statusWords.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 })
            } else if grant.holdsSignIn {
                state = .signedIn
            } else {
                state = .waiting
            }
            return Tool(id: id, vendor: grant.vendor, state: state, actions: grant.connected ? grant.tools.map(\.action) : [])
        }

        // The latest draft an approval names that KIFF has shown this Mac.
        let named = shown.filter { $0.type == "approval" }.compactMap { c in c.draft.flatMap { drafts[$0] } }
        if let draft = named.last(where: { $0.holdsTools }) {
            card = Card(title: draft.cardTitle(words), lines: draft.lines(words), confirmed: draft.confirmed)
        }
    }

    /// The plan's eyebrow: how many of its steps are done.
    func progress(_ words: Words) -> String {
        words("coach.plan.progress", ["done": words.number(steps.filter { $0.state == .done }.count), "total": words.number(steps.count)])
    }

    /// A tool's state in the shared words, and its tone.
    static func status(_ state: Tool.State, _ words: Words) -> (String, ApprovalLines.Tone) {
        switch state {
        case .connected: return (words("connect.status.connected"), .ok)
        case .signedIn: return (words("coach.answer.signed_in"), .amber)
        case .waiting: return (words("chat.waiting_for_you"), .amber)
        case .failed: return (words("coach.shape.not_connected"), .no)
        }
    }

    /// The panel shows beside Coach's conversation at this width or wider, as the iPad's `shaping`.
    static let widest: Double = 780
    /// Its own width.
    static let width: Double = 420

    /// Whether the panel shows: Coach's own conversation, read, at least 780 across. The iPad also
    /// waits for `planqueReady`, which this Mac is only after a Start made on it.
    static func shows(width: Double, coach: Bool) -> Bool { coach && width >= widest }
}

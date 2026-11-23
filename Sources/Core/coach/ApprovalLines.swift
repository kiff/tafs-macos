import Foundation

/// An approval card in Coach's chat, drawn up to the approval as the iPad's `SetupApproval`
/// (SetupChatView.swift:1495-1803): where it stands, its eyebrow, the line it folds to, the Card
/// KIFF drafted for it or tafs cloud's Card-next words, and why it didn't go through. Approving
/// it is the phone's: it grants at planque or confirms KIFF's Card, so nothing here builds an
/// answer but `declined` (`CloudClient.decline`).
enum ApprovalLines {
    /// An approval's answer, as the iPad's `SetupThread.answer(_:to:)` reads it for an approval
    /// (SetupComponent.swift:345-409): from tafs cloud's settled `answer` when it sends one, else
    /// its exact English words. **Nothing reads as approved by default.**
    enum Answer: Equatable {
        case approved
        case alreadyApproved
        case declined
        /// Not approved: tafs cloud's line for the owner when it refused the request (`refused`).
        case failed(refused: String?)
    }

    /// What tafs cloud's English words for a failed answer put before why.
    static let didntGoThrough = " · it didn't go through: "

    /// The approval's answer, once the person answered it (`answered`); nil before, or for an
    /// answer they wrote past.
    static func answer(_ card: Thread.Card) -> Answer? {
        guard card.type == "approval", card.answerState == "answered" else { return nil }
        let words = card.answered ?? ""
        let text: String
        if let stored = card.stored {
            switch stored {
            case "approved", "connected": text = "approved"
            case "declined": text = "declined"
            default:
                if stored == "already approved" || stored.hasPrefix("already approved:") { text = "already approved" }
                else if stored.hasPrefix("failed: ") { text = stored }
                else { text = "failed: " + words }
            }
        } else if let r = words.range(of: didntGoThrough) {
            text = "failed: " + words[r.upperBound...]
        } else {
            switch words {
            case "Approved": text = "approved"
            case "Already approved": text = "already approved"
            case "Declined": text = "declined"
            default: text = "failed: " + words
            }
        }
        switch text {
        case "approved": return .approved
        case "already approved": return .alreadyApproved
        case "declined": return .declined
        default:
            // tafs cloud's line for a refused approval, whole: only when its settled answer says so.
            let line = words.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed(refused: card.stored?.hasPrefix("failed: ") == true && !line.isEmpty ? line : nil)
        }
    }

    /// Where an approval stands, as the iPad's `setupCardState` (AppModel.swift:9279-9302), without
    /// the phone's own approving: finished only by its answer; declined; failed by its answer or by
    /// planque's state for its grant, in planque's words.
    enum State: Equatable {
        case needsYou
        case done
        case declined
        case failed(String?)
        var isFailure: Bool { if case .failed = self { return true } else { return false } }
    }

    static func state(_ card: Thread.Card, grant: AppConnections.Grant?) -> State {
        // As the iPad's `approvalFinished` (AppModel.swift:9295-9302): planque failed the grant
        // after the owner approved, so the card says so with planque's why, whatever the answer
        // said. The Mac reads the grant only with the card in the thread, as the iPad's
        // `grantsReadFor` asks.
        let grantFailed = grant?.failed == true
        switch answer(card) {
        case .approved?, .alreadyApproved?: if !grantFailed { return .done }
        case .declined?: return .declined
        case .failed?: return .failed(nil)
        case nil: break
        }
        if let grant, grant.failed {
            return .failed(grant.statusWords.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 })
        }
        return .needsYou
    }

    /// A sign-in's state, as the iPad's `setupCardState` for one: Not now, didn't go through,
    /// signed in or its grant connected or listed, planque failed it, else it waits.
    static func signInState(_ card: Thread.Card, grant: AppConnections.Grant?) -> State {
        if card.answerState == "answered" {
            let words = card.answered ?? ""
            if words.range(of: didntGoThrough) != nil { return .failed(nil) }
            return words == "Signed in" ? .done : .declined
        }
        if let grant, grant.connected || grant.listed { return .done }
        if let grant, grant.failed {
            return .failed(grant.statusWords.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 })
        }
        return .needsYou
    }

    /// The eyebrow and its tone, in the iPad's order: an earlier request first, then the state.
    enum Tone: Equatable { case ok, dim, no, amber }

    static func eyebrow(_ state: State, replaced: Bool, _ words: Words) -> (String, Tone) {
        if replaced { return (words("coach.earlier_request"), .dim) }
        switch state {
        case .done: return (words("coach.answer.approved_short"), .ok)
        case .declined: return (words("coach.answer.declined_short"), .dim)
        case .failed: return (words("coach.answer.failed_short"), .no)
        case .needsYou: return (words("coach.needs_you_approve"), .amber)
        }
    }

    /// What a replaced card says, folded, as the iPad's `replacedLine` (SetupChatView.swift:1515-1521):
    /// what the person did with it, then where to look.
    static func replacedLine(_ card: Thread.Card, _ words: Words) -> String {
        switch answer(card) {
        case .approved?: return words("coach.answer.approved_more_below")
        case .declined?: return words("coach.answer.declined_again_below")
        default: return words("coach.setup_changed_request_see_below")
        }
    }

    /// The Card an approved card signed: KIFF took the signature, and it holds tools.
    static func signedCard(_ draft: AccountClient.Draft?) -> AccountClient.Draft? {
        guard let draft, draft.signed, draft.holdsTools else { return nil }
        return draft
    }

    /// An answered approval in one line, as the iPad's `outcome(_:_:)` (SetupChatView.swift:1597-1618):
    /// the signed Card named first, then Coach's title for the card, else the Card drafted, else
    /// the vendor.
    static func outcome(_ card: Thread.Card, _ state: State, grant: AppConnections.Grant?, draft: AccountClient.Draft?, _ words: Words) -> String {
        let signed = state == .done ? signedCard(draft)?.cardTitle(words) : nil
        let title = card.title?.trimmingCharacters(in: .whitespaces)
        let named = title.flatMap { $0.isEmpty ? nil : $0 }
        let vendor = (grant?.vendor ?? card.service).map(CallNames.vendorWords) ?? words("coach.the_vendor")
        if state == .done, answer(card) == .alreadyApproved {
            return "\(words("coach.already_approved")) · \(signed ?? named ?? vendor)"
        }
        if let signed { return words("coach.answer.approved_title", ["title": signed]) }
        if let named {
            return words(state == .declined ? "coach.answer.declined_title" : "coach.answer.approved_title", ["title": named])
        }
        if let draft, draft.holdsTools {
            return words(state == .declined ? "coach.answer.declined_title" : "coach.answer.approved_title", ["title": draft.cardTitle(words)])
        }
        if state == .declined { return words("coach.answer.declined_title", ["title": vendor]) }
        if grant?.connected == true { return words("coach.answer.approved_connected", ["vendor": vendor]) }
        return words("coach.approved_signed", ["vendor": vendor])
    }

    /// The line under the folded one: the signed Card's lines, as the iPad's `signedCardLines`.
    static func signedLines(_ state: State, draft: AccountClient.Draft?, _ words: Words) -> [String] {
        state == .done ? signedCard(draft)?.lines(words) ?? [] : []
    }

    /// The connection's line, as the iPad's card draws it from planque's grant: tafs cloud's line
    /// for one already made, else connected, else signed in and reading what the vendor offers.
    /// Nil where the phone shows planque's own words for the request, which this Mac doesn't read.
    static func connectionLine(_ card: Thread.Card, grant: AppConnections.Grant?, _ words: Words) -> String? {
        if let done = card.connectionWords { return done }
        guard let grant else { return nil }
        if grant.connected { return words("coach.connected_keys_kept_sealed", ["vendor": grant.vendor]) }
        if grant.listed { return words("coach.signed_reading_what_offers", ["vendor": grant.vendor]) }
        return nil
    }

    /// tafs cloud's words for a Card approved next, on a card with no draft (an app's first
    /// sign-in), as the iPad's `cardNextWords`: none when its mark says the Card is signed now,
    /// or the connection is already made.
    static func cardNextWords(_ card: Thread.Card) -> String? {
        guard card.draft == nil, card.signs?.card != true, card.connectionWords == nil else { return nil }
        return card.signs?.words
    }

    /// Whether the Card KIFF drafted is drawn: read, with Cards, and not marked next with no words.
    static func drawsDraft(_ card: Thread.Card, _ draft: AccountClient.Draft?) -> Bool {
        guard let draft, draft.cards != nil else { return false }
        return !(card.signs?.cardNext == true && card.signs?.words == nil)
    }

    /// Why a failed approval didn't go through, as the iPad's: tafs cloud's line for a refused
    /// request, whole; else planque's why; else that nothing came of it.
    static func failedLine(_ card: Thread.Card, _ state: State, _ words: Words) -> String? {
        guard case .failed(let why) = state else { return nil }
        if case .failed(let refused?)? = answer(card) { return refused }
        return why.map { words("coach.answer.failed_why", ["value": $0]) } ?? words("coach.did_not_go_through_nothing")
    }

    /// Sent again unchanged it would fail the same way: planque failed its grant, as the iPad's
    /// `requestRefused` (AppModel.swift:10113-10117). The phone's own refusals it remembers aren't here.
    static func requestRefused(_ state: State, grant: AppConnections.Grant?) -> Bool {
        state.isFailure && grant?.status == "failed"
    }

    /// Whether an approval offers Decline, as the iPad's `SetupApproval` (SetupChatView.swift:1757-1764):
    /// not replaced, not a request planque refused, and waiting or failed, even one already
    /// answered that didn't go through. Declining grants nothing, so it is never signed.
    static func declinable(_ card: Thread.Card, _ state: State, replaced: Bool, grant: AppConnections.Grant?) -> Bool {
        guard card.type == "approval", !replaced, !requestRefused(state, grant: grant) else { return false }
        return state == .needsYou || state.isFailure
    }
}

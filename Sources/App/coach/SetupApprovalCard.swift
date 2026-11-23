import SwiftUI

/// An approval in Coach's chat, waiting, failed or opened again, drawn up to the approval as the
/// iPad's `SetupApproval.card` (SetupChatView.swift:1620-1802): its state, Coach's words for it, the
/// connection's line, the Card KIFF drafted for it (or tafs cloud's words for a Card approved next),
/// the wider line, why it didn't go through, then Decline and, in Approve's place, where to
/// approve. Approving grants at planque or confirms KIFF's Card: the phone's, so nothing here
/// approves. A card a newer request for the same connection replaced is history: its words only.
struct SetupApprovalCard: View {
    @Environment(\.words) private var words
    @ObservedObject var model: CoachModel
    let card: Thread.Card
    let replaced: Bool
    let state: ApprovalLines.State
    let grant: AppConnections.Grant?
    /// Whether this Mac can sign an approval: never yet, so Approve's place says where to approve.
    let canApprove: Bool
    /// Opened again from its folded line: Fold folds it.
    let open: Bool
    let fold: () -> Void

    var body: some View {
        let (eyebrow, tone) = ApprovalLines.eyebrow(state, replaced: replaced, words)
        let stroke: Color = replaced ? Theme.line : state == .done ? Theme.ok : state.isFailure ? Theme.no : Theme.amber
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow(text: eyebrow, color: Self.color(tone))
                Spacer()
                if open {
                    Button(action: fold) { Text(words("coach.plan.fold_short")).font(.system(size: 13)).foregroundColor(Theme.dim) }
                        .buttonStyle(.plain)
                }
            }
            asked
            ApprovalDraft(model: model, card: card, replaced: replaced, grant: grant)
            // A sign-in that asks for more than the job, said above the buttons, in tafs cloud's words.
            if !replaced, let wider = card.widerWords { WiderLine(words: wider) }
            outcome
            if !replaced { answers }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).stroke(stroke))
    }

    static func color(_ tone: ApprovalLines.Tone) -> Color {
        switch tone {
        case .ok: return Theme.ok
        case .dim: return Theme.dim
        case .no: return Theme.no
        case .amber: return Theme.amberText
        }
    }

    /// What it asks, in Coach's words (where the phone shows planque's), and the connection's line.
    @ViewBuilder private var asked: some View {
        if let title = card.title { Text(verbatim: title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink) }
        if let text = card.text {
            Text(verbatim: text).font(.system(size: 15)).foregroundColor(Theme.ink).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        }
        if let connection = ApprovalLines.connectionLine(card, grant: grant, words) {
            Label(connection, systemImage: "checkmark.circle.fill").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ok)
                .accessibilityIdentifier("approval.connection-done")
        }
    }

    /// Opened again once replaced, where to look; else why it didn't go through.
    @ViewBuilder private var outcome: some View {
        if replaced {
            Text(words("coach.newer_request_connection_below")).font(.system(size: 13)).foregroundColor(Theme.soft)
                .fixedSize(horizontal: false, vertical: true)
        } else if let failed = ApprovalLines.failedLine(card, state, words) {
            Text(verbatim: failed).font(.system(size: 14)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Decline, while it waits, and in Approve's place where to approve; a request planque refused
    /// says Coach has to change it instead.
    @ViewBuilder private var answers: some View {
        if ApprovalLines.requestRefused(state, grant: grant) {
            Text(words("coach.coach_mode_has_change_request")).font(.system(size: 13)).foregroundColor(Theme.soft)
                .fixedSize(horizontal: false, vertical: true)
        } else if state == .needsYou || state.isFailure {
            if model.answering == card.key {
                Text(words("coach.answering")).font(.system(size: 13)).foregroundColor(Theme.soft)
            } else if ApprovalLines.declinable(card, state, replaced: replaced, grant: grant) {
                // Saying no grants nothing, so it's never signed: any Mac may, as the iPad's Decline,
                // on a failed card already answered too.
                OutlineAction(title: words("coach.approval.decline")) { Task { await model.decline(card) } }
                    .disabled(model.answering != nil)
            }
            if !canApprove {
                // No Approve here: this Mac can't sign one. The phone has the same card.
                Text(words("approval.device_can_not_approve_approve")).font(.system(size: 12)).foregroundColor(Theme.soft)
                    .frame(maxWidth: .infinity)
            }
            if let why = model.notAnswered[card.key] {
                Text(words("coach.answer.failed_why", ["value": why])).font(.system(size: 12)).foregroundColor(Theme.no)
            }
        }
    }
}

/// The taf's Card as the approval would sign it, in KIFF's lines for the draft it names, as the
/// iPad's card draws it (SetupChatView.swift:1706-1745): under tafs cloud's words, dimmed, when the
/// Card is approved next; said while KIFF's draft is read, or why it couldn't be, with Try again;
/// or, with no draft and planque's grant read, tafs cloud's words for a Card approved next.
struct ApprovalDraft: View {
    @Environment(\.words) private var words
    @ObservedObject var model: CoachModel
    let card: Thread.Card
    let replaced: Bool
    /// planque's grant for it: tafs cloud's words for a Card next are drawn only once it is read.
    let grant: AppConnections.Grant?

    var body: some View {
        let read = card.draft.flatMap { model.drafts[$0] }
        let draft = read?.draft
        return Group {
            if let draft, ApprovalLines.drawsDraft(card, draft) {
                drawn(draft)
            } else if let id = card.draft, draft == nil, !replaced, card.answerState == nil {
                // The Card isn't read yet: said, never a blank. KIFF's why, with Try again.
                if case .failed(let why)? = read {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(words("coach.card_draft_not_read", ["why": why])).font(.system(size: 13)).foregroundColor(Theme.no)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(words("common.try_again")) { Task { await model.read(draft: id) } }
                            .font(.system(size: 13, weight: .semibold))
                            .accessibilityIdentifier("approval.draft-try-again")
                    }
                } else {
                    Text(words("coach.reading_kiff_words")).font(.system(size: 13)).foregroundColor(Theme.dim)
                }
            } else if let next = ApprovalLines.cardNextWords(card, grant: grant) {
                Text(verbatim: next).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("approval.card-next")
            }
        }
    }

    private func drawn(_ draft: AccountClient.Draft) -> some View {
        let next = card.signs?.cardNext == true
        return VStack(alignment: .leading, spacing: 6) {
            if next, let said = card.signs?.words {
                Text(verbatim: said).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("approval.card-next")
            } else {
                Eyebrow(text: draft.cardTitle(words))
            }
            ForEach(Array(draft.lines(words).enumerated()), id: \.offset) { _, line in
                Text(verbatim: line).font(.system(size: 12, design: .monospaced)).foregroundColor(next ? Theme.dim : Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.raised))
    }
}

/// The iPad's outlined button: 15 medium, at least 48 high, corner 14, its colour at 0.4.
struct OutlineAction: View {
    let title: String
    var color: Color = Theme.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title).font(.system(size: 15, weight: .medium)).foregroundColor(color)
                .frame(maxWidth: .infinity, minHeight: 48)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(color.opacity(0.4)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

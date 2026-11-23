import SwiftUI

/// Beside Coach's conversation on a wide Coach, as the iPad's `SetupShapePanel` (kiff/tafs#85): what
/// it has made so far, the taf's name, the plan, the tools it connects and the Card KIFF drafted.
/// Only what Coach already holds (`SetupShape`); the cards to answer stay in the conversation.
struct SetupShapePanel: View {
    @Environment(\.words) private var words
    let shape: SetupShape

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: words("coach.shape.taking_shape"))
                    if let heading = shape.name ?? shape.title {
                        Text(verbatim: heading).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundColor(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if shape.isEmpty {
                        Text(words("billing.conversation_goes_plan_tools_being")).font(.system(size: 14)).foregroundColor(Theme.soft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !shape.steps.isEmpty { plan }
                if !shape.tools.isEmpty { tools }
                if let card = shape.card { ShapeCard(card: card) }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Coach mode's blue, a shade deeper than the conversation beside it.
        .background(Theme.coachPanel)
    }

    private var plan: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: shape.progress(words))
            ForEach(Array(shape.steps.enumerated()), id: \.offset) { _, step in
                HStack(alignment: .top, spacing: 10) {
                    StepMark(status: step.mark).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: step.label)
                            .strikethrough(step.state == .skipped)
                            .font(.system(size: 14, weight: step.state == .needsYou || step.state == .now ? .semibold : .regular))
                            .foregroundColor(step.state == .toDo || step.state == .skipped ? Theme.dim : Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if step.state == .needsYou {
                            Text(words("needs_you.title")).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.amberText)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: words("coach.tools_eyebrow"))
            ForEach(shape.tools) { tool in ShapeTool(tool: tool) }
            Text(words("connect.sign_ins_kept_sealed_no")).font(.system(size: 12)).foregroundColor(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A vendor the conversation connects, with its state and, once connected, the tools it brings.
private struct ShapeTool: View {
    @Environment(\.words) private var words
    let tool: SetupShape.Tool

    var body: some View {
        let (status, tone) = SetupShape.status(tool.state, words)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(verbatim: tool.vendor).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                Spacer(minLength: 8)
                Text(verbatim: status).font(.system(size: 12, weight: .semibold)).foregroundColor(SetupApprovalCard.color(tone))
            }
            if !tool.actions.isEmpty {
                Text(verbatim: tool.actions.joined(separator: ", ")).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.soft)
            }
            if case .failed(let why?) = tool.state {
                Text(verbatim: why).font(.system(size: 12)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line))
        .accessibilityElement(children: .combine)
    }
}

/// The Card KIFF drafted, in KIFF's lines: dashed until the owner confirms it.
private struct ShapeCard: View {
    @Environment(\.words) private var words
    let card: SetupShape.Card

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: words(card.confirmed ? "card.card_confirmed_kiff" : "card.card_draft_kiff"))
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: card.title).font(.system(size: 13, weight: .semibold, design: .monospaced))
                ForEach(Array(card.lines.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line).font(.system(size: 12, design: .monospaced)).fixedSize(horizontal: false, vertical: true)
                }
                if card.lines.isEmpty { Text(words("card.no_actions_short")).font(.system(size: 12, design: .monospaced)) }
            }
            .foregroundColor(Theme.ink)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(card.confirmed ? Theme.ok : Theme.ink.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: card.confirmed ? [] : [5, 4])))
            if !card.confirmed {
                Text(words("coach.shape.draft_until_approved")).font(.system(size: 12)).foregroundColor(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A plan step's mark, as the iPad's `StepMark`: done and failed filled, the step at work ringed in
/// amber, the rest a faint ring; read out in the shared words, never tafs cloud's status.
struct StepMark: View {
    @Environment(\.words) private var words
    let status: String

    var body: some View {
        ZStack {
            switch status {
            case "done":
                Circle().fill(Theme.ok)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundColor(Theme.onFill)
            case "failed":
                Circle().fill(Theme.no)
                Image(systemName: "xmark").font(.system(size: 9, weight: .heavy)).foregroundColor(Theme.onFill)
            case "active":
                Circle().stroke(Theme.amber, lineWidth: 2.5)
            default:
                Circle().stroke(Theme.ink.opacity(0.25), lineWidth: 1.5)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityLabel(words(Self.key(status)))
    }

    static func key(_ status: String) -> String {
        switch status {
        case "done": return "coach.plan.step_done"
        case "failed": return "coach.plan.step_failed"
        case "active": return "coach.plan.step_active"
        case "skipped": return "coach.plan.step_skipped"
        default: return "coach.plan.step_pending"
        }
    }
}

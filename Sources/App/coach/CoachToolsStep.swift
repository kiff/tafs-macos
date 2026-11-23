import SwiftUI

/// Coach's tools still to give, as one line above Coach's conversation, as the iPad's
/// `CoachToolsRow` (CoachToolsStep.swift:6-34): it opens the step. Nothing once the tools are
/// given, or before tafs cloud has said.
struct CoachToolsRow: View {
    @Environment(\.words) private var words
    let tools: CoachTools
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 8) {
                Text(verbatim: tools.rowWords(words)).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.amberText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundColor(Theme.dim).accessibilityHidden(true)
            }
            .padding(.horizontal, Look.inset)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Theme.background)
        .accessibilityIdentifier("coach-tools-row")
        .sheet(isPresented: $open) {
            CoachToolsSheet(tools: tools) { open = false }.environment(\.words, words)
        }
    }
}

/// Coach's tools as a step of their own, as the iPad's `CoachToolsSheet` (CoachToolsStep.swift:41-122):
/// what tafs cloud says is still to give, in its words, each tool and Coach's Cards folded under a
/// few groups; then, in Give's place, where to give them, and Not now. Giving them signs tafs
/// cloud's batch and Coach's Cards' draft with the approval key: the phone's, so nothing here
/// gives them or sends anything.
struct CoachToolsSheet: View {
    @Environment(\.words) private var words
    let tools: CoachTools
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: tools.title(words)).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.ink)
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    content
                    Button(action: close) {
                        Text(verbatim: tools.notNow(words)).font(.system(size: 15, weight: .medium)).foregroundColor(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.ink.opacity(0.4)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("coach-tools-not-now")
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 600)
        .background(Theme.background)
    }

    @ViewBuilder private var content: some View {
        if let said = tools.stateLine(words) {
            CoachToolsLine(words: said, size: 15, color: Theme.ink)
        } else {
            if let intro = tools.step?.intro, !intro.isEmpty, !(tools.step?.groups.isEmpty ?? true) {
                CoachToolsLine(words: intro, size: 15, color: Theme.soft)
            }
            CoachToolsGiven(tools: tools)
            if let ask = tools.step?.ask, !ask.isEmpty { CoachToolsLine(words: ask, size: 15, color: Theme.ink, weight: .semibold).padding(.top, 6) }
            // Give's place: the one confirmation that gives them is the phone's.
            Text(words("approval.device_can_not_approve_approve")).font(.system(size: 12)).foregroundColor(Theme.soft)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("coach-tools-give")
        }
    }
}

/// What's given to Coach, as the iPad's `CoachToolsGiven` in the step (`stepBody`,
/// CoachToolsStep.swift:194-248): a few groups up front, each tool and its limits folded under them
/// with Coach's Cards in KIFF's words. Every word is tafs cloud's or KIFF's.
struct CoachToolsGiven: View {
    let tools: CoachTools
    @State private var folded = true

    var body: some View {
        let step = tools.step
        let grouped = !(step?.groups.isEmpty ?? true)
        let open = !grouped || (step?.details.isEmpty ?? true) || !folded
        return VStack(alignment: .leading, spacing: 10) {
            if let step, grouped {
                ForEach(Array(step.groups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 2) {
                        CoachToolsLine(words: group.name, size: 15, color: Theme.ink, weight: .semibold)
                        if !group.line.isEmpty { CoachToolsLine(words: group.line, size: 14, color: Theme.soft) }
                    }
                    .padding(.top, 4)
                }
                if !step.details.isEmpty { details(step.details) }
            }
            if open {
                if let step, grouped {
                    ForEach(Array(step.groups.enumerated()), id: \.offset) { _, group in groupTools(group) }
                } else if let lines = tools.connectLines {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, said in CoachToolsLine(words: said, size: 14, color: Theme.ink) }
                }
                cards
            }
        }
    }

    /// The fold over each tool and the Cards, in tafs cloud's words.
    private func details(_ said: String) -> some View {
        Button { folded.toggle() } label: {
            HStack(spacing: 6) {
                Text(verbatim: said).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.amberText)
                Image(systemName: folded ? "chevron.down" : "chevron.up").font(.system(size: 12)).foregroundColor(Theme.amberText)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("coach-tools-details")
    }

    /// One group's tools, with what each does and why.
    @ViewBuilder private func groupTools(_ group: CoachTools.Step.Group) -> some View {
        if !group.tools.isEmpty { CoachToolsLine(words: group.name, size: 13, color: Theme.ink, weight: .semibold).padding(.top, 4) }
        ForEach(Array(group.tools.enumerated()), id: \.offset) { _, tool in
            VStack(alignment: .leading, spacing: 2) {
                CoachToolsLine(words: tool.name, size: 14, color: Theme.ink, weight: .semibold)
                if !tool.does.isEmpty { CoachToolsLine(words: tool.does, size: 13, color: Theme.ink) }
                if !tool.why.isEmpty { CoachToolsLine(words: tool.why, size: 13, color: Theme.soft) }
            }
        }
    }

    /// Coach's Cards in KIFF's own words.
    @ViewBuilder private var cards: some View {
        if let title = tools.cardTitle, !title.isEmpty { CoachToolsLine(words: title, size: 14, color: Theme.ink, weight: .semibold).padding(.top, 4) }
        ForEach(Array((tools.cards ?? []).enumerated()), id: \.offset) { _, card in
            VStack(alignment: .leading, spacing: 2) {
                if !card.title.isEmpty { CoachToolsLine(words: card.title, size: 13, color: Theme.ink, weight: .semibold) }
                ForEach(Array(card.lines.enumerated()), id: \.offset) { _, said in CoachToolsLine(words: said, size: 13, color: Theme.soft) }
            }
        }
    }
}

/// One of the step's lines, as tafs cloud or KIFF wrote it, wrapping.
struct CoachToolsLine: View {
    let words: String
    let size: CGFloat
    let color: Color
    var weight: Font.Weight = .regular

    var body: some View {
        Text(verbatim: words).font(.system(size: size, weight: weight)).foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

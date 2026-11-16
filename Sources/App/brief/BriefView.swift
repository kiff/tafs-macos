import SwiftUI

/// "Your brief", as the iPad's `BriefView` (BriefView.swift:7-139): decisions first, each with
/// Coach's recommendation and what happens meanwhile, then one next move, then what got done, case
/// by case; two columns, decisions beside Done, as on the iPad's width. Every word, count and order
/// is tafs cloud's; a recommendation is shown, never acted on, and nothing is signed from here.
/// Without a brief, or once a decision is opened, it's Needs you, as today.
struct BriefScreen<NeedsYouList: View>: View {
    @Environment(\.words) private var words
    @ObservedObject var model: BriefModel
    /// Needs you's own list, where every decision is answered.
    let needsYou: NeedsYouList
    /// How much of Needs you the brief doesn't show.
    var beyond = 0
    /// The tafs, to name each decision's.
    var tafs: [Home.Taf] = []
    /// The account's time zone, for a mission's log.
    var zone: String?
    /// Starts the next move with Coach; nil when this person may not use Coach.
    var startNextMove: ((String) -> Void)?
    /// Needs you shown in the brief's place, opened from it.
    @State private var showingList = false
    @State private var log: LogShown?

    struct LogShown: Identifiable { let mission: String; let title: String; var id: String { mission } }

    var body: some View {
        if let brief = model.brief, !showingList {
            screen(brief)
                .sheet(item: $log) { shown in
                    MissionLogView(title: shown.title, zone: zone, load: { await model.missionLog(shown.mission) }, close: { log = nil })
                        .environment(\.words, words)
                }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if let brief = model.brief {
                    Button { showingList = false } label: { Label(brief.words.tab, systemImage: "chevron.left") }
                        .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.coach)
                        .padding(.horizontal, Look.inset).padding(.top, 16)
                }
                needsYou
            }
        }
    }

    private func screen(_ brief: Brief) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(brief)
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) { decisions(brief) }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 14) {
                        done(brief)
                        // Under Done, so it stays in view beside the decisions (the iPad mockup).
                        nextMove(brief)
                        rest(brief)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                if let credits = brief.credits {
                    Text(verbatim: credits).font(.system(size: 12)).foregroundColor(Theme.dim).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Look.inset).padding(.top, 56).padding(.bottom, Look.inset)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
    }

    private func header(_ brief: Brief) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ScreenTitle(title: brief.words.title.isEmpty ? brief.words.tab : brief.words.title)
            if !brief.words.when.isEmpty {
                Label(brief.words.when, systemImage: "clock").font(.system(size: 13)).foregroundColor(Theme.soft)
            }
            // All, then two labels, then "+N": the tafs list's chips, filtering the brief.
            if !brief.labels.isEmpty {
                LabelChips(labels: brief.labels, selected: model.label, all: brief.words.all.isEmpty ? words("home.labels_all") : brief.words.all) { id in
                    Task { await model.filter(id) }
                }
            }
        }
    }

    @ViewBuilder private func decisions(_ brief: Brief) -> some View {
        let open = model.decisions
        if !open.isEmpty {
            Eyebrow(text: brief.words.decisions)
            ForEach(open) { decision in
                DecisionCard(decision: decision, words: brief.words, taf: tafs.first { $0.tafID == decision.ref.taf },
                             answer: { showingList = true }, later: { Task { await model.later(decision) } })
            }
            if let more = brief.more { Text(verbatim: more.words).font(.system(size: 13)).foregroundColor(Theme.soft) }
            if let why = model.laterRefused { Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no) }
        }
    }

    @ViewBuilder private func nextMove(_ brief: Brief) -> some View {
        if let move = brief.nextMove, !model.nextMoveDismissed {
            BriefPanel(stroke: Theme.amber.opacity(0.35)) {
                Label(brief.words.nextMove.uppercased(), systemImage: "sparkle").font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.amberText)
                Text(verbatim: move.words).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if let startNextMove {
                        Button(move.start) { model.dismissNextMove(); startNextMove(move.words) }.buttonStyle(OutlineButtonStyle(color: Theme.amberText))
                    }
                    Button(move.dismiss) { model.dismissNextMove() }.buttonStyle(OutlineButtonStyle())
                }
            }
        }
    }

    @ViewBuilder private func done(_ brief: Brief) -> some View {
        if !brief.done.isEmpty {
            Eyebrow(text: brief.words.done)
            BriefPanel {
                ForEach(Array(brief.done.enumerated()), id: \.element.id) { i, group in
                    if i > 0 { Divider() }
                    ForEach(group.cases) { item in CaseRow(item: item) }
                    if group.value != nil || group.log != nil { doneFoot(group, words: brief.words) }
                }
            }
        }
    }

    private func doneFoot(_ group: Brief.Done, words: Brief.Words) -> some View {
        HStack {
            if let value = group.value { Text(verbatim: value).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink) }
            Spacer()
            if let mission = group.log {
                Button { log = LogShown(mission: mission, title: group.mission ?? "") } label: {
                    Text(verbatim: words.evidence + " ›").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.coach)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The things that need nothing now, in one line: Needs you's list, unchanged, with its own
    /// count whenever it holds more than the brief's decisions.
    @ViewBuilder private func rest(_ brief: Brief) -> some View {
        let count = beyond > 0 ? words.count("needs_you.count", beyond) : nil
        if brief.rest != nil || count != nil {
            Button { showingList = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if let rest = brief.rest { Text(verbatim: rest.words).font(.system(size: 14)).foregroundColor(Theme.ink) }
                        if let count { Text(verbatim: count).font(.system(size: 13, weight: .semibold)).foregroundColor(brief.rest == nil ? Theme.ink : Theme.dim) }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.soft)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// A panel of the brief: the panel's ground and line, its parts spaced.
struct BriefPanel<Content: View>: View {
    var stroke: Color = Theme.line
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).stroke(stroke, lineWidth: 1))
    }
}

/// A case's line, as the iPad's `CaseRow` (BriefView.swift:261-278): green once the source says
/// it's closed, amber while it waits on someone.
struct CaseRow: View {
    let item: Brief.Case

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(item.closed ? Theme.ok : item.waiting ? Theme.amber : Theme.dim).frame(width: 7, height: 7).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if !item.name.isEmpty { Text(verbatim: item.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink) }
                Text(verbatim: item.words).font(.system(size: 13)).foregroundColor(item.closed ? Theme.ok : Theme.soft).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

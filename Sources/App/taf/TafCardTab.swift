import SwiftUI

/// A taf's Card tab, as the iPad's `card(_:)` (TafDetailView.swift:380-462): tafs cloud's words for
/// its time zone, the Cards as the wallet, what the front one lets the taf do, how KIFF counts it,
/// then, for whoever manages the taf, its halt, its versions, its usage and Revoke.
struct TafCardTab: View {
    @Environment(\.words) private var words
    let taf: Home.Taf
    /// Its Setup, halt and versions; nil where nothing reads them.
    let pages: TafPagesModel?
    let manages: Bool
    let issuedBy: String
    @Binding var front: String?
    var halted: () async -> Void = {}
    @State private var counting: TafCard?
    @State private var versionsOpen = false
    @State private var usageOpen = false
    @State private var confirmRevoke = false
    /// Why KIFF didn't revoke the Card, in the shared line.
    @State private var revokeFailed: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                timeZone
                cards
                managed
            }
            .padding(.bottom, Look.inset)
        }
        .sheet(item: $counting) { card in CountedView(card: card) { counting = nil }.environment(\.words, words) }
        .sheet(isPresented: $versionsOpen) {
            if let pages { VersionsView(model: pages) { versionsOpen = false }.environment(\.words, words) }
        }
        .sheet(isPresented: $usageOpen) {
            if let pages { TafCreditsView(model: pages.credits, name: taf.name) { usageOpen = false }.environment(\.words, words) }
        }
    }

    /// tafs cloud's words for the zone its times are in, and in amber for a schedule kept in
    /// another zone, as sent.
    @ViewBuilder private var timeZone: some View {
        if let zone = taf.timeZoneWords { Text(verbatim: zone).font(.system(size: 13)).foregroundColor(Theme.soft) }
        if let zone = taf.scheduleTimeZoneWords { Text(verbatim: zone).font(.system(size: 13)).foregroundColor(Theme.amberText) }
    }

    /// No Card listed says nothing: tafs cloud sends no field that says one was revoked. The Cards
    /// as the iPad's wallet: a click brings one to the front, and what's under it is the front one's.
    @ViewBuilder private var cards: some View {
        if !taf.cards.isEmpty {
            CardStack(cards: taf.cards, color: Theme.tafColor(taf.color), issuedBy: issuedBy, front: $front)
                .frame(maxWidth: .infinity)
            if let shown = CardStack.front(of: taf.cards, front) {
                // A Card with no rules has no panel under it, never an empty one.
                if !shown.rules.isEmpty { CardRulesPanel(card: shown) }
                // How KIFF counts each of its tools, as the owner approved it: its own sheet.
                if !shown.counted.isEmpty {
                    PanelLink(action: { counting = shown }) {
                        Label(words("card.how_counted"), systemImage: "list.bullet.rectangle")
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.amberText)
                    }
                    .accessibilityIdentifier("card-counted")
                }
            }
        }
    }

    /// For whoever manages the taf: halting it, its versions, its usage, then Revoke.
    @MainActor @ViewBuilder private var managed: some View {
        let live = TafView.halts(manages: manages, state: taf.state)
        if let pages, live {
            // Halting is a job of its own: its row opens its screen.
            HaltRow(model: pages.halt, name: taf.name, halted: halted)
        }
        if let pages, manages {
            VersionsLink(model: pages) { versionsOpen = true }
            // Its credits this period, and its runs, as the iPad's Usage row.
            PanelLink(action: { usageOpen = true }) {
                Label(words("usage.label"), systemImage: "chart.bar")
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.amberText)
            }
        }
        if live {
            if pages?.viewOnly == true {
                // A view-only session isn't offered Revoke, on every device alike (the iPad's TafDetailView.swift:468-473).
                Text(words("taf.revoke_needs_approver")).font(.system(size: 13)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let revoke = pages?.revokeCards {
                // A plain session call, as the iPad's: it only takes authority away, so no key is asked.
                Button(words("taf.revoke")) { confirmRevoke = true }
                    .buttonStyle(OutlineButtonStyle(color: Theme.no))
                    .alert(words("taf.revoke_title", ["taf": taf.name]), isPresented: $confirmRevoke) {
                        Button(words("taf.revoke_and_stop"), role: .destructive) {
                            Task {
                                do {
                                    try await revoke(taf.cards.map(\.id))
                                    revokeFailed = nil
                                } catch {
                                    revokeFailed = words("card.revoke_failed", ["why": NeedsYouModel.why(error)])
                                }
                            }
                        }
                        Button(words("common.cancel"), role: .cancel) {}
                    } message: { Text(words("taf.revoke_body")) }
                if let why = revokeFailed {
                    Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The Card tab's way into the versions, as the iPad's (TafDetailView.swift:440-448): tafs cloud's
/// title for them ("Changes to how it runs") and its summary, from the Setup, read here too.
private struct VersionsLink: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafPagesModel
    let open: () -> Void

    var body: some View {
        PanelLink(action: open) {
            VStack(alignment: .leading, spacing: 4) {
                Label(part?.title ?? words("version.changes_row"), systemImage: "square.stack.3d.up")
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.amberText)
                if let summary = part?.summary { Text(verbatim: summary).font(.system(size: 13)).foregroundColor(Theme.soft) }
            }
        }
        .task {
            // The iPad reads the Setup with the page; here, if its tab hasn't yet.
            if case .loading = model.setup { await model.loadSetup() }
        }
    }

    private var part: TafSetup.Part? {
        if case .loaded(let setup) = model.setup { return setup.versions }
        return nil
    }
}

/// A Setup or Card screen's way in, as the iPad's `PanelLink`: its label, and the caret that says
/// it opens, on a panel.
struct PanelLink<Content: View>: View {
    let action: () -> Void
    let label: () -> Content

    init(action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Content) {
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            HStack {
                label()
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.soft)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A button for a change that is signed on the iPad, which this Mac can't sign yet: drawn as the
/// iPad's, in red, and a click shows the line for an approval made on another device
/// (`approval.device_can_not_approve_approve`). Nothing is sent.
struct ApprovalElsewhereButton: View {
    @Environment(\.words) private var words
    let title: String
    @State private var said = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(title) { said = true }
                .buttonStyle(OutlineButtonStyle(color: Theme.no))
            if said {
                // This Mac has no security key: what one is, then where to approve (tafs#1718).
                Text(words("approval.security_key.none_paired")).font(.system(size: 13)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
                Text(words("approval.device_can_not_approve_approve")).font(.system(size: 13)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Each thing a Card lets the taf do, and what happens outside it, with its limits as the iPad's
/// `CardRule.summary`.
struct CardRulesPanel: View {
    @Environment(\.words) private var words
    let card: TafCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(card.rules.enumerated()), id: \.offset) { _, rule in row(rule) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }

    private func row(_ rule: TafCard.Rule) -> some View {
        let summary = rule.summary(words)
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: rule.label).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                if let outside = outsideWords(rule.outside) { Text(outside).font(.system(size: 12)).foregroundColor(Theme.soft) }
            }
            Spacer()
            // Its limits as the iPad's summary: held or refused above them.
            if !summary.isEmpty {
                Text(verbatim: summary).font(Theme.mono(12)).foregroundColor(Theme.ink).multilineTextAlignment(.trailing)
            }
        }
    }

    /// What happens outside a rule, in the shared words; nothing for a word tafs cloud may
    /// send that this app doesn't know.
    private func outsideWords(_ outside: TafCard.Rule.Outside) -> String? {
        switch outside {
        case .refuse: return words("card.outside_refused")
        case .hold: return words("card.outside_held")
        case .unknown: return nil
        }
    }
}

/// Card › How this is counted, as the iPad's `CountedView`: for each tool the Card covers, KIFF's
/// lines for how it's counted, under the tool's title. The app adds no words of its own.
struct CountedView: View {
    @Environment(\.words) private var words
    let card: TafCard
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(words("card.how_counted")).font(Theme.display(22)).foregroundColor(Theme.ink)
                Spacer()
                Button(words("common.done"), action: close).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(card.counted, id: \.tool) { tool($0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 480, height: 440)
        .background(Theme.background)
        .accessibilityIdentifier("counted.\(card.title)")
    }

    private func tool(_ tool: TafCard.Counted) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: tool.title)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(tool.lines.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line).font(.system(size: 15)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel))
        }
    }
}

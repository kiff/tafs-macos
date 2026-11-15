import SwiftUI

/// A taf's Activity and Setup, read from tafs cloud when their tab opens. Both only read.
@MainActor
final class TafPagesModel: ObservableObject {
    enum State<Page: Equatable>: Equatable {
        case loading
        case loaded(Page)
        case unread(why: String)
    }

    @Published private(set) var activity: State<TafActivity> = .loading
    @Published private(set) var setup: State<TafSetup> = .loading
    /// The Activity filter shown, as tafs cloud names it.
    @Published private(set) var filter = "all"
    /// tafs cloud's own query for the Activity shown, from an app in the Setup; nil for a filter.
    @Published private(set) var query: String?

    private let cloud: CloudClient
    let taf: String
    /// The taf's halt, from its Setup.
    let halt: HaltModel
    private var asked = 0

    init(cloud: CloudClient, taf: String) {
        self.cloud = cloud
        self.taf = taf
        halt = HaltModel(cloud: cloud, taf: taf)
    }

    /// Reads the Activity, for a filter tafs cloud offered. A slower answer to an older filter is dropped.
    func loadActivity(filter: String? = nil) async {
        if let filter {
            self.filter = filter
            query = nil
        }
        asked += 1
        let mine = asked
        do {
            let page = try await cloud.activity(of: taf, filter: self.filter, query: query)
            guard mine == asked else { return }
            activity = .loaded(page)
        } catch {
            guard mine == asked else { return }
            activity = .unread(why: NeedsYouModel.why(error))
        }
    }

    /// The next page of the same filter, once the list's end is shown, as the iPad does. A
    /// page asked for before the filter changed is dropped.
    func loadMore() async {
        guard case .loaded(var page) = activity, let cursor = page.nextCursor else { return }
        let mine = asked
        do {
            let next = try await cloud.activity(of: taf, filter: filter, query: query, cursor: cursor)
            guard mine == asked, case .loaded(let shown) = activity, shown.nextCursor == cursor else { return }
            page.append(next)
            activity = .loaded(page)
        } catch {
            // The calls shown stay; the end is tried again when it shows again.
        }
    }

    /// The Activity of one app's calls, from its sheet in the Setup, as the iPad opens it.
    func show(activityQuery: String) {
        query = activityQuery
        filter = "all"
        activity = .loading
    }

    func loadSetup() async {
        do { setup = .loaded(try await cloud.setup(of: taf)) } catch { setup = .unread(why: NeedsYouModel.why(error)) }
    }
}

/// A taf's Activity, as the iPad's: its Card's line, tafs cloud's filters as pills, then its
/// calls by day, each drawn as sent.
struct TafActivityTab: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafPagesModel
    let taf: Home.Taf
    /// Whether this person manages the taf: Coach's fix is theirs.
    var manages = false
    /// Coach with tafs cloud's words in its box; Plan & usage.
    var askCoach: (String) -> Void = { _ in }
    var openUsage: () -> Void = {}
    /// Opens the Card tab, from the Card's line.
    let openCard: () -> Void

    var body: some View {
        ScrollView {
            // Lazy, so the list's end shows only when it's scrolled to, and the next page is
            // asked for then.
            LazyVStack(alignment: .leading, spacing: 14) {
                // Its health, as tafs cloud reads it, over its work, as the iPad's `WorkPanel`.
                if let health = taf.health, health.needsAttention { healthLines(health) }
                if let card = taf.cards.first { cardLine(card) }
                switch model.activity {
                case .loading:
                    ProgressView().controlSize(.small)
                case .unread(let why):
                    Text(words("home.couldnt_load_from_kiff")).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.no)
                    Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.soft)
                    Button(words("common.try_again")) { Task { await model.loadActivity() } }
                case .loaded(let page):
                    ForEach(page.exceptions) { CardUnitPanel(exception: $0) }
                    if !page.filters.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(page.filters) { choice in
                                Chip(title: choice.title, chosen: model.filter == choice.id) { Task { await model.loadActivity(filter: choice.id) } }
                            }
                        }
                    }
                    ForEach(page.groups) { group in
                        if !group.title.isEmpty {
                            Text(verbatim: group.title.uppercased()).font(Theme.mono(11)).tracking(1.5).foregroundColor(Theme.soft).padding(.top, 6)
                        }
                        ForEach(group.entries) { row($0) }
                    }
                    if let cursor = page.nextCursor {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                            .task(id: cursor) { await model.loadMore() }
                    }
                    if let end = page.endWords {
                        Text(verbatim: end).font(.system(size: 13)).foregroundColor(Theme.dim).frame(maxWidth: .infinity).padding(.top, 6)
                    }
                }
            }
            .padding(.bottom, Look.inset)
        }
        .task { await model.loadActivity() }
    }

    /// A taf that isn't healthy, as the iPad's `HealthLines`: each line, amber when at risk and
    /// red when failing, with the fixes tafs cloud decided for it. Coach's fix opens Coach with
    /// tafs cloud's words in the box, nothing sent, for whoever manages the taf; the credits fix
    /// opens Plan & usage. A fix of a kind the app doesn't know is no button.
    private func healthLines(_ health: Home.Taf.Health) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(health.lines.enumerated()), id: \.offset) { index, line in
                Text(verbatim: line).font(.system(size: 14)).foregroundColor(health.failing ? Theme.no : Theme.amberText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(health.fixes(for: index).enumerated()), id: \.offset) { _, fix in
                    if let act = action(fix) {
                        Button(action: act) { Text(verbatim: fix.words).padding(.horizontal, 16) }
                            .buttonStyle(OutlineButtonStyle())
                            .fixedSize()
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
    }

    /// What a fix does here; nil draws no button.
    private func action(_ fix: Home.Taf.Health.Fix) -> (() -> Void)? {
        switch fix.kind {
        case "coach":
            guard let say = fix.say, !say.isEmpty, manages else { return nil }
            return { askCoach(say) }
        case "credits":
            return openUsage
        default:
            return nil
        }
    }

    /// The taf's first Card in one line: what is left, and the Card's title. It opens the Card.
    private func cardLine(_ card: TafCard) -> some View {
        Button(action: openCard) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 8).fill(Theme.tafColor(taf.color)).frame(width: 48, height: 32)
                    .overlay(Image(systemName: "creditcard").font(.system(size: 14, weight: .semibold)).foregroundColor(.white))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if let left = card.line(words) { Text(verbatim: left).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink) }
                    Text(verbatim: card.title).font(.system(size: 13)).foregroundColor(Theme.soft)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.soft)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One call: its kind's dot, tafs cloud's title and detail, and its time.
    private func row(_ entry: TafActivity.Entry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle().fill(color(entry.tone)).frame(width: 9, height: 9).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: entry.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                if let detail = entry.detail { Text(verbatim: detail).font(.system(size: 14)).foregroundColor(Theme.soft) }
            }
            Spacer()
            // Its time, and under it its amount in tafs cloud's words, as the iPad's row.
            VStack(alignment: .trailing, spacing: 3) {
                if let time = entry.time { Text(verbatim: time).font(Theme.mono(12)).foregroundColor(Theme.soft) }
                if let amount = entry.amountText { Text(verbatim: amount).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.ink) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        .accessibilityElement(children: .combine)
    }

    /// The iPad's kind colours (`TafActivity.Entry.tone`).
    private func color(_ tone: TafActivity.Entry.Tone) -> Color {
        switch tone {
        case .ok: return Theme.ok
        case .amber: return Theme.amber
        case .no: return Theme.no
        }
    }
}

/// A taf's Setup, as tafs cloud sends it: what waits on its Card first, then each part with
/// its line. It only reads here: changing a part is done with Coach, with its approval.
struct TafSetupTab: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafPagesModel
    /// Opens the taf's Activity with tafs cloud's query for one app's calls.
    var openActivity: (String) -> Void = { _ in }
    /// The app whose sheet is open.
    @State private var chosen: TafSetup.Node?
    /// The taf's name, for its halt.
    var tafName: String? = nil
    /// Whether its halt is offered: to whoever manages the taf, as KIFF says, and not for a
    /// taf whose Card is no longer active, as the iPad's `TafDetailView`.
    var halts = false
    /// Reads the list again after a halt tafs cloud answered.
    var halted: () async -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch model.setup {
                case .loading:
                    ProgressView().controlSize(.small)
                case .unread(let why):
                    Text(words("home.couldnt_load_from_kiff")).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.no)
                    Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.soft)
                    Button(words("common.try_again")) { Task { await model.loadSetup() } }
                case .loaded(let setup):
                    // Halting is a job of its own: its row opens its screen, for whoever manages the taf.
                    if halts { HaltRow(model: model.halt, name: tafName, halted: halted) }
                    ForEach(setup.exceptions) { CardUnitPanel(exception: $0) }
                    if let again = setup.connectAgain { connectAgain(again) }
                    if let workflow = setup.workflow { part(workflow) }
                    let nodes = TafSetup.nodes(setup.connections)
                    if !nodes.isEmpty {
                        // One row per app, as the iPad's `ConnectedToolsRing` has one node per app.
                        Eyebrow(text: words("connect.connected_tools")).padding(.top, 6)
                        ForEach(nodes) { node($0) }
                    }
                    if let error = setup.connectionsError {
                        // In red with Try again, as the iPad says it.
                        HStack(spacing: 10) {
                            Text(verbatim: error).font(.system(size: 13)).foregroundColor(Theme.no)
                            Button(words("common.try_again")) { Task { await model.loadSetup() } }
                                .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.amberText)
                        }
                        .padding(.horizontal, 4)
                    }
                    if let versions = setup.versions { part(versions) }
                    if let memory = setup.memory {
                        Eyebrow(text: words("taf.memory.title")).padding(.top, 6)
                        part(memory)
                    }
                }
            }
            .padding(.bottom, Look.inset)
        }
        .task { await model.loadSetup() }
        .sheet(item: $chosen) { node in
            ConnectedAppSheet(node: node, close: { chosen = nil }, openActivity: { query in
                chosen = nil
                openActivity(query)
            })
        }
    }

    /// An app, as the iPad's node: its name, and its actions in words, green while the taf uses
    /// it. It opens the app's sheet.
    private func node(_ node: TafSetup.Node) -> some View {
        Button { chosen = node } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: node.app.name).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                    if let actions = node.app.actionWords {
                        Text(verbatim: actions).font(.system(size: 13)).foregroundColor(node.app.running ? Theme.ok : Theme.soft)
                    }
                }
                Spacer()
                if let status = node.app.statusWords {
                    Text(verbatim: status).font(.system(size: 13, weight: .semibold)).foregroundColor(node.app.reconnect ? Theme.amberText : Theme.soft)
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.soft)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The taf's own sign-in expired: tafs cloud's words for it, edged in amber. Connecting again
    /// is a sign-in, done on the phone for now: no button here.
    private func connectAgain(_ again: TafSetup.ConnectAgain) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: again.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.amberText)
            if let words = again.words { Text(verbatim: words).font(.system(size: 14)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).stroke(Theme.amber.opacity(0.7)))
    }

    private func part(_ part: TafSetup.Part) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: part.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
            if let summary = part.summary { Text(verbatim: summary).font(.system(size: 14)).foregroundColor(Theme.soft) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
    }
}

/// A call refused for want of a limit in its unit: tafs cloud's title, words and history,
/// edged in amber. What to do about it is Coach's, with its approval: no button here.
struct CardUnitPanel: View {
    let exception: CardUnitException

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: exception.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
            if let words = exception.words { Text(verbatim: words).font(.system(size: 14)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true) }
            if let history = exception.history { Text(verbatim: history).font(.system(size: 12)).foregroundColor(Theme.soft) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).stroke(Theme.amber.opacity(0.7)))
    }
}

/// One app on the taf, as the iPad's `ConnectedAppSheet`: its status (amber when it must sign in
/// again), what it may do with each action's limits, its week, which opens the taf's Activity of
/// its calls, and the other sign-ins to the same app. Sign in again and Disconnect change what
/// the taf may do, so they come with approvals: none here.
struct ConnectedAppSheet: View {
    @Environment(\.words) private var words
    let node: TafSetup.Node
    let close: () -> Void
    let openActivity: (String) -> Void

    var body: some View {
        let app = node.app
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(verbatim: app.name).font(Theme.display(22)).foregroundColor(Theme.ink)
                Spacer()
                Button(words("common.done"), action: close).keyboardShortcut(.cancelAction)
            }
            if let status = app.statusWords {
                Text(verbatim: status).font(.system(size: 14)).foregroundColor(app.reconnect ? Theme.amberText : Theme.soft)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !app.actions.isEmpty {
                        Eyebrow(text: words("taf.app.what_it_may_do"))
                        ForEach(Array(app.actions.enumerated()), id: \.offset) { _, action in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: action.title).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink)
                                ForEach(Array(action.limits.enumerated()), id: \.offset) { _, line in
                                    Text(verbatim: line).font(.system(size: 13)).foregroundColor(Theme.soft)
                                }
                                if let steps = action.stepWords { Text(verbatim: steps).font(.system(size: 13)).foregroundColor(Theme.dim) }
                            }
                        }
                    }
                    // Its week: opens the taf's Activity of its calls; nothing to open with no actions.
                    if let stats = app.statsWords {
                        Button { if let query = app.activityQuery { openActivity(query) } } label: {
                            Text(verbatim: stats).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.amberText)
                        }
                        .buttonStyle(.plain)
                        .disabled(app.actions.isEmpty || app.activityQuery == nil)
                        .padding(.top, 4)
                    }
                    if !node.others.isEmpty {
                        Eyebrow(text: words("connect.other_connections")).padding(.top, 6)
                        ForEach(node.others) { other in
                            Text(verbatim: other.statusWords ?? other.name).font(.system(size: 14))
                                .foregroundColor(other.reconnect ? Theme.amberText : Theme.soft)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 480, height: 440)
        .background(Theme.background)
    }
}

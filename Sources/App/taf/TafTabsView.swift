import Combine
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
    /// Its versions, oldest first, once read, as the iPad's `versions[tafID]`: a read that fails
    /// keeps them, with why beside them.
    @Published private(set) var versionList: [TafVersions.Version]?
    /// A switch under way, as tafs cloud keeps it: the taf doesn't run until it ends.
    @Published private(set) var switching: TafVersions.Switching?
    /// Why the versions couldn't be read, or the switch wasn't cancelled.
    @Published private(set) var versionError: String?
    /// The Activity filter shown, as tafs cloud names it.
    @Published private(set) var filter = "all"
    /// tafs cloud's own query for the Activity shown, from an app in the Setup; nil for a filter.
    @Published private(set) var query: String?
    /// The runs it kept: the panel's first few (`false`), and all of them (`true`).
    @Published private(set) var runPages: [Bool: TafRuns.Pages] = [:]
    /// Run now, kept by taf for the whole app (`RunNowModel`), so it outlives this page.
    let runs: RunNowModel
    /// Run now is on its way: a second click sends nothing.
    var runInFlight: Bool { runs.inFlight.contains(taf) }
    /// tafs cloud's words when Run now started no run.
    var runNowWords: String? { runs.words[taf] }
    /// Why Run now didn't start a run, where the iPad says it in its error line.
    var runNotStarted: String? { runs.notStarted[taf] }
    private var following: AnyCancellable?

    private let cloud: CloudClient
    let taf: String
    /// The taf's halt, from its Setup.
    let halt: HaltModel
    /// The taf's dial, for Setup's Starts when and Results go to.
    let knob: TafKnobModel
    /// Its credits and runs this period, for the Card tab's Usage.
    let credits: TafCreditsModel
    /// What it remembers, for the Setup's See all.
    let memory: TafMemoryModel
    private var asked = 0

    /// This device's planque proof for the Setup read; nil reads without it.
    private let proof: () async -> String?

    init(cloud: CloudClient, taf: String, proof: @escaping () async -> String? = { nil },
         runs: RunNowModel? = nil) {
        self.cloud = cloud
        self.taf = taf
        self.proof = proof
        halt = HaltModel(cloud: cloud, taf: taf)
        knob = TafKnobModel(cloud: cloud, taf: taf)
        credits = TafCreditsModel(cloud: cloud, taf: taf)
        memory = TafMemoryModel(cloud: cloud, taf: taf)
        self.runs = runs ?? RunNowModel(cloud: cloud)
        // The page draws Run now from the app's model: it changes when that does.
        following = self.runs.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
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

    /// Reads the runs it kept, as the iPad's `loadRunPage`: three for the panel, twenty a page
    /// for all of them. Asked again with what was read, a 304 keeps it. `more` reads the next
    /// page; asked while a read is on its way, it waits for that one.
    func loadRunPage(all: Bool = false, more: Bool = false) async {
        var cache = runPages[all] ?? TafRuns.Pages()
        guard !cache.loading else {
            if more { cache.moreWhenReady = true; runPages[all] = cache }
            return
        }
        let cursor = more ? cache.pages.last?.nextCursor : nil
        if more && cursor == nil { return }
        cache.loading = true; cache.moreWhenReady = false; cache.error = nil; runPages[all] = cache
        do {
            let (page, tag) = try await cloud.runsPage(of: taf, cursor: cursor, etag: more ? nil : cache.etag, limit: TafRuns.limit(all: all))
            if let page { cache.pages = more ? cache.pages + [page] : [page] }
            if !more { cache.etag = tag }
        } catch { cache.error = NeedsYouModel.why(error) }
        let follow = cache.error == nil && runPages[all]?.moreWhenReady == true
        cache.loading = false; cache.moreWhenReady = false; runPages[all] = cache
        if follow { await loadRunPage(all: all, more: true) }
    }

    /// Runs the taf now, as the iPad's `runNow`: once at a time; tafs cloud's words when it
    /// started no run; the runs read again when it did. Waiting for credits says tafs cloud's
    /// words; any other refusal says the run didn't start, and why.
    @discardableResult
    func runNow(words: Words) async -> String? {
        await runs.runNow(taf, words: words)
    }

    /// Reads the versions, as the iPad's `loadVersions` (AppModel.swift:3906-3922): what was read
    /// stays when a later read fails, with tafs cloud's why under it.
    func loadVersions() async {
        do {
            let state = try await cloud.versions(of: taf)
            versionList = state.versions
            switching = state.switching
            versionError = nil
        } catch {
            versionError = Words.app("version.not_loaded", ["why": NeedsYouModel.why(error)])
        }
    }

    /// Cancels a switch under way, then reads the versions again, as the iPad's `cancelSwitch`
    /// (AppModel.swift:4145-4153). It gives no authority back, so it isn't signed.
    func cancelSwitch() async {
        do { try await cloud.cancelSwitch(of: taf) } catch {
            versionError = Words.app("version.switch_not_cancelled", ["why": NeedsYouModel.why(error)])
        }
        await loadVersions()
    }

    /// Reads the Setup, as the iPad's `loadTafSetup` (`AppModel.swift:138-149`): with this
    /// device's planque proof when one can be made, else without it, and tafs cloud then says
    /// where the connected apps would be.
    func loadSetup() async {
        do {
            let proof = await proof()
            setup = .loaded(try await cloud.setup(of: taf, proof: proof))
        } catch { setup = .unread(why: NeedsYouModel.why(error)) }
    }
}

/// A taf's Activity, as the iPad's `TafActivityList`: what needs the person, its work and runs,
/// tafs cloud's filters as pills, then its calls by day, each drawn as sent. Its Cards are beside
/// it, in the page's side column (`TafView`).
struct TafActivityTab: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafPagesModel
    let taf: Home.Taf
    /// Plan & usage, from the credits fix.
    var openUsage: () -> Void = {}
    /// The taf's doors, for whoever manages it: their knocks come first, as the iPad's
    /// `TafActivityList.parts`; nil for anyone else.
    var doors: DoorsModel? = nil
    /// tafs cloud offers doors here: only then are they read.
    var doorsOffered = false

    var body: some View {
        ScrollView {
            // Lazy, so the list's end shows only when it's scrolled to, and the next page is
            // asked for then.
            LazyVStack(alignment: .leading, spacing: 14) {
                if let doors { TafKnocksPanel(taf: taf, doors: doors, offered: doorsOffered) }
                // As the iPad's `TafActivityList.parts`: what waits on the Card for want of a unit,
                // then its work, under which its health sits (`WorkPanel`).
                if case .loaded(let page) = model.activity { ForEach(page.exceptions) { CardUnitPanel(exception: $0) } }
                if let health = taf.health, health.needsAttention { workPanel(health) }
                // Then its runs, and the runs it kept, as the iPad's `TafActivityList.parts`.
                RunsPanel(model: model, taf: taf)
                RetainedRuns(model: model)
                switch model.activity {
                case .loading:
                    ProgressView().controlSize(.small)
                case .unread(let why):
                    Text(words("home.couldnt_load_from_kiff")).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.no)
                    Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.soft)
                    Button(words("common.try_again")) { Task { await model.loadActivity() } }
                case .loaded(let page):
                    if !page.filters.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(page.filters) { choice in
                                Chip(title: choice.title, chosen: model.filter == choice.id) { Task { await model.loadActivity(filter: choice.id) } }
                            }
                        }
                    }
                    ForEach(page.groups) { group in
                        // A day's title as the iPad's: "Today", soft, never in capitals.
                        if !group.title.isEmpty {
                            Text(verbatim: group.title).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.dim).padding(.top, 6)
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

    /// Its work, as the iPad's `WorkPanel` (TafDetailView.swift:564-612): "Its work", then its
    /// health as Home read it (`HealthLines`). The rest of the panel comes with `GET …/work`.
    private func workPanel(_ health: Home.Taf.Health) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: words("taf.its_work"))
            healthLines(health)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
    }

    /// A taf that isn't healthy, as the iPad's `HealthLines`: each line, amber when at risk and
    /// red when failing, with the fixes tafs cloud decided for it. The credits fix opens Plan &
    /// usage. A fix of a kind the app doesn't know is no button.
    private func healthLines(_ health: Home.Taf.Health) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(health.lines.enumerated()), id: \.offset) { index, line in
                Text(verbatim: line).font(.system(size: 14)).foregroundColor(health.failing ? Theme.no : Theme.amberText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(health.fixes(for: index).enumerated()), id: \.offset) { _, fix in
                    if let act = Self.action(fix, openUsage: openUsage) {
                        Button(action: act) { Text(verbatim: fix.words).padding(.horizontal, 16) }
                            .buttonStyle(OutlineButtonStyle())
                            .fixedSize()
                            .accessibilityIdentifier("taf.health.fix.\(fix.kind)")
                    }
                }
            }
        }
        .accessibilityIdentifier("taf.health")
    }

    /// What a fix does here, as `HealthLines.action`; nil draws no button.
    static func action(_ fix: Home.Taf.Health.Fix, openUsage: @escaping () -> Void) -> (() -> Void)? {
        switch fix.kind {
        case "coach":
            // The iPad's improves the taf in Coach mode (`askCoachAbout`): it comes with Coach
            // mode, and until then no button.
            return nil
        case "credits":
            return openUsage
        default:
            return nil
        }
    }

    /// One call, as the iPad's `SourceActivityRow` (TafPresentationViews.swift:328-363): a plain
    /// row, not boxed: tafs cloud's title and detail, and its time with its amount under it.
    private func row(_ entry: TafActivity.Entry) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: entry.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                if let detail = entry.detail { Text(verbatim: detail).font(.system(size: 13)).foregroundColor(Theme.soft) }
            }
            Spacer()
            VStack(alignment: .trailing) {
                if let time = entry.time { Text(verbatim: time).font(.system(size: 12)).foregroundColor(Theme.dim) }
                if let amount = entry.amountText { Text(verbatim: amount).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.ink) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

/// A taf's Setup, in the iPad's order (`TafDetailView.swift:305-358`): what waits on its Card and
/// its own Connect again first, then the job, Starts when, its connected apps as the iPad's ring
/// with its workflow inside, Results go to, what it remembers, and removing it. Its halt is on the
/// Card tab, as on the iPad.
struct TafSetupTab: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafPagesModel
    /// Opens the taf's Activity with tafs cloud's query for one app's calls.
    var openActivity: (String) -> Void = { _ in }
    /// Reads the list again after a pause or a change of where its results go.
    var halted: () async -> Void = {}
    /// The taf's doors, for whoever manages it; nil for anyone else. On the iPad they are in
    /// Setup › Starts when; here they stay at the top of the Setup until Starts when has them.
    var doors: DoorsModel? = nil
    /// The taf, for the job, Starts when and Results go to; nil leaves them out.
    var taf: Home.Taf? = nil
    /// Whether this person manages the taf, as KIFF says: changing what starts it and where
    /// its results go is theirs.
    var manages = false
    /// Who is signed in: the account's time zone, and their email for Email me.
    var me: Me? = nil
    /// This person's sign-in email: their own key reads "You".
    var myEmail: String? = nil
    /// Coach on this taf, a new conversation; nil draws no Improve in Coach.
    var improveInCoach: (() -> Void)? = nil
    /// Connect apps, from the ring's +; nil draws no +.
    var openConnect: (() -> Void)? = nil
    @State private var startsOpen = false
    @State private var resultsOpen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                first
                if let taf {
                    jobPanel(taf)
                    PanelLink(action: { startsOpen = true }) { linkLabel(words("setup.starts_when"), "clock") }
                    ConnectedToolsRing(model: model, taf: taf, manages: manages, openActivity: openActivity,
                                       openConnect: openConnect, improveInCoach: improveInCoach)
                    PanelLink(action: { resultsOpen = true }) { linkLabel(words("setup.results_go_to"), "paperplane") }
                }
                MemorySummaryPanel(model: model)
                if manages {
                    // Removing a taf is signed on the iPad (`removeTaf`), which this Mac can't do:
                    // as another device's Sign out, no button, the shared line in its place.
                    Text(words("approval.device_can_not_approve_approve")).font(.system(size: 13)).foregroundColor(Theme.soft)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("setup.remove")
                }
            }
            .padding(.bottom, Look.inset)
        }
        .task { await model.loadSetup() }
        // A Home read after a change brings the taf's own record: it, not the change's answer, is
        // the one drawn from then on, as the iPad's `cloudTafs` takes each newer read.
        .onChange(of: taf?.status) { _ in model.knob.homeRead() }
        .onChange(of: taf?.results) { _ in model.knob.homeRead() }
        .sheet(isPresented: $startsOpen) {
            if let taf {
                StartsWhenView(model: model.knob, taf: taf, manages: manages, timeZone: me?.timeZone, refreshed: halted) { startsOpen = false }
                    .environment(\.words, words)
            }
        }
        .sheet(isPresented: $resultsOpen) {
            if let taf {
                ResultsGoToView(model: model.knob, taf: taf, manages: manages, email: me?.email, refreshed: halted) { resultsOpen = false }
                    .environment(\.words, words)
            }
        }
    }

    /// The taf's doors, then what waits on its Card for want of a unit, and its own Connect again.
    @ViewBuilder private var first: some View {
        if let doors, let taf { DoorsListPanel(taf: taf, doors: doors, myEmail: myEmail) }
        if case .loaded(let setup) = model.setup {
            ForEach(setup.exceptions) { CardUnitPanel(exception: $0) }
            if let again = setup.connectAgain { connectAgain(again) }
        }
    }

    /// THE JOB, as the iPad's: its job in words, and Improve in Coach for whoever may.
    private func jobPanel(_ taf: Home.Taf) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: words("setup.job"))
            Text(verbatim: taf.job(words)).font(.system(size: 15)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
            if let improveInCoach {
                Button(words("setup.improve_in_coach"), action: improveInCoach)
                    .buttonStyle(.plain).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.amberText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
    }

    /// A Setup screen's way in, as the iPad's `PanelLink` label: its mark and name in amber.
    private func linkLabel(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.amberText)
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
}

/// WHAT IT REMEMBERS, as the iPad's `MemorySummaryPanel` (TafPresentationViews.swift:485-501): tafs
/// cloud's count of its notes ("3 notes"), the latest, and See all, which opens every note.
struct MemorySummaryPanel: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafPagesModel
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: words("taf.memory.title"))
            switch model.setup {
            case .loaded(let setup):
                if let memory = setup.memory { summary(memory) }
            case .loading:
                ProgressView().controlSize(.small)
            case .unread:
                EmptyView()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        // Notes forgotten there change the count here: the Setup is read again, as the iPad's.
        .sheet(isPresented: $open, onDismiss: { Task { await model.loadSetup() } }) {
            TafMemoryView(model: model.memory) { open = false }.environment(\.words, words)
        }
    }

    private func summary(_ memory: TafSetup.Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: memory.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
            if let latest = memory.summary { Text(verbatim: latest).font(.system(size: 14)).foregroundColor(Theme.soft).lineLimit(2) }
            Button(words("taf.memory.see_all")) { open = true }
                .buttonStyle(.plain).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.amberText)
        }
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

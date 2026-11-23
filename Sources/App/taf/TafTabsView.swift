import Combine
import SwiftUI

/// A taf's Activity and Setup, read from tafs cloud when their tab opens. Both only read.
@MainActor
final class TafPagesModel: ObservableObject {
    /// A version's trial (`Trials`): KIFF's client, for reading the draft and ending a trial (the device key's call), and
    /// the security key's approval of a draft confirm, set by the window. Nil leaves trials to the phone.
    var account: AccountClient?
    var confirmWithKey: ((KeyAct, String) async throws -> Data)?
    /// The taf's name, for the trial's prompts.
    var tafName = ""
    @Published private(set) var trial: Trials.Open?
    @Published private(set) var trialError: String?
    @Published private(set) var trialBusy = false
    /// The trial's own chat, made when a trial is open.
    @Published private(set) var trialChat: CoachModel?
    /// Revokes the taf's Cards in KIFF, as the iPad's `revoke`: set by the window; nil draws no Revoke.
    var revokeCards: (([String]) async throws -> Void)?
    /// Whether this Mac's session is view-only (KIFF's `view`): Revoke isn't offered, as on the iPad.
    var viewOnly = false
    /// Remove for good on this Mac's security key (`TafRemoval`), set by the window; nil says to approve elsewhere.
    var removeForGood: (() async -> String?)?
    /// What the removal takes with it, in tafs cloud's words, read before the key is asked.
    var removalPreview: (() async -> String?)?
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
    /// Where its work stands, once read, as the iPad's `works[tafID]`: a read that fails keeps it.
    @Published private(set) var work: TafWork?
    /// What went wrong under the work, as the iPad's `workErrors[tafID]`.
    @Published private(set) var workFailure: TafWork.Failure?
    /// The runs whose Send again is on its way: a second click sends nothing.
    @Published private(set) var sendingAgain: Set<String> = []
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

    /// Whether this Mac starts and installs trials: with KIFF's client and the security key.
    var startsTrials: Bool { account != nil && confirmWithKey != nil }

    /// The taf's open trial, as tafs cloud keeps it; its chat is made once one is open.
    func loadTrial() async {
        do {
            setTrial(try await cloud.openTrial(of: taf))
        } catch is CancellationError {
        } catch {
            trialError = Words.app("version.trial.not_read", ["why": NeedsYouModel.why(error)])
        }
    }

    private func setTrial(_ open: Trials.Open?) {
        trial = open
        if let open {
            if trialChat == nil {
                let chat = CoachModel(cloud: cloud, taf: Coach(id: taf, name: Words.app("version.trial.chat_name", ["taf": tafName, "n": String(open.n)])))
                chat.trial = true
                trialChat = chat
            }
        } else {
            trialChat = nil
        }
    }

    /// The draft a trial of version `n` would confirm, read by this Mac itself, before anything is signed.
    func trialDraft(version n: Int) async throws -> AccountClient.Draft {
        guard let account else { throw KIFFError.unreadable }
        return try await account.draft(id: try await cloud.trialDraft(of: taf, version: n))
    }

    /// Starts trying version `n`, as the iPad's `startTrying`; true once it's open. `shownDraft` is the draft version the
    /// person read: changed since, nothing is signed.
    func startTrial(version n: Int, shownDraft: String) async -> Bool {
        guard let account, let confirm = confirmWithKey, !trialBusy else { return false }
        trialBusy = true
        defer { trialBusy = false }
        trialError = nil
        let cloud = cloud, taf = taf, prompt = Words.app("version.trial.prompt", ["n": String(n), "taf": tafName])
        let done = await Trials.start(n: n, shownDraft: shownDraft, words: Words.app, makeDraft: { try await cloud.trialDraft(of: taf, version: n) },
                                      readDraft: { try await account.draft(id: $0) }, confirm: { try await confirm($0, prompt) },
                                      open: { try await cloud.openTrial(of: taf, version: n, draft: $0) })
        switch done {
        case .started(let open):
            setTrial(open)
            await loadVersions()
            return true
        case .changed: trialError = Words.app("version.trial.changed")
        case .notATrial(let status): trialError = Trials.notATrialLine(status, words: Words.app)
        case .closed: break
        case .failed(let why): trialError = why
        }
        return false
    }

    /// Install: the trial's draft confirmed in KIFF on the key (if it isn't yet), then tafs cloud makes it live.
    func installTrial() async -> Bool {
        guard let account, let confirm = confirmWithKey, let open = trial, !trialBusy else { return false }
        trialBusy = true
        defer { trialBusy = false }
        trialError = nil
        do {
            let draft = try await account.draft(id: open.draft)
            if !draft.confirmed {
                _ = try await confirm(.confirmDraft(id: draft.id, version: draft.version),
                                      Words.app("version.prompt.install", ["n": String(open.n), "taf": tafName]))
            }
            _ = try await cloud.installTrial(of: taf)
        } catch is CancellationError {
            return false
        } catch {
            trialError = Words.app("version.trial.install_unfinished", ["n": String(open.n), "why": NeedsYouModel.why(error)])
            return false
        }
        setTrial(nil)
        await loadVersions()
        return true
    }

    /// Go back: KIFF ends the trial Card (the device key's call: it takes authority away), then tafs cloud ends the trial.
    func goBackFromTrial() async -> Bool {
        guard let account, let open = trial, !trialBusy else { return false }
        trialBusy = true
        defer { trialBusy = false }
        trialError = nil
        do {
            try await account.endTrial(draft: open.draft)
            _ = try await cloud.endTrial(of: taf)
        } catch {
            trialError = Words.app("version.trial.not_ended", ["why": NeedsYouModel.why(error)])
            return false
        }
        setTrial(nil)
        await loadVersions()
        return true
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

    /// Reads where its work stands, as the iPad's `loadWork`.
    func loadWork() async {
        do {
            work = try await cloud.work(of: taf)
            workFailure = nil
        } catch is CancellationError {
        } catch {
            workFailure = .notRead(why: NeedsYouModel.why(error))
        }
    }

    /// Answer within: the owner's promise, whole hours or nil to clear it, as the iPad's `setPromise`. tafs cloud
    /// checks and keeps it, so the work is read again after, whatever came of it.
    func setPromise(hours: Int?) async {
        workFailure = nil
        var failed: TafWork.Failure?
        do { try await cloud.setPromise(of: taf, hours: hours) } catch { failed = .promiseNotSet(why: NeedsYouModel.why(error)) }
        await loadWork()
        // Said after the work is read again, so the read doesn't clear it.
        if let failed { workFailure = failed }
    }

    /// Send again, as the iPad's `sendAgain`: one run's delivery once more. The work is read again after.
    func sendAgain(run: String, place: String) async {
        guard sendingAgain.insert(run).inserted else { return }
        workFailure = nil
        var failed: TafWork.Failure?
        do { try await cloud.sendAgain(of: taf, run: run, place: place) } catch { failed = .notSentAgain(why: NeedsYouModel.why(error)) }
        sendingAgain.remove(run)
        await loadWork()
        if let failed { workFailure = failed }
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
    /// Whoever manages the taf sets Answer within and sends a reply again.
    var manages = false
    /// Coach on this taf with these words in its box, nothing sent; nil for someone who may not use Coach on it.
    var askCoach: ((String) -> Void)? = nil
    /// Connect apps, where an app is connected again.
    var openConnect: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            // Lazy, so the list's end shows only when it's scrolled to, and the next page is
            // asked for then.
            LazyVStack(alignment: .leading, spacing: 14) {
                if let doors { TafKnocksPanel(taf: taf, doors: doors, offered: doorsOffered) }
                // As the iPad's `TafActivityList.parts`: what waits on the Card for want of a unit,
                // then its work, under which its health sits (`WorkPanel`).
                if case .loaded(let page) = model.activity { ForEach(page.exceptions) { CardUnitPanel(exception: $0) } }
                TafWorkPanel(model: model, homeHealth: taf.health, manages: manages, openUsage: openUsage)
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
                if let next = entry.next, !next.words.trimmingCharacters(in: .whitespaces).isEmpty { nextStep(next, of: entry) }
            }
            Spacer()
            VStack(alignment: .trailing) {
                if let time = entry.time { Text(verbatim: time).font(.system(size: 12)).foregroundColor(Theme.dim) }
                if let amount = entry.amountText { Text(verbatim: amount).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.ink) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
    }

    /// A not-done call's next step, as the iPad's `NextStepRow`: Connect apps, or Ask Coach (Coach on this taf, its first
    /// message written in, nothing sent), as tafs cloud says. Only someone who manages the taf gets a button, and Ask Coach
    /// only someone who may use Coach on it; anyone else, and a kind this app doesn't know, reads the words alone.
    @ViewBuilder private func nextStep(_ next: TafActivity.Entry.NextStep, of entry: TafActivity.Entry) -> some View {
        let fallback = [entry.title, entry.detail].compactMap { $0 }.joined(separator: ": ")
        switch (manages, next.action(fallback: fallback)) {
        case (true, .askCoach(let message)) where askCoach != nil:
            Button(next.words) { askCoach?(message) }.buttonStyle(OutlineButtonStyle()).fixedSize()
                .accessibilityIdentifier("activity.next-step")
        case (true, .connectApps) where openConnect != nil:
            Button(next.words) { openConnect?() }.buttonStyle(OutlineButtonStyle()).fixedSize()
                .accessibilityIdentifier("activity.next-step")
        default:
            Text(verbatim: next.words).font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
        }
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
    /// The taf's doors, for whoever manages it, in Setup › Starts when as on the iPad; nil for
    /// anyone else.
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
                    // Remove for good, as the iPad draws it for whoever manages the taf (not behind its
                    // ApprovalGate). It's signed with the approval key there (`removeTaf`), which this
                    // Mac can't do: a click says to approve on another device and sends nothing.
                    if model.removeForGood != nil, let taf {
                        RemoveForGoodButton(model: model, name: taf.name).accessibilityIdentifier("setup.remove")
                    } else {
                        ApprovalElsewhereButton(title: words("setup.remove_for_good"))
                            .accessibilityIdentifier("setup.remove")
                    }
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
                StartsWhenView(model: model.knob, taf: taf, manages: manages, timeZone: me?.timeZone, refreshed: halted,
                               doors: doors, myEmail: myEmail, improveInCoach: improveInCoach) { startsOpen = false }
                    .environment(\.words, words)
            }
        }
        .sheet(isPresented: $resultsOpen) {
            if let taf {
                ResultsGoToView(model: model.knob, taf: taf, manages: manages, email: me?.email, refreshed: halted,
                                improveInCoach: improveInCoach) { resultsOpen = false }
                    .environment(\.words, words)
            }
        }
    }

    /// What waits on its Card for want of a unit, and its own Connect again.
    @ViewBuilder private var first: some View {
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

/// Remove for good on this Mac's security key, as the iPad's (TafDetailView.swift:153-158, `removeTaf`): confirmed first
/// with what goes with it in tafs cloud's words, then the key's sheet names it ("Remove {taf} for good"), then what
/// happened, in the iPad's words.
struct RemoveForGoodButton: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafPagesModel
    let name: String
    @State private var confirming = false
    @State private var goes: String?
    @State private var busy = false
    @State private var said: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(words("setup.remove_for_good")) {
                Task {
                    goes = await model.removalPreview?()
                    confirming = true
                }
            }
            .buttonStyle(OutlineButtonStyle(color: Theme.no))
            .disabled(busy)
            .alert(words("taf.remove_title", ["taf": name]), isPresented: $confirming) {
                Button(words("taf.remove.button"), role: .destructive) {
                    Task {
                        busy = true
                        said = await model.removeForGood?()
                        busy = false
                    }
                }
                Button(words("common.cancel"), role: .cancel) {}
            } message: { Text(TafRemoval.body(words, goes: goes)) }
            if let said {
                Text(verbatim: said).font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

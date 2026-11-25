import SwiftUI

@MainActor
final class ConnectAppsModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded
        case unread(why: String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var apps: [Apps.App] = []
    @Published private(set) var canContinue = false
    /// tafs cloud's read stopped early: an app that isn't listed isn't absent.
    @Published private(set) var partial = false
    /// Coach can connect an app that isn't listed: the screen ends with "Not listed? Ask Coach".
    @Published private(set) var byKey = false
    @Published var search = ""
    /// The account's connections at planque, as this Mac last read them (`AppConnections`).
    @Published private(set) var grants: [AppConnections.Grant] = []
    /// Whether this Mac read them: without, a connected app's page says so, never an empty list.
    @Published private(set) var readsConnections = false
    /// The tafs removed since, as tafs cloud names them (`removed_tafs`).
    @Published private(set) var removedTafs: [Apps.RemovedTaf] = []
    /// The Record's newest calls, for each connection's last failed call (`AppConnections.lastFailure`), as the iPad
    /// reads its `record`, read when an app's connections open. One that can't be read is none: the line isn't drawn,
    /// nothing else changes.
    @Published private(set) var calls: [Record.Entry] = []
    /// The app whose connections are open ("Your {app} connections"), from its row's chevron.
    @Published var opened: Apps.App?

    /// Where ending a connection is done, as last worked out (`refreshRoute`): the rows draw
    /// this, so a redraw reads no Keychain and loads no Secure Enclave key. A click works it out
    /// again before anything is asked or sent.
    @Published private(set) var endRoute: ConnectionEnding.Route = .phone

    /// The connections being ended now, by the action's id (a grant's `|end`, or `clear`): its
    /// button waits until planque answered and the list was read again.
    @Published private(set) var ending: Set<String> = []
    /// What an ending said afterwards, by the action's id: planque's refusal, Clear's count, or
    /// that it wasn't done.
    @Published private(set) var notes: [String: String] = [:]

    private let cloud: CloudClient
    /// Where this Mac reads its connections; nil reads none.
    private let connections: ConnectionsSource?
    /// Touch ID, biometrics only, before this Mac ends a connection (`TouchIDOnly`).
    private let touchID: TouchIDOnly
    private var cursor: String?
    private var asked = 0
    /// The session this model was made for ended (`endSession`): no ending sends anything more.
    private var sessionEnded = false

    init(cloud: CloudClient, connections: ConnectionsSource? = nil, touchID: TouchIDOnly? = nil) {
        self.cloud = cloud
        self.connections = connections
        // Touch ID through this sign-in's ending key (`EndingKey`): none, and the phone.
        self.touchID = touchID ?? .system(session: cloud.session)
        refreshRoute()
    }

    /// The session is ending (a sign-out, or the window rebuilt for another session): an ending
    /// on its way, even one whose Touch ID prompt is still open, sends nothing more, as the
    /// iPad's `accountGeneration`.
    func endSession() { sessionEnded = true }

    /// Whether an ending may still send: the session it began in is still this one.
    private var current: Bool { !sessionEnded && !Task.isCancelled }

    /// Where ending a connection is done now (`ConnectionEnding.route`): here, with Touch ID, only
    /// on a Mac whose session key is in the Secure Enclave and that can check Touch ID now; else
    /// on the phone, and this Mac sends nothing. Reads the Keychain and loads the ending key, so
    /// it runs on appear, on the app coming back, after an ending and at each click, never per row.
    private var routeNow: ConnectionEnding.Route {
        guard let source = connections, source.end != nil else { return .phone }
        return ConnectionEnding.route(enclaveKey: source.enclaveKey, biometrics: touchID.available())
    }

    /// Works out `endRoute` again.
    func refreshRoute() {
        let route = routeNow
        if route != endRoute { endRoute = route }
    }

    /// Remove access, Cancel the request or Cancel the sign-in, as the iPad's
    /// `disconnect(grantID:)`: Touch ID with the question's title (`prompt`), then planque's
    /// `DELETE`, then the connections read again. A closed prompt says nothing; a refusal says
    /// `connect.not_disconnected`; a Mac that no longer ends one itself (no ending key now, or
    /// one the system invalidated) says to approve on the phone. `id` is the action's, for its note.
    func disconnect(_ grantID: String, prompt: String, id: String) async {
        guard !ending.contains(id), !sessionEnded else { return }
        refreshRoute()
        guard endRoute == .touchID, let source = connections, let end = source.end else {
            notes[id] = Words.app(ConnectionEnding.phoneLine)
            return
        }
        ending.insert(id)
        notes[id] = nil
        defer {
            ending.remove(id)
            refreshRoute()
        }
        let outcome = await ConnectionEnding.end([grantID], tenant: source.tenant, prompt: prompt, confirm: touchID.confirm, delete: end,
                                                 current: { [weak self] in self?.current ?? false }, Words.app)
        if outcome.stopped { return }
        if !outcome.unconfirmed { await readAgain() }
        notes[id] = ConnectionEnding.disconnectNote(outcome, Words.app)
    }

    /// Clear, as the iPad's `clearRemovedConnections`: of `ids`, only those tafs cloud lists as a
    /// removed taf's with no live Card using them; one Touch ID for all, then planque's `DELETE`
    /// for each, then the connections read again and how it went.
    func clear(_ ids: [String]) async {
        let id = "clear"
        guard !ending.contains(id), !sessionEnded else { return }
        refreshRoute()
        guard endRoute == .touchID, let source = connections, let end = source.end else {
            notes[id] = Words.app(ConnectionEnding.phoneLine)
            return
        }
        let plan = ConnectionEnding.clearPlan(ids, listed: AppConnections.removedListed(removedTafs))
        guard !plan.ending.isEmpty || !plan.keptFor.isEmpty else { return }
        guard !plan.ending.isEmpty else {
            notes[id] = ConnectionEnding.cleared(done: 0, kept: plan.keptFor.count, keptFor: plan.keptFor.flatMap { $0 }, left: 0, Words.app)
            return
        }
        ending.insert(id)
        notes[id] = nil
        defer {
            ending.remove(id)
            refreshRoute()
        }
        let prompt = Words.app.count("connect.clear_removed.title", plan.ending.count)
        let outcome = await ConnectionEnding.end(plan.ending, tenant: source.tenant, prompt: prompt, confirm: touchID.confirm, delete: end,
                                                 current: { [weak self] in self?.current ?? false }, Words.app)
        if outcome.stopped { return }
        if !outcome.unconfirmed { await readAgain() }
        notes[id] = ConnectionEnding.clearNote(outcome, ending: plan.ending.count, keptFor: plan.keptFor, Words.app)
    }

    /// The connections and the removed tafs read again after an ending, as the iPad's
    /// `refreshConnections` and `loadConnectApps`.
    private func readAgain() async {
        if !search.isEmpty { await readConnections() }
        await load()
    }

    /// The Record's first page, read only, when an app's connections open (`AppConnectionsView`): the catalog's own
    /// reads stay as they are.
    func readCalls() async {
        do { calls = try await cloud.record().entries } catch is CancellationError {} catch { calls = [] }
    }

    var yours: [Apps.App] { apps.filter(\.isYours) }
    var discover: [Apps.App] { apps.filter { !$0.isYours } }

    /// Searches from the first page. A slower answer to an older search is dropped.
    func load() async {
        asked += 1
        let mine = asked
        let q = search
        refreshRoute()
        // The account's connections too, as the iPad's `loadConnectApps`, so a connected app
        // lists each one.
        if q.isEmpty { await readConnections() }
        do {
            // This Mac's signed read with it, as the iPad sends it: tafs cloud then names the
            // removed tafs' connections. A fresh one each time: planque takes each once.
            let source = connections
            let proof = await source?.proof()
            let page = try await cloud.apps(q, proof: proof)
            guard mine == asked else { return }
            apps = page.apps
            byKey = false
            removedTafs = page.removedTafs
            show(page)
        } catch {
            guard mine == asked else { return }
            state = .unread(why: NeedsYouModel.why(error))
        }
    }

    /// The next page of the same search. A row already listed isn't listed twice.
    func more() async {
        guard let cursor else { return }
        let mine = asked
        let q = search
        do {
            let source = connections
            let proof = await source?.proof()
            let page = try await cloud.apps(q, cursor: cursor, proof: proof)
            guard mine == asked else { return }
            let listed = Set(apps.map(\.entry))
            apps += page.apps.filter { !listed.contains($0.entry) }
            show(page)
        } catch {
            guard mine == asked else { return }
            state = .unread(why: NeedsYouModel.why(error))
        }
    }

    /// Reads the account's connections from planque. One that can't be read leaves none, and the
    /// page says this Mac doesn't read them.
    func readConnections() async {
        guard let source = connections else { return }
        do {
            let read = try await source.grants()
            grants = read
            readsConnections = true
        } catch {
            grants = []
            readsConnections = false
        }
    }

    private func show(_ page: Apps.Page) {
        cursor = page.nextCursor
        canContinue = cursor != nil
        partial = page.partial
        byKey = byKey || page.byKey
        state = .loaded
    }
}

/// Connect apps: the account's own connections, then the catalog. This screen lists; an
/// app is connected through Coach, where its Card is approved with it, so Connect, Ask Coach,
/// Sign in again and "Not listed? Ask Coach" open Coach. Where no taf can have an app, its
/// Connect is off and "Make one first" says why, over Discover. A connected app's chevron opens
/// its connections (`AppConnectionsView`), where only ending one is done here, with Touch ID.
struct ConnectAppsView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: ConnectAppsModel
    /// The tafs listed, by KIFF agent: a connection's page names the taf it was made for.
    var tafs: [Home.Taf] = []
    /// The tafs on tafs cloud this person manages: a row's button says "Ask Coach" where none
    /// needs the app (`Apps.buttonKey`), as the iPad's `connectFor`.
    var connectable: [Home.Taf] = []
    /// Whoever manages the account's Cards (KIFF's `cards.manage`) sees a connection's actions.
    var managesCards = true
    var openCoach: () -> Void = {}

    /// The columns' widths, the same for the headings and every row, as the iPad's
    /// `ConnectColumns`: the app takes the rest, at least 200.
    private static let how: CGFloat = 150
    private static let whose: CGFloat = 130
    private static let status: CGFloat = 230
    private static let gap: CGFloat = 12
    /// The chevron's place at each row's end, past Status, as the iPad's list draws its link's.
    private static let chevron: CGFloat = 14

    var body: some View {
        if let app = model.opened {
            AppConnectionsView(app: app, model: model, tafs: tafs, managesCards: managesCards) { model.opened = nil }
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    ScreenTitle(title: words("connect.apps.title"), size: 34, rounded: false)
                    Spacer()
                    // Search sits at the top right, as on the iPad.
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundColor(Theme.soft)
                        TextField(words("connect.apps.search"), text: $model.search).textFieldStyle(.plain).font(.system(size: 14))
                            .onSubmit { Task { await model.load() } }
                    }
                    .padding(.horizontal, 14).frame(width: 240, height: 36)
                    .background(Capsule().fill(Theme.panel)).overlay(Capsule().stroke(Theme.line))
                }
                .padding(.top, 40)
                switch model.state {
                case .loading:
                    ProgressView().controlSize(.small)
                case .unread(let why):
                    Text(words("home.couldnt_load_from_kiff")).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.no)
                    Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.soft)
                    Button(words("common.try_again")) { Task { await model.load() } }
                case .loaded:
                    if model.apps.isEmpty, !model.partial {
                        Text(words("connect.apps.none")).font(.system(size: 14)).foregroundColor(Theme.soft)
                    }
                    if !model.yours.isEmpty {
                        heading(words("connect.apps.yours"))
                        panel {
                            columns
                            ForEach(model.yours) { app in
                                Rectangle().fill(Theme.line).frame(height: 1)
                                row(app, yours: true)
                            }
                        }
                    }
                    if !model.discover.isEmpty {
                        heading(words("connect.apps.discover"))
                        panel {
                            // Connecting needs a taf: said over the apps to connect, never over Yours.
                            if Apps.saysMakeATaf(discover: model.discover, forTaf: false, connectable: connectable) {
                                Text(words("connect.apps_connect_taf_make_one")).font(.system(size: 13)).foregroundColor(Theme.dim)
                                    .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                            }
                            // The headings sit over Discover when there is no Yours above it.
                            if model.yours.isEmpty { columns }
                            ForEach(model.discover) { app in
                                // A line between rows, and under the headings when they are here.
                                if model.yours.isEmpty || app.id != model.discover.first?.id { Rectangle().fill(Theme.line).frame(height: 1) }
                                row(app, yours: false)
                            }
                        }
                    }
                    if model.canContinue {
                        Button(words("connect.apps.more")) { Task { await model.more() } }
                            .buttonStyle(.plain).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.amberText)
                    }
                    // Only when Coach can connect an app that isn't listed, as on the iPad.
                    if model.byKey {
                        Button(words("connect.apps.not_listed"), action: openCoach)
                            .buttonStyle(.plain).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.amberText)
                    }
                }
            }
            .padding(.horizontal, Look.inset)
            .padding(.bottom, Look.inset)
            .pageColumn(.reading)
        }
        .background(Theme.background)
        .task { await model.load() }
        // Touch ID may have changed while away (a finger added, Touch ID locked): the route again.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshRoute() }
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.soft).padding(.top, 10).padding(.leading, 18)
    }

    private func column(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.dim)
    }

    private var columns: some View {
        HStack(spacing: Self.gap) {
            column(words("connect.apps.column_app")).frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
            column(words("connect.apps.column_how")).frame(width: Self.how, alignment: .leading)
            column(words("connect.apps.column_whose")).frame(width: Self.whose, alignment: .leading)
            column(words("connect.apps.column_status")).frame(width: Self.status, alignment: .leading)
            Color.clear.frame(width: Self.chevron, height: 1)
        }
        .padding(.vertical, 12)
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(.horizontal, 18).padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Look.panelRadius).fill(Theme.panel))
    }

    /// One app, in the iPad's columns: its name, how it connects, whose it is, its status.
    private func row(_ app: Apps.App, yours: Bool) -> some View {
        let setup = app.state == "needs_setup"
        return HStack(alignment: .center, spacing: Self.gap) {
            HStack(spacing: 10) {
                // The app's own icon, only when tafs cloud sends one; nothing in its place otherwise.
                // Read from tafs cloud through `AppLogos` (docs/connections.md › Logos).
                if app.logo != nil { AppLogo(logo: app.logo, side: 24, holdsPlace: true) }
                VStack(alignment: .leading, spacing: 2) {
                    // An app an operator sets up first is named in the soft colour, as on the iPad.
                    Text(verbatim: app.name).font(.system(size: 16, weight: .semibold)).foregroundColor(setup ? Theme.soft : Theme.ink)
                    if let subtitle = app.subtitle { Text(verbatim: subtitle).font(.system(size: 13)).foregroundColor(Theme.soft).lineLimit(2) }
                }
            }
            .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
            Text(words(app.howKey)).font(.system(size: 14)).foregroundColor(Theme.soft)
                .frame(width: Self.how, alignment: .leading)
            Text(verbatim: yours ? (app.whose ?? "") : "").font(.system(size: 14)).foregroundColor(Theme.soft)
                .frame(width: Self.whose, alignment: .leading)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    statusWords(app, yours: yours, setup: setup)
                    // With words beside it, the button goes under them, at the trailing edge, so a long label
                    // ("Volver a iniciar sesión", "Preguntar a Coach") never squeezes the status (the iPad's
                    // `BesideOrUnder`, Windows' `ButtonUnder`).
                    if Self.buttonUnder(app, yours: yours, setup: setup) {
                        trailing(app).frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 4)
                    }
                }
                if !Self.buttonUnder(app, yours: yours, setup: setup) {
                    Spacer(minLength: 4)
                    trailing(app)
                }
            }
            .frame(width: Self.status, alignment: .leading)
            chevron(app)
        }
        .frame(minHeight: 52)
        .padding(.vertical, 8)
        // A connected app opens its connections from anywhere on its row, as the iPad's link.
        .contentShape(Rectangle())
        .onTapGesture { if app.isConnected { model.opened = app } }
        .accessibilityElement(children: .contain)
    }

    /// The Status column's words, as the iPad's: Sign in again, Connected, an operator's setup line, and which tafs use it.
    @ViewBuilder private func statusWords(_ app: Apps.App, yours: Bool, setup: Bool) -> some View {
        if app.needsReconnect {
            Text(words("connect.sign_in_again")).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.amberText)
                .fixedSize(horizontal: false, vertical: true)
        } else if app.isYours {
            Text(words("connect.status.connected")).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ok)
        } else if setup, let line = app.words {
            // For an app an operator sets up first: tafs cloud's own line, in its status.
            Text(verbatim: line).font(.system(size: 13)).foregroundColor(Theme.soft).lineLimit(2)
        }
        // Which tafs use one of the account's own connections, under its status.
        if yours, !app.usedBy.isEmpty {
            Text(words("connect.apps.used_by", ["tafs": words.list(app.usedBy)])).font(.system(size: 12)).foregroundColor(Theme.dim).lineLimit(2)
        }
    }

    /// Whether the row's button goes under its status words: it has a button (Connect, Sign in again, Ask Coach) and
    /// words beside it. A check mark, or a button alone, stays beside.
    static func buttonUnder(_ app: Apps.App, yours: Bool, setup: Bool) -> Bool {
        let button = !app.needsSetup && !app.isConnected
        let worded = app.needsReconnect || app.isYours || (setup && app.words != nil) || (yours && !app.usedBy.isEmpty)
        return button && worded
    }

    /// The row's end, as the iPad's `trailing`: a green check for a connected app; nothing for
    /// one an operator sets up first; else its button, as wide as its words, in the iPad's words
    /// (`Apps.buttonKey`: "Ask Coach" where no taf needs it, else Sign in again or Connect),
    /// which opens Coach.
    @ViewBuilder private func trailing(_ app: Apps.App) -> some View {
        if app.needsSetup {
            EmptyView()
        } else if app.isConnected {
            Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ok)
                .accessibilityLabel(words("connect.status.connected"))
        } else {
            Button(action: openCoach) {
                Text(words(Apps.buttonKey(app, connectable: connectable))).padding(.horizontal, 16)
            }
            .buttonStyle(OutlineButtonStyle())
            .fixedSize()
            // No taf can have it: Connect is off, and "Make one first" over Discover says why.
            .disabled(Apps.route(app, connectable: connectable) == .noTaf)
        }
    }

    /// The chevron of an app whose connections open ("Your {app} connections"), as the iPad's link
    /// (`AppConnections.opens`): connected, or holding a connection on this account.
    @ViewBuilder private func chevron(_ app: Apps.App) -> some View {
        if AppConnections.opens(app, in: model.grants) {
            Button { model.opened = app } label: {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.soft)
                    .frame(width: Self.chevron, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(words("connect.apps.your_connections", ["app": app.name]))
        } else {
            Color.clear.frame(width: Self.chevron, height: 1)
        }
    }
}

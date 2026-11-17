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
    /// The app whose connections are open ("Your {app} connections"), from its row's chevron.
    @Published var opened: Apps.App?

    private let cloud: CloudClient
    /// Where this Mac reads its connections; nil reads none.
    private let connections: ConnectionsSource?
    private var cursor: String?
    private var asked = 0

    init(cloud: CloudClient, connections: ConnectionsSource? = nil) {
        self.cloud = cloud
        self.connections = connections
    }

    var yours: [Apps.App] { apps.filter(\.isYours) }
    var discover: [Apps.App] { apps.filter { !$0.isYours } }

    /// Searches from the first page. A slower answer to an older search is dropped.
    func load() async {
        asked += 1
        let mine = asked
        let q = search
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
/// Sign in again and "Not listed? Ask Coach" open Coach. A connected app's chevron opens its
/// connections (`AppConnectionsView`), which only read.
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task { await model.load() }
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
                    if app.needsReconnect {
                        Text(words("connect.sign_in_again")).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.amberText)
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
                Spacer(minLength: 4)
                trailing(app)
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

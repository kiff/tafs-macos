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
    @Published var search = ""

    private let cloud: CloudClient
    private var cursor: String?
    private var asked = 0

    init(cloud: CloudClient) { self.cloud = cloud }

    var yours: [Apps.App] { apps.filter(\.isYours) }
    var discover: [Apps.App] { apps.filter { !$0.isYours } }

    /// Searches from the first page. A slower answer to an older search is dropped.
    func load() async {
        asked += 1
        let mine = asked
        do {
            let page = try await cloud.apps(search)
            guard mine == asked else { return }
            apps = page.apps
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
        do {
            let page = try await cloud.apps(search, cursor: cursor)
            guard mine == asked else { return }
            let listed = Set(apps.map(\.entry))
            apps += page.apps.filter { !listed.contains($0.entry) }
            show(page)
        } catch {
            guard mine == asked else { return }
            state = .unread(why: NeedsYouModel.why(error))
        }
    }

    private func show(_ page: Apps.Page) {
        cursor = page.nextCursor
        canContinue = cursor != nil
        partial = page.partial
        state = .loaded
    }
}

/// Connect apps: the account's own connections, then the catalog. This screen lists; an
/// app is connected through Coach, where its Card is approved with it.
struct ConnectAppsView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: ConnectAppsModel

    /// The columns' widths, the same for the headings and every row, as the iPad's
    /// `ConnectColumns`: the app takes the rest, at least 200.
    private static let how: CGFloat = 150
    private static let whose: CGFloat = 130
    private static let status: CGFloat = 230
    private static let gap: CGFloat = 12

    var body: some View {
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
                    Text(words("connect.apps.not_listed_why")).font(.system(size: 13)).foregroundColor(Theme.soft)
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
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6).fill(Theme.raised).frame(width: 24, height: 24)
                    .overlay(Text(verbatim: String(app.name.prefix(1)).uppercased()).font(.system(size: 12, weight: .bold)).foregroundColor(Theme.soft))
                    .accessibilityHidden(true)
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
            .frame(width: Self.status, alignment: .leading)
        }
        .frame(minHeight: 52)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

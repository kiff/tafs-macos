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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(words("connect.apps.title")).font(Theme.display(28)).foregroundColor(Theme.ink)
                TextField(words("connect.apps.search"), text: $model.search)
                    .textFieldStyle(.roundedBorder).font(.system(size: 14)).frame(maxWidth: 420)
                    .onSubmit { Task { await model.load() } }
                switch model.state {
                case .loading:
                    ProgressView().controlSize(.small)
                case .unread(let why):
                    Text(words("home.couldnt_load_from_kiff")).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.no)
                    Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.dim)
                    Button(words("common.try_again")) { Task { await model.load() } }
                case .loaded:
                    if model.apps.isEmpty, !model.partial {
                        Text(words("connect.apps.none")).font(.system(size: 14)).foregroundColor(Theme.dim)
                    }
                    section(words("connect.apps.yours"), model.yours)
                    section(words("connect.apps.discover"), model.discover)
                    if model.canContinue {
                        Button(words("connect.apps.more")) { Task { await model.more() } }
                            .buttonStyle(.plain).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.coach)
                    }
                    Text(words("connect.apps.not_listed_why")).font(.system(size: 13)).foregroundColor(Theme.dim)
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task { await model.load() }
    }

    @ViewBuilder private func section(_ title: String, _ apps: [Apps.App]) -> some View {
        if !apps.isEmpty {
            Text(title).font(.system(size: 12, weight: .bold)).foregroundColor(Theme.dim).padding(.top, 6)
            VStack(spacing: 0) {
                ForEach(apps) { app in
                    row(app)
                    if app.id != apps.last?.id { Rectangle().fill(Theme.line).frame(height: 1) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        }
    }

    private func row(_ app: Apps.App) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 7).fill(Theme.raised).frame(width: 30, height: 30)
                .overlay(Text(verbatim: String(app.name.prefix(1)).uppercased()).font(.system(size: 14, weight: .bold)).foregroundColor(Theme.soft))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: app.name).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                if let subtitle = app.subtitle { Text(verbatim: subtitle).font(.system(size: 13)).foregroundColor(Theme.soft) }
                // The second line is tafs cloud's; for an app to set up first, its own words.
                if let line = app.words ?? app.line {
                    Text(verbatim: line).font(.system(size: 12)).foregroundColor(app.needsReconnect ? Theme.amberText : Theme.dim)
                }
            }
            Spacer()
            if let whose = app.whose { Text(verbatim: whose).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.soft) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

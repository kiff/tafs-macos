import SwiftUI

/// "Your {app} connections", as the iPad's `AppConnectionsView` (kiff/tafs
/// `ios/Tafs/Views/ConnectAppsView.swift:488-722`): a section per taf the app's connections were
/// made for, those needing attention first, then the removed tafs', then "Other connections".
/// What would change a connection (Sign in again, Replace the key, Remove access, Cancel, Clear
/// these connections) is drawn as on the iPad for whoever manages the Cards; a click asks the
/// iPad's question first where the iPad asks one. Ending one (Remove access, Cancel the request,
/// Cancel the sign-in, Clear) is done here on a Mac whose device key is in the Secure Enclave and
/// that can check Touch ID: Touch ID only, then the device key signs planque's `DELETE`
/// (`ConnectionEnding`), with "Approve on your phone instead" beside it. On any other Mac, and for
/// anything that grants access (Sign in again, Replace the key), it says to approve on another
/// device (`approval.device_can_not_approve_approve`) and sends nothing (docs/connections.md).
/// planque's own row opens the connection's page (`ConnectionDetailView`).
struct AppConnectionsView: View {
    @Environment(\.words) private var words
    let app: Apps.App
    @ObservedObject var model: ConnectAppsModel
    let tafs: [Home.Taf]
    let managesCards: Bool
    let back: () -> Void
    /// The action clicked last, by its connection's id (or `clear`): the gate's words show under it.
    @State private var gated: String?
    /// The connection whose page is open (planque's row), by id.
    @State private var detail: String?

    /// `gated` starts the page as after a click on that action (its screenshot).
    init(app: Apps.App, model: ConnectAppsModel, tafs: [Home.Taf], managesCards: Bool, gated: String? = nil, back: @escaping () -> Void) {
        self.app = app
        self.model = model
        self.tafs = tafs
        self.managesCards = managesCards
        self.back = back
        _gated = State(initialValue: gated)
    }

    var body: some View {
        if let id = detail, let grant = model.grants.first(where: { $0.id == id }) {
            let end = grant.id + "|end"
            ConnectionDetailView(grant: grant, appTitle: app.name, managesCards: managesCards, lastFailed: lastFailure(grant),
                                 ending: ConnectionEnd(route: model.endRoute, busy: model.ending.contains(end), note: model.notes[end],
                                                perform: { [model] prompt in await model.disconnect(grant.id, prompt: prompt, id: end) })) { detail = nil }
        } else {
            page
        }
    }

    @ViewBuilder private var page: some View {
        let tafs = self.tafs
        let parts = AppConnections.groups(AppConnections.connections(of: app, in: model.grants),
                                          taf: { AppConnections.taf(of: $0, in: tafs) }, removed: Set(model.removedTafs.map(\.agent)))
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                backButton
                ScreenTitle(title: words("connect.apps.your_connections", ["app": app.name]), size: 34, rounded: false)
                // This Mac didn't read its connections: it says so, rather than an empty list.
                if !model.readsConnections {
                    Text(words("connect.start_connected_tools_first", ["device": "Mac"])).font(.system(size: 15)).foregroundColor(Theme.soft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(parts.tafs) { group in
                    ConnectionsSection(title: group.taf) { rows(group.grants, taf: group.taf) }
                }
                if !parts.removed.isEmpty { removedSection(parts.removed) }
                if !parts.others.isEmpty {
                    ConnectionsSection(title: words("connect.other_connections")) { rows(parts.others, taf: nil) }
                }
                // Said only to whoever manages Cards, and only when a connection here is a taf's.
                if managesCards, !parts.tafs.isEmpty {
                    Text(words("connect.apps.disconnect_why")).font(.system(size: 13)).foregroundColor(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 18)
                }
            }
            .padding(.horizontal, Look.inset)
            .padding(.bottom, Look.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
    }

    /// Back to Connect apps, as the iPad's navigation bar does.
    private var backButton: some View {
        Button(action: back) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                Text(words("connect.apps.title")).font(.system(size: 14))
            }
            .foregroundColor(Theme.amberText).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 18)
    }

    /// `taf` is the taf the connections were made for, by name: Remove access's question names it.
    /// A connection's last failed call, from the Record's newest calls, its own taf's first.
    private func lastFailure(_ g: AppConnections.Grant) -> String? {
        AppConnections.lastFailure(g, record: model.calls, ownTaf: AppConnections.tafID(of: g, in: tafs), words)
    }

    private func rows(_ grants: [AppConnections.Grant], taf: String?) -> some View {
        ForEach(grants) { g in
            if g.id != grants.first?.id { Rectangle().fill(Theme.line).frame(height: 1) }
            ConnectionRow(grant: g, app: app, taf: taf, alsoOn: AppConnections.alsoOn(g, in: tafs), lastFailed: lastFailure(g),
                          managesCards: managesCards, model: model, gated: $gated) { detail = g.id }
        }
    }

    /// The removed tafs' connections, as tafs cloud names them: no action each, and one Clear
    /// for those no live taf's Card uses (`AppConnections.clearable`): with Touch ID here, else on
    /// the phone.
    private func removedSection(_ removed: [AppConnections.Grant]) -> some View {
        let listed = AppConnections.removedListed(model.removedTafs)
        let clearable = AppConnections.clearable(removed, listed: listed)
        return ConnectionsSection(title: words("connect.from_removed")) {
            ForEach(removed) { g in
                if g.id != removed.first?.id { Rectangle().fill(Theme.line).frame(height: 1) }
                RemovedConnectionRow(grant: g, app: app, usedBy: listed[g.id]?.usedBy.map(\.name))
            }
            if managesCards, !clearable.isEmpty {
                Rectangle().fill(Theme.line).frame(height: 1)
                // Asked first, as the iPad's: how many it clears, and that one a Card uses is kept.
                GatedAction(title: words("connect.clear_removed.button"), id: "clear", gated: $gated,
                            ask: GateQuestion(title: words.count("connect.clear_removed.title", clearable.count),
                                              message: words("connect.clear_removed.body"), confirm: words("connect.clear_removed.clear"),
                                              cancel: words("common.cancel")),
                            route: model.endRoute, busy: model.ending.contains("clear"), note: model.notes["clear"],
                            perform: { [model] in await model.clear(removed.map(\.id)) })
                    .padding(.vertical, 12)
            }
        }
    }
}

/// One heading and its connections in a panel, as a section of the iPad's list.
private struct ConnectionsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.soft).padding(.top, 10).padding(.leading, 18)
            VStack(alignment: .leading, spacing: 0, content: content)
                .padding(.horizontal, 18).padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Look.panelRadius).fill(Theme.panel))
        }
    }
}

/// The question the iPad asks before an action that ends something, in its words.
struct GateQuestion: Equatable {
    let title: String
    let message: String?
    /// The question's own button, red.
    let confirm: String
    /// The button that leaves it as it is.
    let cancel: String
}

/// An action drawn as the iPad's: a click asks the iPad's question first when it asks one (`ask`).
/// One that ends a connection (`perform`) on a Touch ID Mac (`route`) then runs it: Touch ID, then
/// planque's `DELETE`, with "Approve on your phone instead" under it and how it went (`note`).
/// Anything else shows why this Mac can't, under it, and sends nothing.
struct GatedAction: View {
    @Environment(\.words) private var words
    let title: String
    let id: String
    var color: Color = Theme.no
    @Binding var gated: String?
    var ask: GateQuestion?
    /// Where it's done: only `.touchID` with `perform` runs anything.
    var route: ConnectionEnding.Route = .phone
    /// It's running: the button waits.
    var busy = false
    /// How it went, under it.
    var note: String?
    /// Ends the connection: Touch ID, then planque's `DELETE` (`ConnectAppsModel`). Nil for
    /// anything that grants access, which is never done here.
    var perform: (() async -> Void)?
    @State private var asking = false

    /// Done here: only an ending, on a Touch ID Mac.
    private var here: Bool { route == .touchID && perform != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { if ask == nil { act() } else { asking = true } } label: {
                Text(verbatim: title).font(.system(size: 15, weight: .semibold)).foregroundColor(color)
            }
            .buttonStyle(.plain)
            .disabled(busy)
            if busy { ProgressView().controlSize(.small) }
            if let note, !busy {
                Text(verbatim: note).font(.system(size: 13)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if here {
                // The phone stays offered beside Touch ID, as the owner asked.
                Text(words("approval.security_key.on_phone")).font(.system(size: 13)).foregroundColor(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            } else if gated == id {
                Text(words(ConnectionEnding.phoneLine)).font(.system(size: 13)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog(ask?.title ?? "", isPresented: $asking, titleVisibility: .visible) {
            Button(ask?.confirm ?? title, role: .destructive) { act() }
            Button(ask?.cancel ?? words("common.cancel"), role: .cancel) {}
        } message: {
            if let message = ask?.message { Text(verbatim: message) }
        }
    }

    /// Ends it here with Touch ID, or says to approve on another device.
    private func act() {
        if here, let perform {
            gated = nil
            Task { await perform() }
        } else {
            gated = id
        }
    }
}

/// A connection, as the iPad's `entry` and `row` (`ConnectAppsView.swift:594-683`): planque's row
/// when it draws one (its name, the tafs on it, its health); else its name, planque's words for
/// its status, how to fix it and Remove access (or Cancel while its sign-in waits).
private struct ConnectionRow: View {
    @Environment(\.words) private var words
    let grant: AppConnections.Grant
    let app: Apps.App
    /// The taf it was made for, by name, when this app can name it.
    let taf: String?
    /// The other tafs whose Card draws on its tools (`AppConnections.alsoOn`): its line, and Remove access names them.
    let alsoOn: [String]
    /// Its last failed call, in tafs cloud's words, when the Record has one.
    let lastFailed: String?
    let managesCards: Bool
    @ObservedObject var model: ConnectAppsModel
    @Binding var gated: String?
    /// Opens planque's row's page.
    let open: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: grant.name ?? app.name).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink)
                if grant.rowFromPlanque { planqueLines } else { ownLines }
                // As the iPad's `entry`: the other Cards on it, then its last failed call (gap 13), in red.
                if let also = AppConnections.alsoOnLine(alsoOn, words) {
                    Text(verbatim: also).font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
                }
                if let lastFailed {
                    Text(verbatim: lastFailed).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
                }
                misplaced
                if !grant.rowFromPlanque, managesCards { fix }
            }
            Spacer(minLength: 8)
            if grant.rowFromPlanque {
                // planque's row opens its page, as the iPad's link.
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.soft)
                    .frame(height: 24)
            } else if managesCards {
                let id = grant.id + "|end"
                let asked = endQuestion
                // Remove access, Cancel the request, Cancel the sign-in: ended here with Touch ID.
                GatedAction(title: words(AppConnections.endKey(grant)), id: id, gated: $gated, ask: asked,
                            route: model.endRoute, busy: model.ending.contains(id), note: model.notes[id],
                            perform: { [model, grant] in await model.disconnect(grant.id, prompt: asked.title, id: id) })
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 260, alignment: .trailing)
            }
        }
        .frame(minHeight: 44, alignment: .leading)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { if grant.rowFromPlanque { open() } }
        .accessibilityAddTraits(grant.rowFromPlanque ? .isButton : [])
    }

    /// The iPad's question before ending it: Cancel's for a request or a sign-in that waits
    /// (`ConnectionFixWords`), else Remove access's (`DisconnectWords`), naming the taf it ends and the other tafs
    /// whose Cards stop with it (`alsoOn`).
    private var endQuestion: GateQuestion {
        if grant.cancellable {
            return GateQuestion(title: AppConnections.cancelTitle(grant, words), message: words("connect.cancel_sign_in.body", ["vendor": grant.vendor]),
                                confirm: words(AppConnections.cancelWordKey(grant)), cancel: words("connect.cancel_sign_in.keep_waiting"))
        }
        return GateQuestion(title: AppConnections.disconnectTitle(grant.vendor, taf: taf, alsoStops: alsoOn, words),
                            message: AppConnections.disconnectMessage(grant.vendor, taf: taf, alsoStops: alsoOn, key: grant.takesKey, words),
                            confirm: words("connect.disconnect_button"), cancel: words("common.cancel"))
    }

    /// planque's own row: the tafs that use it and its health, as sent.
    @ViewBuilder private var planqueLines: some View {
        if let used = grant.usedBy, !used.isEmpty {
            Text(words("connect.apps.used_by", ["tafs": used.joined(separator: ", ")])).font(.system(size: 13)).foregroundColor(Theme.soft)
        }
        if let health = grant.health {
            Text(verbatim: health.words).font(.system(size: 13)).foregroundColor(health.ok ? Theme.dim : Theme.amberText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// planque's words for its status, or that its sign-in waits.
    @ViewBuilder private var ownLines: some View {
        if let status = grant.statusWords {
            Text(verbatim: status).font(.system(size: 13)).foregroundColor(Theme.dim)
        } else if grant.waitingSignIn {
            Text(words("connect.status.waiting_sign_in", ["vendor": grant.vendor])).font(.system(size: 13)).foregroundColor(Theme.dim)
        }
    }

    /// Made for a taf that doesn't use the app, as tafs cloud says (`misplaced`).
    @ViewBuilder private var misplaced: some View {
        if let wrong = app.misplaced.first(where: { $0.grant == grant.id }) {
            Text(words("connect.misplaced", ["taf": wrong.name, "app": app.name])).font(.system(size: 13)).foregroundColor(Theme.amberText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// How it's fixed: a provider's connection says so; else Sign in again, or Replace the key.
    @ViewBuilder private var fix: some View {
        if grant.signsInThroughProvider {
            Text(words("connect.through_provider", ["vendor": grant.vendor])).font(.system(size: 13)).foregroundColor(Theme.soft)
                .fixedSize(horizontal: false, vertical: true)
        } else if !grant.cancellable {
            // It grants access: never done here, on any Mac.
            GatedAction(title: words(grant.takesKey ? "connect.replace_key" : "connect.sign_in_again"), id: grant.id + "|fix", color: Theme.amberText, gated: $gated)
                .padding(.top, 4)
        }
    }
}

/// A removed taf's connection, as the iPad's `removedRow`: what it is, the taf it was made for by
/// the name planque keeps, planque's words for its status, and the tafs whose Cards still use it.
private struct RemovedConnectionRow: View {
    @Environment(\.words) private var words
    let grant: AppConnections.Grant
    let app: Apps.App
    let usedBy: [String]?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: grant.name ?? app.name).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink)
            if let name = grant.agentName, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(verbatim: name).font(.system(size: 13)).foregroundColor(Theme.soft)
            }
            if let status = grant.statusWords {
                Text(verbatim: status).font(.system(size: 13)).foregroundColor(Theme.dim)
            }
            if let kept = usedBy.flatMap({ AppConnections.keptLine($0, words) }) {
                Text(verbatim: kept).font(.system(size: 13)).foregroundColor(Theme.soft)
            }
        }
        .frame(minHeight: 44, alignment: .leading)
        .padding(.vertical, 8)
    }
}

/// How a connection's page ends it: where (`route`), whether it's running, how it went, and the
/// ending itself with Touch ID's reason (`ConnectAppsModel.disconnect`).
struct ConnectionEnd {
    let route: ConnectionEnding.Route
    let busy: Bool
    let note: String?
    let perform: (String) async -> Void
}

/// A connection's page, as the iPad's `ConnectionDetailView` (`ConnectAppsView.swift:1181-1262`),
/// opened from planque's row: its health, the tafs that use it, and, for whoever manages the
/// Cards, the actions planque says work for it now, in planque's words and order. Remove asks
/// first in planque's words, naming what stops, then ends it here with Touch ID on a Touch ID
/// Mac; every other action, and Remove on any other Mac, says to approve on another device and
/// sends nothing, as the rest of this page (docs/connections.md).
struct ConnectionDetailView: View {
    @Environment(\.words) private var words
    let grant: AppConnections.Grant
    let appTitle: String
    let managesCards: Bool
    /// Its last failed call, in tafs cloud's words, under its health, as the iPad's detail.
    var lastFailed: String? = nil
    /// How Remove is done here (`ConnectionEnding`); nil, on the phone.
    let ending: ConnectionEnd?
    let back: () -> Void
    /// The action clicked last, by its place in planque's list: the gate's words show under it.
    @State private var gated: String?

    /// `gated` starts the page as after a click on that action (its screenshot).
    init(grant: AppConnections.Grant, appTitle: String, managesCards: Bool, lastFailed: String? = nil, ending: ConnectionEnd? = nil, gated: String? = nil,
         back: @escaping () -> Void) {
        self.grant = grant
        self.appTitle = appTitle
        self.managesCards = managesCards
        self.lastFailed = lastFailed
        self.ending = ending
        self.back = back
        _gated = State(initialValue: gated)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                backButton
                ScreenTitle(title: grant.name ?? appTitle, size: 34, rounded: false)
                // Two sections without headings, as the iPad's list.
                panel { about }
                if managesCards, !actions.isEmpty {
                    panel {
                        // By place: planque may send two actions with one id (Sign in again by approve, and by key).
                        ForEach(actions, id: \.offset) { item in
                            if item.offset > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                            action(item.offset, item.element)
                                .padding(.vertical, 12)
                        }
                    }
                }
            }
            .padding(.horizontal, Look.inset)
            .padding(.bottom, Look.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
    }

    /// One of planque's actions. Remove (`removes`) is ended here with Touch ID on a Touch ID Mac;
    /// Sign in again grants access and never is.
    private func action(_ offset: Int, _ a: AppConnections.Grant.Action) -> GatedAction {
        let id = "\(offset)"
        guard a.removes, let ending else {
            return GatedAction(title: a.words, id: id, color: a.removes ? Theme.no : Theme.amberText, gated: $gated, ask: question(a))
        }
        // Asked in planque's words: Touch ID asks the same.
        return GatedAction(title: a.words, id: id, color: Theme.no, gated: $gated, ask: question(a),
                           route: ending.route, busy: ending.busy, note: ending.note,
                           perform: { [words = a.words, perform = ending.perform] in await perform(words) })
    }

    /// planque's known actions with their places, in its order.
    private var actions: [(offset: Int, element: AppConnections.Grant.Action)] { Array(grant.knownActions.enumerated()) }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(.horizontal, 18).padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Look.panelRadius).fill(Theme.panel))
    }

    /// Its health, in planque's words (ink when well, else amber), and the tafs that use it.
    @ViewBuilder private var about: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let health = grant.health {
                Text(verbatim: health.words).font(.system(size: 15, weight: .semibold)).foregroundColor(health.ok ? Theme.ink : Theme.amberText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let used = grant.usedBy, !used.isEmpty {
                Text(words("connect.apps.used_by", ["tafs": used.joined(separator: ", ")])).font(.system(size: 14)).foregroundColor(Theme.soft)
            }
            if let lastFailed {
                Text(verbatim: lastFailed).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
    }

    /// Remove is asked first, in planque's own words, with what stops; the rest aren't.
    private func question(_ action: AppConnections.Grant.Action) -> GateQuestion? {
        guard action.removes else { return nil }
        return GateQuestion(title: action.words, message: action.stops, confirm: action.words, cancel: words("common.cancel"))
    }

    /// Back to the app's connections.
    private var backButton: some View {
        Button(action: back) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                Text(words("connect.apps.your_connections", ["app": appTitle])).font(.system(size: 14))
            }
            .foregroundColor(Theme.amberText).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 18)
    }
}

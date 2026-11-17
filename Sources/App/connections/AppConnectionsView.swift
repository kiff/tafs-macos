import SwiftUI

/// "Your {app} connections", as the iPad's `AppConnectionsView` (kiff/tafs
/// `ios/Tafs/Views/ConnectAppsView.swift:488-660`): a section per taf the app's connections were
/// made for, those needing attention first, then the removed tafs', then "Other connections".
/// This page only reads. What would change a connection (Sign in again, Replace the key, Remove
/// access, Cancel, Clear these connections) is drawn as on the iPad for whoever manages the Cards,
/// and a click says to approve on another device (`approval.device_can_not_approve_approve`),
/// sending nothing: this Mac can't sign it (docs/connections.md).
struct AppConnectionsView: View {
    @Environment(\.words) private var words
    let app: Apps.App
    @ObservedObject var model: ConnectAppsModel
    let tafs: [Home.Taf]
    let managesCards: Bool
    let back: () -> Void
    /// The action clicked last, by its connection's id (or `clear`): the gate's words show under it.
    @State private var gated: String?

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
                    ConnectionsSection(title: group.taf) { rows(group.grants) }
                }
                if !parts.removed.isEmpty { removedSection(parts.removed) }
                if !parts.others.isEmpty {
                    ConnectionsSection(title: words("connect.other_connections")) { rows(parts.others) }
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

    private func rows(_ grants: [AppConnections.Grant]) -> some View {
        ForEach(grants) { g in
            if g.id != grants.first?.id { Rectangle().fill(Theme.line).frame(height: 1) }
            ConnectionRow(grant: g, app: app, managesCards: managesCards, gated: $gated)
        }
    }

    /// The removed tafs' connections, as tafs cloud names them: no action each, and one Clear
    /// for those no live taf's Card uses (`AppConnections.clearable`).
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
                GatedAction(title: words("connect.clear_removed.button"), id: "clear", gated: $gated)
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

/// An action this Mac can't sign, drawn as the iPad's: a click shows why, under it, and sends nothing.
private struct GatedAction: View {
    @Environment(\.words) private var words
    let title: String
    let id: String
    var color: Color = Theme.no
    @Binding var gated: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { gated = id } label: {
                Text(verbatim: title).font(.system(size: 15, weight: .semibold)).foregroundColor(color)
            }
            .buttonStyle(.plain)
            if gated == id {
                Text(words("approval.device_can_not_approve_approve")).font(.system(size: 13)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A connection, as the iPad's `entry` and `row` (`ConnectAppsView.swift:577-660`): planque's row
/// when it draws one (its name, the tafs on it, its health); else its name, planque's words for
/// its status, how to fix it and Remove access (or Cancel while its sign-in waits).
private struct ConnectionRow: View {
    @Environment(\.words) private var words
    let grant: AppConnections.Grant
    let app: Apps.App
    let managesCards: Bool
    @Binding var gated: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: grant.name ?? app.name).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink)
                if grant.rowFromPlanque { planqueLines } else { ownLines }
                misplaced
                if !grant.rowFromPlanque, managesCards { fix }
            }
            Spacer(minLength: 8)
            if !grant.rowFromPlanque, managesCards {
                GatedAction(title: words(AppConnections.endKey(grant)), id: grant.id + "|end", gated: $gated).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 260, alignment: .trailing)
            }
        }
        .frame(minHeight: 44, alignment: .leading)
        .padding(.vertical, 8)
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

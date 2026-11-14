import AppKit
import SwiftUI

/// Light, dark, or as the Mac is set: kept between launches, and applied to the whole app.
enum ThemeChoice: String, CaseIterable, Identifiable {
    case light, dark, system

    var id: String { rawValue }
    var titleKey: String { "settings.theme.\(rawValue)" }
    static let key = "tafs.theme"

    static func saved(in defaults: UserDefaults = .standard) -> ThemeChoice {
        defaults.string(forKey: key).flatMap(ThemeChoice.init) ?? .system
    }

    var appearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }

    func apply(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.key)
        NSApp?.appearance = appearance
    }
}

@MainActor
final class AccountModel: ObservableObject {
    /// Who is signed in, once KIFF has said; nil until then, and if it can't be read.
    @Published private(set) var me: Me?
    /// The plan's one line, in tafs cloud's words.
    @Published private(set) var planLine: String?
    @Published var theme: ThemeChoice

    private let account: AccountClient
    private let cloud: CloudClient
    private let defaults: UserDefaults

    init(account: AccountClient, cloud: CloudClient, defaults: UserDefaults = .standard) {
        self.account = account
        self.cloud = cloud
        self.defaults = defaults
        theme = ThemeChoice.saved(in: defaults)
    }

    /// Each line is read on its own: one that can't be read is left out, never the page.
    func load() async {
        me = try? await account.me()
        planLine = (try? await cloud.balance())?.words
    }

    func choose(_ theme: ThemeChoice) {
        self.theme = theme
        theme.apply(defaults: defaults)
    }
}

/// Account, to the iPad's layout: a large title and grouped panels of rows.
struct AccountView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: AccountModel
    @ObservedObject var devices: DevicesModel
    /// Opens another screen of the sidebar from its row.
    let open: (Screen) -> Void
    let addThisMac: () -> Void
    let signOut: () -> Void
    @State private var showingDevices = false

    var body: some View {
        if showingDevices {
            VStack(alignment: .leading, spacing: 0) {
                Button { showingDevices = false } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                        Text(words("settings.title")).font(.system(size: 14))
                    }
                    .foregroundColor(Theme.amberText).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Look.inset).padding(.top, 18)
                DevicesView(model: devices)
            }
            .background(Theme.background)
        } else {
            page
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ScreenTitle(title: words("settings.title")).padding(.top, 40)
                group(words("settings.your_account")) {
                    row(words("settings.mode"), value: words("settings.mode_kiff"))
                    divider
                    row(words("settings.kiff_account"), value: model.me?.email ?? model.me?.account ?? "")
                }
                if model.me?.viewOnly == true {
                    // Exactly when KIFF says this session is view-only.
                    group(words("pair.view_only.title")) {
                        Text(words("pair.view_only.lead", ["device": words("device.mac")])).font(.system(size: 13)).foregroundColor(Theme.soft)
                            .padding(.vertical, 12).fixedSize(horizontal: false, vertical: true)
                        divider
                        action(words("pair.view_only.add", ["device": words("device.mac")]), color: Theme.amberText, addThisMac)
                    }
                }
                group(words("settings.people_apps")) {
                    link(words("settings.devices.title")) { showingDevices = true }
                    divider
                    link(words("connect.apps.title")) { open(.connectApps) }
                }
                if let plan = model.planLine {
                    group(words("settings.plan")) {
                        Button { open(.usage) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(verbatim: plan).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                                    Text(words("usage.title")).font(.system(size: 12)).foregroundColor(Theme.amberText)
                                }
                                Spacer()
                                chevron
                            }
                            .padding(.vertical, 12).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                group(words("settings.theme_title")) {
                    HStack(spacing: 0) {
                        ForEach(ThemeChoice.allCases) { choice in
                            let chosen = model.theme == choice
                            Button { model.choose(choice) } label: {
                                Text(words(choice.titleKey)).font(.system(size: 13, weight: chosen ? .semibold : .regular)).foregroundColor(Theme.ink)
                                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                                    .background(Capsule().fill(chosen ? Theme.panel : Color.clear)).contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(chosen ? .isSelected : [])
                        }
                    }
                    .padding(2).background(Capsule().fill(Theme.raised)).padding(.vertical, 10)
                }
                group(words("sign_in.how_works")) {
                    Text(words("sign_in.every_action_taf_takes_goes", ["device": words("device.mac")]))
                        .font(.system(size: 13)).foregroundColor(Theme.soft).padding(.vertical, 12).fixedSize(horizontal: false, vertical: true)
                }
                group(words("settings.legal")) {
                    action(words("settings.terms"), color: Theme.amberText) { Self.openPage("https://kiff.dev/tafs/terms") }
                    divider
                    action(words("settings.privacy_policy"), color: Theme.amberText) { Self.openPage("https://kiff.dev/tafs/privacy") }
                }
                group(nil) {
                    action(words("settings.sign_out"), color: Theme.no, signOut)
                }
            }
            .padding(.horizontal, Look.inset)
            .padding(.bottom, Look.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task { await model.load() }
    }

    /// Only tafs' own pages on kiff.dev are opened from here.
    static func openPage(_ address: String) {
        guard let url = URL(string: address), url.scheme == "https", url.host == "kiff.dev" else { return }
        NSWorkspace.shared.open(url)
    }

    private func group<Content: View>(_ title: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.soft).padding(.leading, 18).padding(.top, 14)
            } else {
                Color.clear.frame(height: 14)
            }
            VStack(alignment: .leading, spacing: 0, content: content)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Look.panelRadius).fill(Theme.panel))
        }
    }

    private var divider: some View { Rectangle().fill(Theme.line).frame(height: 1) }
    private var chevron: some View { Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.soft) }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 15)).foregroundColor(Theme.ink)
            Spacer()
            Text(verbatim: value).font(.system(size: 15)).foregroundColor(Theme.soft).lineLimit(1).textSelection(.enabled)
        }
        .padding(.vertical, 12)
    }

    private func link(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 15)).foregroundColor(Theme.ink)
                Spacer()
                chevron
            }
            .padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func action(_ title: String, color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 15)).foregroundColor(color)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

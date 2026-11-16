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
    /// The balance, for the Plan card: tafs cloud's `plan_line` in `plan_tone`'s colour.
    @Published private(set) var balance: Usage.Balance?
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
        balance = try? await cloud.balance()
    }

    /// The Account page reads only what the window's own read didn't get: `/v1/me` is read
    /// once, not again each time the page opens.
    func loadIfNeeded() async {
        if me == nil { me = try? await account.me() }
        if balance == nil { balance = try? await cloud.balance() }
    }

    /// The plan line's colour, by its tone as on the iPad.
    var planColor: Color {
        switch balance?.planTone {
        case "waiting": return Theme.no
        case "warning": return Theme.amberText
        default: return Theme.ink
        }
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
    /// People & groups, read from KIFF; nil leaves its row out.
    var people: PeopleModel? = nil
    /// Export my chats; nil leaves it out.
    var exportChats: ExportChatsModel? = nil
    /// Alerts on this Mac, for this account; nil leaves its row out.
    var alerts: AlertsModel? = nil
    /// A taf's name by its KIFF agent, for what each group uses.
    var tafName: (String) -> String? = { _ in nil }
    /// Opens another screen of the sidebar from its row.
    let open: (Screen) -> Void
    let addThisMac: () -> Void
    /// This Mac's device key is a software key (no Secure Enclave): adding it with the phone
    /// still leaves it view-only, so it isn't offered, and the line says where approvals go.
    var softwareKey = false
    let signOut: () -> Void
    @State private var showingDevices = false
    @State private var showingPeople = false
    @State private var showingAlerts = false
    @State private var confirmingSignOut = false

    var body: some View {
        if showingAlerts {
            VStack(alignment: .leading, spacing: 0) {
                back { showingAlerts = false }
                if let alerts { AlertsView(model: alerts) }
            }
            .background(Theme.background)
        } else if showingPeople, let people {
            VStack(alignment: .leading, spacing: 0) {
                back { showingPeople = false }
                PeopleView(model: people, me: model.me, tafName: tafName)
            }
            .background(Theme.background)
        } else if showingDevices {
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
                DevicesView(model: devices, signOutThisMac: signOut)
            }
            .background(Theme.background)
        } else {
            page
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ScreenTitle(title: words("settings.title"), size: 34, rounded: false).padding(.top, 40)
                group(words("settings.your_account")) {
                    row(words("settings.mode"), value: words("settings.mode_kiff"))
                    divider
                    row(words("settings.kiff_account"), value: model.me?.account ?? "")
                    // Who signed in, when it isn't the account's own name, as on the iPad.
                    if let email = model.me?.signedInAs {
                        divider
                        row(words("settings.signed_in_as"), value: email)
                    }
                }
                if model.me?.viewOnly == true {
                    // Exactly when KIFF says this session is view-only.
                    group(words("pair.view_only.title")) {
                        if softwareKey {
                            // The shared line for a computer with a software key, as the phone
                            // says when it pairs one: approvals go to the phone or a passkey.
                            Text(words("settings.devices.pair_software_key")).font(.system(size: 13)).foregroundColor(Theme.soft)
                                .padding(.vertical, 12).fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(words("pair.view_only.lead", ["device": words("device.mac")])).font(.system(size: 13)).foregroundColor(Theme.soft)
                                .padding(.vertical, 12).fixedSize(horizontal: false, vertical: true)
                            divider
                            action(words("pair.view_only.add", ["device": words("device.mac")]), color: Theme.amberText, addThisMac)
                        }
                    }
                }
                group(words("settings.people_apps")) {
                    // People & groups first, as the iPad's list has it.
                    if people != nil {
                        link(words("people.title")) { showingPeople = true }
                        divider
                    }
                    link(words("settings.devices.title")) { showingDevices = true }
                    divider
                    link(words("connect.apps.title")) { open(.connectApps) }
                }
                // The Plan card always, as on the iPad: tafs cloud's plan line in its tone's
                // colour when it is read, else Plan & usage alone.
                group(words("settings.plan")) {
                    Button { open(.usage) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                if let plan = model.balance?.planLine {
                                    Text(verbatim: plan).font(.system(size: 16, weight: .semibold)).foregroundColor(model.planColor)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(words("usage.title")).font(.system(size: 13)).foregroundColor(Theme.amberText)
                                } else {
                                    Text(words("usage.title")).font(.system(size: 17)).foregroundColor(Theme.ink)
                                }
                            }
                            Spacer()
                            chevron
                        }
                        .padding(.vertical, 12).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                // Alerts, a row on its own, as the iPad's list has it.
                if alerts != nil {
                    group(nil) { link(words("settings.alerts")) { showingAlerts = true } }
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
                // A builder takes at most 10 views on macOS 12 (Swift 5.7): the last sections are one.
                Group {
                    // The language tafs's lines are in, by its own name, and macOS's own setting to
                    // change it (Language & Region › Applications), as the iPad opens iOS's.
                    group(words("settings.language_title")) {
                        row(words("settings.language_title"), value: AppInfo.languageName(words.language))
                        divider
                        action(words("settings.change_language"), color: Theme.amberText) { Self.openLanguageSettings() }
                    }
                    // Their own copy, for their rights of access and portability, as the iPad's.
                    if let exportChats {
                        group(nil) { ExportChatsRow(model: exportChats) }
                        Text(words("export.own_chats_each_taf_coach")).font(.system(size: 13)).foregroundColor(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 18)
                    }
                    group(words("sign_in.how_works")) {
                        Text(words("sign_in.every_action_taf_takes_goes", ["device": words("device.mac")]))
                            .font(.system(size: 14)).foregroundColor(Theme.soft).padding(.vertical, 12).fixedSize(horizontal: false, vertical: true)
                    }
                    group(words("settings.legal")) {
                        action(legal(words("settings.terms")), color: Theme.amberText) { Self.openPage(LegalPages.terms(words.language)) }
                        divider
                        action(legal(words("settings.privacy_policy")), color: Theme.amberText) { Self.openPage(LegalPages.privacy(words.language)) }
                    }
                    group(words("settings.about")) {
                        row(words("settings.version"), value: AppInfo.version(Bundle.main.infoDictionary ?? [:]))
                        divider
                        Text(words("home.tagline")).font(.system(size: 17)).foregroundColor(Theme.dim).padding(.vertical, 12)
                    }
                    group(words("settings.account_actions")) {
                        // Confirmed first, so a stray click never ends the session.
                        action(words("settings.sign_out"), color: Theme.no) { confirmingSignOut = true }
                    }
                }
            }
            .padding(.horizontal, Look.inset)
            .padding(.bottom, Look.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task { await model.loadIfNeeded() }
        .alert(words("settings.sign_out_of_kiff.title"), isPresented: $confirmingSignOut) {
            Button(words("settings.sign_out"), role: .destructive) { signOut() }
            Button(words("common.cancel"), role: .cancel) {}
        } message: {
            Text(words("settings.sign_out_of_kiff.body_device", ["device": words("device.mac")]))
        }
    }

    /// The legal pages open in the app's language where kiff.dev has them (`LegalPages`); in any
    /// other language the label says the page is in English.
    private func legal(_ label: String) -> String {
        LegalPages.saysEnglish(words.language) ? words("settings.legal_in_english", ["label": label]) : label
    }

    /// macOS's Language & Region, where a language is chosen for one app.
    static func openLanguageSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.international") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Only tafs' own pages on kiff.dev are opened from here.
    static func openPage(_ address: String) {
        guard let url = URL(string: address), url.scheme == "https", url.host == "kiff.dev" else { return }
        NSWorkspace.shared.open(url)
    }

    private func group<Content: View>(_ title: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.soft).padding(.leading, 18).padding(.top, 14)
            } else {
                Color.clear.frame(height: 14)
            }
            VStack(alignment: .leading, spacing: 0, content: content)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Look.panelRadius).fill(Theme.panel))
        }
    }

    /// Back to Account, as the iPad's navigation bar does.
    private func back(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                Text(words("settings.title")).font(.system(size: 14))
            }
            .foregroundColor(Theme.amberText).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Look.inset).padding(.top, 18)
    }

    private var divider: some View { Rectangle().fill(Theme.line).frame(height: 1) }
    private var chevron: some View { Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.soft) }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 17)).foregroundColor(Theme.ink)
            Spacer()
            Text(verbatim: value).font(.system(size: 17)).foregroundColor(Theme.soft).lineLimit(1).textSelection(.enabled)
        }
        .padding(.vertical, 12)
    }

    private func link(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 17)).foregroundColor(Theme.ink)
                Spacer()
                chevron
            }
            .padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func action(_ title: String, color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 17)).foregroundColor(color)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

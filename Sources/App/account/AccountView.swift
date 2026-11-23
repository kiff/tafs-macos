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
    /// This Mac's security key, when it approves with one (kiff/cloud#96): the time zone is then approved by the key,
    /// named in its sheet. Set by the window once its session is known.
    var approveWithKey: ((KeyAct, String) async throws -> Data)?
    /// Who is signed in, once KIFF has said; nil until then, and if it can't be read.
    @Published private(set) var me: Me?
    /// The balance, for the Plan card: tafs cloud's `plan_line` in `plan_tone`'s colour.
    @Published private(set) var balance: Usage.Balance?
    @Published var theme: ThemeChoice
    /// Coach's "Show suggestions", as tafs cloud last said it; nil until read, and the row is
    /// left out. While it changes, and why a change didn't go, as the iPad's `suggestions`.
    @Published var suggestions: Suggestions?
    @Published var suggestionsBusy = false
    @Published var suggestionsError: String?
    /// The AI-data consent, for the AI use row; nil until read, and the row is left out. The
    /// screen asked for from the row, and why the last answer didn't go.
    @Published var consent: TafsCloud.AIConsent?
    @Published var consentAsked: TafsCloud.AIConsent?
    @Published var consentBusy = false
    @Published var consentError: String?
    /// The time zone picker's list, for the search in `zoneQuery`; a save on its way, and why
    /// the last one didn't go all the way.
    @Published var zones: [TimeZoneChoice] = []
    @Published var savingZone = false
    @Published var zoneError: String?
    var zoneQuery = ""

    let account: AccountClient
    let cloud: CloudClient
    private let defaults: UserDefaults
    /// The owner confirms before the device key signs the time zone, as the iPad's
    /// `signer.sign(_:reason:)`: Touch ID, or the Mac's password.
    let confirm: (String) async throws -> Void

    init(account: AccountClient, cloud: CloudClient, defaults: UserDefaults = .standard,
         confirm: @escaping (String) async throws -> Void = NeedsYouModel.confirmOwnerForCore) {
        self.account = account
        self.cloud = cloud
        self.defaults = defaults
        self.confirm = confirm
        theme = ThemeChoice.saved(in: defaults)
    }

    /// Took who is signed in, as read again after the time zone changed.
    func took(_ me: Me) { self.me = me }

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

/// A page of Account, opened from its row: Back returns to the page before.
enum AccountPage: Equatable {
    case language, alerts, people, devices, kiffAccount, timeZone, files, chrome
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
    /// Files, every file the account's tafs delivered; nil leaves its row out.
    var files: FilesModel? = nil
    /// Account › Chrome: its row shows only once planque lists Chromes for this person (`chromes` read).
    var chrome: ChromesModel? = nil
    /// A taf's name by its KIFF agent, for what each group uses.
    var tafName: (String) -> String? = { _ in nil }
    /// Opens another screen of the sidebar from its row.
    let open: (Screen) -> Void
    let addThisMac: () -> Void
    /// This Mac's device key is a software key (no Secure Enclave): adding it with the phone
    /// still leaves it view-only, so it isn't offered, and the line says where approvals go.
    var softwareKey = false
    /// How this Mac's approvals are signed: How tafs works says where (`howItWorksKey`).
    var route: ApprovalRoute = .phoneOrPasskey
    /// Whether this person may use Coach, as the iPad's `mayUseCoach`: Coach's panel is theirs.
    var mayUseCoach = false
    /// The sample is open (`Sample`): Mode says Sample data, and the account's action is Clear the sample, which
    /// leaves it at once (nothing of anyone's is lost), as Windows' and the iPad's.
    var inSample = false
    let signOut: () -> Void
    /// The pages open over Account, the last on screen; none shows Account itself.
    @State var pages: [AccountPage] = []
    @State private var confirmingSignOut = false

    var body: some View {
        if let shown = pages.last {
            VStack(alignment: .leading, spacing: 0) {
                back
                opened(shown)
            }
            .background(Theme.background)
        } else {
            page
        }
    }

    @ViewBuilder private func opened(_ shown: AccountPage) -> some View {
        switch shown {
        case .language: LanguagePickerView()
        case .alerts: if let alerts { AlertsView(model: alerts) }
        case .people: if let people { PeopleView(model: people, me: model.me, tafName: tafName) }
        case .devices: DevicesView(model: devices, signOutThisMac: signOut, addThisMac: addsThisMac ? addThisMac : nil,
                                   managesPasskeys: model.me?.managesPasskeys ?? false)
        case .kiffAccount: KiffAccountPage(model: model, exportChats: exportChats, openZone: { pages.append(.timeZone) })
        case .timeZone: TimeZonePicker(model: model)
        case .files: if let files { FilesView(model: files, zone: model.me?.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current) }
        case .chrome: if let chrome { ChromesView(model: chrome) }
        }
    }

    /// Adding this Mac with the phone is offered while it's view-only with a Secure Enclave key.
    private var addsThisMac: Bool { model.me?.viewOnly == true && !softwareKey }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ScreenTitle(title: words("settings.title"), size: 34, rounded: false).padding(.top, 40)
                accountGroups
                settingsGroups
                aboutGroups
            }
            .padding(.horizontal, Look.inset)
            .padding(.bottom, Look.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task {
            await model.loadIfNeeded()
            await model.loadSettings()
        }
        .alert(words("settings.sign_out_of_kiff.title"), isPresented: $confirmingSignOut) {
            Button(words("settings.sign_out"), role: .destructive) { signOut() }
            Button(words("common.cancel"), role: .cancel) {}
        } message: {
            Text(words("settings.sign_out_of_kiff.body_device", ["device": words("device.mac")]))
        }
        .sheet(item: Binding(get: { model.consentAsked }, set: { if $0 == nil { model.notNowAI() } })) { consent in
            AIConsentSheet(model: model, consent: consent).environment(\.words, words)
        }
    }

    /// Your account, view only, People & apps, Plan, and Coach, as the iPad's list starts.
    @ViewBuilder private var accountGroups: some View {
        group(words("settings.your_account")) {
            row(words("settings.mode"), value: words(inSample ? "settings.mode_sample" : "settings.mode_kiff"))
            divider
            // The account's own page: its id, its time zone, Export and Delete account.
            AccountRow.link(words("settings.kiff_account"), value: model.me?.account ?? "") { pages.append(.kiffAccount) }
            // Who signed in, when it isn't the account's own name, as on the iPad.
            if let email = model.me?.signedInAs {
                divider
                row(words("settings.signed_in_as"), value: email)
            }
        }
        if model.me?.viewOnly == true { viewOnly }
        group(words("settings.people_apps")) {
            // People & groups first, as the iPad's list has it.
            if people != nil {
                link(words("people.title")) { pages.append(.people) }
                divider
            }
            link(words("settings.devices.title")) { pages.append(.devices) }
            divider
            // Chrome, after Devices, as the iPad's: only once planque offers Chromes.
            if let chrome, chrome.chromes != nil {
                link(words("chrome.title")) { pages.append(.chrome) }
                divider
            }
            link(words("connect.apps.title")) { open(.connectApps) }
            // Files: every file the account's tafs delivered, as the iPad's row after Connect apps.
            if files != nil {
                divider
                link(words("files.title")) { pages.append(.files) }
            }
        }
        // The Plan card always, as on the iPad: tafs cloud's plan line in its tone's
        // colour when it is read, else Plan & usage alone.
        group(words("settings.plan")) { plan }
        // What a new Coach conversation offers, as tafs cloud keeps it, where the iPad keeps it:
        // for the people who may use Coach, once it's read.
        if mayUseCoach, let shown = model.suggestions {
            group(words("coach.title")) { SuggestionsRow(model: model, shown: shown) }
        }
    }

    /// Exactly when KIFF says this session is view-only.
    private var viewOnly: some View {
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

    private var plan: some View {
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

    /// Alerts, the theme, the language, AI use, the time zone and Export, in the iPad's order.
    @ViewBuilder private var settingsGroups: some View {
        // Alerts, a row on its own, as the iPad's list has it.
        if alerts != nil {
            group(nil) { link(words("settings.alerts")) { pages.append(.alerts) } }
        }
        group(words("settings.theme_title")) { themes }
        // The language tafs's lines are in, by its own name, and the app's own list to
        // change it (Account › Language), not macOS's settings.
        group(words("settings.language_title")) {
            row(words("settings.language_title"), value: AppInfo.languageName(words.language))
            divider
            // In the accent, as the iPad's (SignInView.swift:364).
            AccountRow.link(words("settings.change_language"), color: Theme.amberText) { pages.append(.language) }
        }
        // The AI-data consent: given, with Withdraw; not given, its screen. tafs cloud's words.
        if let consent = model.consent, consent.drawable {
            group(nil) { AIConsentRow(model: model, consent: consent) }
        }
        // The account's time zone, which a Card's day ends by, and its picker.
        group(nil) { AccountRow.link(words("settings.time_zone_title"), value: model.zone) { pages.append(.timeZone) } }
        // Their own copy, for their rights of access and portability, as the iPad's.
        if let exportChats {
            group(nil) { ExportChatsRow(model: exportChats) }
            AccountRow.footer(words("export.own_chats_each_taf_coach"))
        }
    }

    private var themes: some View {
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

    /// Whether the new onboarding is on (`Onboarding.on`): then Legal opens How tafs works.
    var onboarding = Onboarding.on
    @State private var showingHowItWorks = false

    /// How tafs works, Legal, About and Sign out, as the iPad's list ends.
    @ViewBuilder private var aboutGroups: some View {
        group(words("sign_in.how_works")) {
            Text(words(route.howItWorksKey, ["device": words("device.mac")]))
                .font(.system(size: 14)).foregroundColor(Theme.soft).padding(.vertical, 12).fixedSize(horizontal: false, vertical: true)
        }
        group(words("settings.legal")) {
            // The new onboarding's How tafs works: the three cards again, and KIFF's and tafs's pages (`HowTafsWorksView`).
            if onboarding {
                action(words("onboarding.how_it_works"), color: Theme.amberText) { showingHowItWorks = true }
                divider
            }
            action(legal(words("settings.terms")), color: Theme.amberText) { Self.openPage(LegalPages.terms(words.language)) }
            divider
            action(legal(words("settings.privacy_policy")), color: Theme.amberText) { Self.openPage(LegalPages.privacy(words.language)) }
        }
        Color.clear.frame(height: 0).sheet(isPresented: $showingHowItWorks) {
            HowTafsWorksView(chromeOffered: chrome?.chromes != nil) { showingHowItWorks = false }.inLanguage(words).frame(minWidth: 620, minHeight: 640)
        }
        group(words("settings.about")) {
            row(words("settings.version"), value: AppInfo.version(Bundle.main.infoDictionary ?? [:]))
            divider
            Text(words("home.tagline")).font(.system(size: 17)).foregroundColor(Theme.dim).padding(.vertical, 12)
        }
        group(words("settings.account_actions")) {
            if inSample {
                // The sample holds nothing of anyone's: it's left at once, back to the welcome.
                action(words("settings.clear_sample"), color: Theme.no) { signOut() }
            } else {
                // Confirmed first, so a stray click never ends the session.
                action(words("settings.sign_out"), color: Theme.no) { confirmingSignOut = true }
            }
        }
    }

    /// The legal pages open in the app's language where kiff.dev has them (`LegalPages`); in any
    /// other language the label says the page is in English.
    private func legal(_ label: String) -> String {
        LegalPages.saysEnglish(words.language) ? words("settings.legal_in_english", ["label": label]) : label
    }

    /// Only tafs' own pages on kiff.dev are opened from here.
    static func openPage(_ address: String) {
        guard let url = URL(string: address), url.scheme == "https", url.host == "kiff.dev" else { return }
        NSWorkspace.shared.open(url)
    }

    private func group<Content: View>(_ title: String?, @ViewBuilder _ content: () -> Content) -> some View {
        AccountGroup(title, content: content)
    }

    /// Back to the page before, as the iPad's navigation bar does: the KIFF account page from
    /// its time zone, else Account.
    private var back: some View {
        let before: AccountPage? = pages.count > 1 ? pages[pages.count - 2] : nil
        return Button { _ = pages.popLast() } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                Text(words(before == .kiffAccount ? "settings.kiff_account" : "settings.title")).font(.system(size: 14))
            }
            .foregroundColor(Theme.amberText).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Look.inset).padding(.top, 18)
    }

    private var divider: some View { AccountRow.divider }
    private var chevron: some View { AccountRow.chevron }

    private func row(_ title: String, value: String) -> some View { AccountRow.value(title, value) }

    private func link(_ title: String, _ action: @escaping () -> Void) -> some View { AccountRow.link(title, action) }

    private func action(_ title: String, color: Color, _ action: @escaping () -> Void) -> some View {
        AccountRow.action(title, color: color, action)
    }
}

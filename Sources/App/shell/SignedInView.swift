import SwiftUI

/// The window of a signed-in Mac: the sidebar, with each built screen in its place.
struct SignedInView: View {
    @Environment(\.words) private var words
    @StateObject private var needsYou: NeedsYouModel
    @StateObject private var devices: DevicesModel
    @StateObject private var people: PeopleModel
    @StateObject private var accountHalt: HaltModel
    @StateObject private var exportChats: ExportChatsModel
    @StateObject private var accountModel: AccountModel
    @StateObject private var record: RecordModel
    @StateObject private var overview: OverviewModel
    @StateObject private var calendar: CalendarModel
    @StateObject private var usage: UsageModel
    @StateObject private var connect: ConnectAppsModel
    @StateObject private var coach: CoachModel
    @StateObject private var alerts: AlertsModel
    @State private var selection: Screen = .overview
    /// The screen shown last, and the one Coach opened over: Coach's Back returns there.
    @State private var shown: Screen = .overview
    @State private var beforeCoach: Screen = .overview
    /// The taf whose page is open, by its agent, and its chat.
    @State private var openTaf: String?
    @State private var tafChat: CoachModel?
    @State private var tafPages: TafPagesModel?
    /// What this person may do with each taf, as KIFF says, by KIFF agent.
    @State private var access: [String: Access] = [:]
    private let cloud: CloudClient
    private let streamer: LineStream?
    @State private var announced = Announced()
    private let notifier = Notifier()
    private let account: AccountClient
    private let signedOut: () -> Void
    private let addThisMac: () -> Void
    private let route: ApprovalRoute
    /// How often the calls waiting are read again while the window is open.
    static let refreshEvery: TimeInterval = 30

    init(account: AccountClient, cloud: CloudClient, route: ApprovalRoute, streamer: LineStream? = nil, signedOut: @escaping () -> Void,
         addThisMac: @escaping () -> Void = {}) {
        self.account = account
        self.cloud = cloud
        self.streamer = streamer
        self.signedOut = signedOut
        self.addThisMac = addThisMac
        self.route = route
        _needsYou = StateObject(wrappedValue: NeedsYouModel(account: account, route: route))
        _devices = StateObject(wrappedValue: DevicesModel(account: account))
        _people = StateObject(wrappedValue: PeopleModel(account: account))
        _accountHalt = StateObject(wrappedValue: HaltModel(cloud: cloud, taf: nil))
        _exportChats = StateObject(wrappedValue: ExportChatsModel(cloud: cloud))
        _accountModel = StateObject(wrappedValue: AccountModel(account: account, cloud: cloud))
        _record = StateObject(wrappedValue: RecordModel(cloud: cloud))
        _overview = StateObject(wrappedValue: OverviewModel(cloud: cloud))
        _calendar = StateObject(wrappedValue: CalendarModel(cloud: cloud))
        _usage = StateObject(wrappedValue: UsageModel(cloud: cloud))
        _connect = StateObject(wrappedValue: ConnectAppsModel(cloud: cloud))
        _coach = StateObject(wrappedValue: CoachModel(cloud: cloud, streamer: streamer))
        // Alerts are kept per account, as the iPad keys them by tenant.
        _alerts = StateObject(wrappedValue: AlertsModel(account: account.session.tenant))
    }

    var body: some View {
        // Every choice in the sidebar closes the taf's page, the screen already open too.
        let choosing = Binding(get: { selection }, set: { selection = $0; openTaf = nil })
        ShellView(selection: choosing, needsYou: needsYou.count, tafs: overview.tafs, noTafsLine: overview.hasNoTafs ? overview.noTafsLine : nil,
                  held: heldRows, tafPage: tafPage, openTaf: openTaf, open: open,
                  accountLine: accountModel.me?.email ?? accountModel.me?.account, screen: { screen in
            switch screen {
            case .needsYou: return AnyView(NeedsYouView(model: needsYou, tafs: overview.tafs, answersHolds: accountModel.me?.answersHolds ?? true,
                                                        answered: { await needsYou.load(); await readTafs() }))
            case .overview: return AnyView(OverviewView(model: overview, held: heldRows, openNeedsYou: { selection = .needsYou }, openTaf: open, halt: (accountModel.me?.managesCards ?? true) ? accountHalt : nil, halted: { await readTafs() },
                                                        mayUseCoach: mayUseCoach, ownWords: startNewTaf, hand: handToCoach))
            case .record: return AnyView(RecordView(model: record, tafs: overview.tafs))
            case .calendar: return AnyView(CalendarView(model: calendar))
            case .usage: return AnyView(UsageView(model: usage))
            case .connectApps: return AnyView(ConnectAppsView(model: connect, openCoach: { selection = .coach }))
            case .coach: return AnyView(CoachView(model: coach, canApprove: false,
                                                  openTaf: { agent in if let taf = overview.tafs.first(where: { $0.id == agent }) { open(taf) } else { selection = .overview } },
                                                  listed: Set(overview.tafs.map(\.id)), openUsage: { selection = .usage }, close: closeCoach))
            case .account: return AnyView(accountScreen)
            }
        }, startNewTaf: startNewTaf, openCoach: openCoach)
        .onAppear {
            notifier.opened = { selection = .needsYou }
            notifier.account = account.session.tenant
        }
        // A screen chosen from elsewhere (a notification) closes it too. Coach remembers the
        // screen it opened over, for its Back.
        .onChange(of: selection) { screen in
            openTaf = nil
            if screen == .coach, shown != .coach { beforeCoach = shown }
            shown = screen
        }
        // Who is signed in is read once, whatever screen is open.
        .task { await accountModel.load() }
        .task {
            // KIFF's and tafs cloud's lists are read again while the window is open.
            while !Task.isCancelled {
                await needsYou.load()
                // The tafs, for the sidebar and the Overview: read once here, and again with each round,
                // so a taf made in Coach shows without opening the Overview.
                await readTafs()
                if case .loaded(let calls) = needsYou.state {
                    notifier.announce(announced.new(in: calls).map { Announcement($0, words: words) })
                }
                try? await Task.sleep(nanoseconds: UInt64(Self.refreshEvery * 1_000_000_000))
            }
        }
    }

    /// The tafs, then what this person may do with each, as the iPad's `refresh()` with its
    /// `refreshAccess` (AppModel.swift:1894-1896, 1118-1122): access decides Halt, so it's read
    /// with the list, once the list has read. A read that fails keeps what was read.
    private func readTafs() async {
        await overview.load()
        // Home's steps for Needs you, as the iPad's `show` takes them with each read.
        if case .loaded(let page) = overview.state { needsYou.showSteps(page.yourSteps) }
        guard case .loaded = overview.state, let read = try? await account.myAccess() else { return }
        access = read
    }

    /// The calls held for the person, for the sidebar, each with its taf's name.
    private var heldRows: [HeldRow] {
        guard case .loaded(let calls) = needsYou.state else { return [] }
        return calls.map { HeldRow($0, tafs: overview.tafs) }
    }

    /// Opens a taf's page, with its own chat. An agent tafs doesn't run has no page.
    private func open(_ taf: Home.Taf) {
        guard let id = taf.tafID else { return }
        tafChat = CoachModel(cloud: cloud, taf: Coach(id: id, name: taf.name), streamer: streamer)
        tafPages = TafPagesModel(cloud: cloud, taf: id)
        openTaf = taf.id
    }

    /// Closes Coach, back to the screen it opened over, as the iPad's Coach mode's Back.
    private func closeCoach() {
        openTaf = nil
        selection = beforeCoach == .coach ? .overview : beforeCoach
    }

    /// The sidebar's Coach, as the iPad's `openCoach` (AppModel.swift:6767-6778): it only opens
    /// Coach. Coach closes from its own Back (Esc too).
    private func openCoach() {
        openTaf = nil
        selection = .coach
    }

    /// Start a new taf, as the iPad's `startNewTaf` (AppModel.swift:6801-6804): a new
    /// conversation in Coach, so Coach mode's start shows, whether Coach was open or not. The
    /// sidebar's + and Own words both come here.
    private func startNewTaf() {
        coach.startNewTaf()
        openTaf = nil
        selection = .coach
    }

    /// Whether this person may use Coach, as the iPad's `mayUseCoach`: KIFF's answer for Setup,
    /// else an account admin.
    private var mayUseCoach: Bool {
        Access.mayUseCoach(setup: access["setup"], capabilities: accountModel.me?.capabilities)
    }

    /// A recipe handed to Coach from the Overview, as the iPad's `handRecipeToCoach`
    /// (AppModel.swift:7274-7280): its words in Coach's box, to edit and send. Nothing is sent.
    private func handToCoach(_ recipe: Recipes.Recipe) {
        guard mayUseCoach else { return }
        coach.draft = recipe.say
        selection = .coach
    }

    /// Plan & usage in place of the taf's page, as the iPad's `usageRequested` from a health fix.
    static func showUsage(openTaf: inout String?, selection: inout Screen) {
        openTaf = nil
        selection = .usage
    }

    private var tafPage: AnyView? {
        guard let openTaf, let chat = tafChat, let taf = overview.tafs.first(where: { $0.id == openTaf }) else { return nil }
        return AnyView(TafView(taf: taf, chat: chat, pages: tafPages, manages: Access.manages(access[taf.id]),
                               halted: { await readTafs() },
                               // Plan & usage in place of the taf's page.
                               openUsage: { Self.showUsage(openTaf: &self.openTaf, selection: &self.selection) },
                               shareLine: ShareLine(agent: taf.kiffAgent, account: account, people: people, email: accountModel.me?.email)).id(taf.id))
    }

    private var accountScreen: some View {
        AccountView(model: accountModel, devices: devices, people: people, exportChats: exportChats, alerts: alerts,
                    tafName: { agent in overview.tafs.first { $0.id == agent }?.name },
                    open: { selection = $0 }, addThisMac: addThisMac, signOut: {
            // No answer outlives the session it was started in.
            needsYou.cancelAnswers()
            Task {
                // Ended at KIFF first; this Mac forgets its session either way.
                try? await account.signOut()
                // What's still on its way in a chat is the session before's.
                coach.signedOut()
                tafChat?.signedOut()
                signedOut()
            }
        })
    }
}

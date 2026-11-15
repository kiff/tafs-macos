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
    /// Run now for every taf, kept while signed in, as the iPad's app model keeps it.
    @StateObject private var runs: RunNowModel
    @StateObject private var coach: CoachModel
    @StateObject private var alerts: AlertsModel
    @State private var selection: Screen = .overview
    /// The taf whose page is open, by its agent, and its chat.
    @State private var openTaf: String?
    @State private var tafChat: CoachModel?
    @State private var tafPages: TafPagesModel?
    /// What this person may do with each taf, as KIFF says, by KIFF agent.
    @State private var access: [String: Access] = [:]
    /// A job's sheet, from the strip; the gallery, and what was chosen in it, acted on once it
    /// has closed (HomeSplitView.swift:86-90).
    @State private var openRecipe: Recipes.Recipe?
    @State private var showingGallery: GalleryMode?
    @State private var galleryChoice: GalleryChoice?
    /// Each taf's doors, one model per taf, as the iPad's `doors(for:)`.
    @StateObject private var doorModels = DoorModels()
    /// The tab a taf's page opens on.
    @State private var tafTab: TafView.Tab = .chat
    private let cloud: CloudClient
    private let streamer: LineStream?
    @State private var announced = Announced()
    private let notifier = Notifier()
    private let account: AccountClient
    private let signedOut: () -> Void
    private let addThisMac: () -> Void
    /// This Mac's device key is a software key: pairing it again with the phone gives no more.
    private let softwareKey: Bool
    private let route: ApprovalRoute
    /// How often the calls waiting are read again while the window is open.
    static let refreshEvery: TimeInterval = 30

    /// planque, for the Setup read's proof: kept for this session, with this device's id once
    /// read, as the iPad's `planque` (its `deviceID` and `deviceLoader`).
    @State private var planque: PlanqueClient

    init(account: AccountClient, cloud: CloudClient, route: ApprovalRoute, streamer: LineStream? = nil, signedOut: @escaping () -> Void,
         addThisMac: @escaping () -> Void = {}, softwareKey: Bool = false) {
        self.account = account
        let planque = PlanqueClient()
        // As the iPad's `deviceLoader` (AppModel.swift:490-493): only a session with a key,
        // KIFF's `this_device`.
        planque.deviceLoader = { [account] in
            guard account.signMessage != nil else { return nil }
            return try? await account.thisDeviceID()
        }
        _planque = State(initialValue: planque)
        self.cloud = cloud
        self.streamer = streamer
        self.signedOut = signedOut
        self.addThisMac = addThisMac
        self.softwareKey = softwareKey
        self.route = route
        _needsYou = StateObject(wrappedValue: NeedsYouModel(account: account, route: route))
        _devices = StateObject(wrappedValue: DevicesModel(account: account))
        _people = StateObject(wrappedValue: PeopleModel(account: account))
        _accountHalt = StateObject(wrappedValue: HaltModel(cloud: cloud, taf: nil))
        _exportChats = StateObject(wrappedValue: ExportChatsModel(cloud: cloud))
        _accountModel = StateObject(wrappedValue: AccountModel(account: account, cloud: cloud))
        _record = StateObject(wrappedValue: RecordModel(cloud: cloud))
        // The list last read shows in the first frame, as the iPad's remembered list.
        _overview = StateObject(wrappedValue: OverviewModel(cloud: cloud, remembered: .standard))
        _calendar = StateObject(wrappedValue: CalendarModel(cloud: cloud))
        _usage = StateObject(wrappedValue: UsageModel(cloud: cloud))
        _connect = StateObject(wrappedValue: ConnectAppsModel(cloud: cloud))
        _runs = StateObject(wrappedValue: RunNowModel(cloud: cloud))
        _coach = StateObject(wrappedValue: CoachModel(cloud: cloud, streamer: streamer))
        // Alerts are kept per account, as the iPad keys them by tenant.
        _alerts = StateObject(wrappedValue: AlertsModel(account: account.session.tenant))
    }

    var body: some View {
        // Every choice in the sidebar closes the taf's page, the screen already open too.
        let choosing = Binding(get: { selection }, set: { selection = $0; openTaf = nil })
        ShellView(selection: choosing, needsYou: needsYou.count, tafs: overview.tafs, noTafsLine: overview.hasNoTafs ? overview.noTafsLine : nil,
                  held: heldRows, tafPage: tafPage, openTaf: openTaf, open: open,
                  accountLine: accountModel.me?.email ?? accountModel.me?.account,
                  gallery: overview.gallery, openGallery: { showingGallery = $0 }, openRecipe: { openRecipe = $0 }, newTaf: startNewTaf) { screen in
            switch screen {
            // A taf's knocks are answered on its Activity, so its row opens there.
            case .needsYou: return AnyView(NeedsYouView(model: needsYou, tafs: overview.tafs, answersHolds: accountModel.me?.answersHolds ?? true, openKnocks: { open($0, on: .activity) },
                                                        answered: { await needsYou.load(); await readTafs() }))
            case .overview: return AnyView(OverviewView(model: overview, held: heldRows, openNeedsYou: { selection = .needsYou }, openTaf: open, halt: (accountModel.me?.managesCards ?? true) ? accountHalt : nil, halted: { await readTafs() },
                                                        mayUseCoach: mayUseCoach, ownWords: { selection = .coach }, hand: handToCoach))
            case .record: return AnyView(RecordView(model: record, tafs: overview.tafs))
            case .calendar: return AnyView(CalendarView(model: calendar))
            case .usage: return AnyView(UsageView(model: usage))
            case .connectApps: return AnyView(ConnectAppsView(model: connect, openCoach: { selection = .coach }))
            case .coach: return AnyView(CoachView(model: coach, canApprove: false,
                                                  openTaf: { agent in if let taf = overview.tafs.first(where: { $0.id == agent }) { open(taf) } else { selection = .overview } },
                                                  listed: Set(overview.tafs.map(\.id)), openUsage: { selection = .usage }))
            case .account: return AnyView(accountScreen)
            }
        }
        .sheet(item: $openRecipe) { recipe in
            RecipeSheet(recipe: recipe, recipes: overview.sheetRecipes(for: recipe), canHand: mayUseCoach,
                        sampleLabel: overview.gallery?.sampleLabel, close: { openRecipe = nil }) {
                openRecipe = nil
                handToCoach(recipe)
            }
            .environment(\.words, words)
        }
        .sheet(item: $showingGallery, onDismiss: actOnGalleryChoice) { mode in
            if let gallery = overview.gallery {
                RecipeGallerySheet(gallery: gallery, mode: mode, labels: overview.recipes?.labels, canHand: mayUseCoach,
                                   choose: { galleryChoice = $0; showingGallery = nil }, close: { showingGallery = nil })
                    .environment(\.words, words)
            }
        }
        .onAppear {
            notifier.opened = { selection = .needsYou }
            notifier.account = account.session.tenant
            LaunchClock.mark("first window")
        }
        // A screen chosen from elsewhere (a notification) closes it too.
        .onChange(of: selection) { _ in openTaf = nil }
        // Who is signed in is read once, whatever screen is open.
        .task { await accountModel.load() }
        .task {
            // KIFF's and tafs cloud's lists are read again while the window is open.
            while !Task.isCancelled {
                // The held calls and the tafs side by side, as the iPad's `refresh`
                // (AppModel.swift:1815-1821): neither waits for the other. The tafs, for the
                // sidebar and the Overview, are read once here and again with each round, so a
                // taf made in Coach shows without opening the Overview; what this person may do
                // with each is read after the list, as there (`readTafs`).
                async let held: Void = needsYou.load()
                async let tafs: Void = readTafs()
                _ = await (held, tafs)
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

    /// This device's planque proof for a taf's Setup, as the iPad's `loadTafSetup`: the account's
    /// tenant, signed with the device key and no prompt (`signConfirmed`: it reads, it grants
    /// nothing); nil when it can't be made.
    private func setupProof() async -> String? {
        guard let sign = account.signMessage else { return nil }
        planque.tenant = account.session.tenant
        return try? await planque.grantsReadProof(signedBy: sign)
    }

    /// Opens a taf's page, with its own chat. An agent tafs doesn't run has no page.
    private func open(_ taf: Home.Taf) { open(taf, on: .chat) }

    private func open(_ taf: Home.Taf, on tab: TafView.Tab) {
        guard let id = taf.tafID else { return }
        tafTab = tab
        tafChat = CoachModel(cloud: cloud, taf: Coach(id: id, name: taf.name), streamer: streamer)
        tafPages = TafPagesModel(cloud: cloud, taf: id, proof: { await setupProof() }, runs: runs)
        openTaf = taf.id
    }

    /// Whether this person may use Coach, as the iPad's `mayUseCoach`: KIFF's answer for Setup,
    /// else an account admin.
    private var mayUseCoach: Bool {
        Access.mayUseCoach(setup: access["setup"], capabilities: accountModel.me?.capabilities)
    }

    /// Start a new taf, as the iPad's + New (HomeSplitView.swift:426-431): every ready-made job
    /// where tafs cloud sends the gallery; without it, Coach as before.
    private func startNewTaf() {
        if overview.gallery != nil { showingGallery = .create } else { selection = .coach }
    }

    /// What was chosen in the gallery, once it has closed, as the iPad's `actOnGalleryChoice`
    /// (HomeSplitView.swift:440-448): Coach opens over the Overview.
    private func actOnGalleryChoice() {
        guard let choice = galleryChoice else { return }
        galleryChoice = nil
        switch choice {
        case .recipe(let recipe): handToCoach(recipe)
        case .ownWords: selection = .coach
        }
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
                               openUsage: { Self.showUsage(openTaf: &self.openTaf, selection: &self.selection) }, me: accountModel.me,
                               doors: doorModels.model(for: taf, cloud: cloud), doorsOffered: !overview.doorsOffered.isEmpty,
                               myEmail: accountModel.me?.email,
                               shareLine: ShareLine(agent: taf.kiffAgent, account: account, people: people, email: accountModel.me?.email), tab: tafTab).id(taf.id))
    }

    private var accountScreen: some View {
        AccountView(model: accountModel, devices: devices, people: people, exportChats: exportChats, alerts: alerts,
                    tafName: { agent in overview.tafs.first { $0.id == agent }?.name },
                    open: { selection = $0 }, addThisMac: addThisMac, softwareKey: softwareKey, signOut: {
            // A list read still on its way keeps nothing from here.
            overview.endSession()
            // No answer outlives the session it was started in.
            needsYou.cancelAnswers()
            Task {
                // Ended at KIFF first; this Mac forgets its session, and the list kept with it,
                // either way.
                try? await account.signOut()
                // What's still on its way in a chat is the session before's.
                coach.signedOut()
                tafChat?.signedOut()
                signedOut()
            }
        })
    }
}

import SwiftUI

/// The window of a signed-in Mac: the sidebar, with each built screen in its place.
struct SignedInView: View {
    /// Whether the app is in front: back in front, the lists are read again.
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.words) private var words
    /// The one dictation for the signed-in app, as the iPad's `AppModel.dictation`
    /// (AppModel.swift:260): Coach's and each taf's chat share it, so only one listens.
    @StateObject private var dictation = Dictation()
    @StateObject private var needsYou: NeedsYouModel
    /// "Your brief", in Needs you's place once tafs cloud serves it.
    @StateObject private var brief: BriefModel
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
    /// The screen shown last, and the one Coach opened over: Coach's Back returns there.
    @State private var shown: Screen = .overview
    @State private var beforeCoach: Screen = .overview
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
    /// This Mac's device key, its public half (SPKI DER), for planque's enrolment.
    private let deviceKey: Data
    /// The credential of the security key that goes with this Mac (`SecurityKeyStore`), if any.
    private let securityKey: Data?
    /// The PIN sheet, while the security key is asked.
    @State private var pinSheet: PINSheetModel?
    /// How often the calls waiting are read again while the window is open.
    static let refreshEvery: TimeInterval = 30

    /// planque, for the Setup read's proof: kept for this session, with this device's id once
    /// read, as the iPad's `planque` (its `deviceID` and `deviceLoader`).
    @State private var planque: PlanqueClient

    init(account: AccountClient, cloud: CloudClient, route: ApprovalRoute, streamer: LineStream? = nil, signedOut: @escaping () -> Void,
         addThisMac: @escaping () -> Void = {}, softwareKey: Bool = false, deviceKey: Data = Data(), securityKey: Data? = nil,
         startOn: Screen = .overview) {
        self.account = account
        _selection = State(initialValue: startOn)
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
        self.deviceKey = deviceKey
        self.securityKey = securityKey
        self.route = route
        _needsYou = StateObject(wrappedValue: NeedsYouModel(account: account, route: route))
        _brief = StateObject(wrappedValue: BriefModel(cloud: cloud))
        _devices = StateObject(wrappedValue: DevicesModel(account: account))
        _people = StateObject(wrappedValue: PeopleModel(account: account))
        _accountHalt = StateObject(wrappedValue: HaltModel(cloud: cloud, taf: nil))
        _exportChats = StateObject(wrappedValue: ExportChatsModel(cloud: cloud))
        _accountModel = StateObject(wrappedValue: AccountModel(account: account, cloud: cloud))
        _record = StateObject(wrappedValue: RecordModel(cloud: cloud, account: account))
        // The list last read shows in the first frame, as the iPad's remembered list.
        _overview = StateObject(wrappedValue: OverviewModel(cloud: cloud, remembered: .standard))
        _calendar = StateObject(wrappedValue: CalendarModel(cloud: cloud))
        _usage = StateObject(wrappedValue: UsageModel(cloud: cloud, account: account))
        _connect = StateObject(wrappedValue: ConnectAppsModel(cloud: cloud))
        _runs = StateObject(wrappedValue: RunNowModel(cloud: cloud))
        _coach = StateObject(wrappedValue: CoachModel(cloud: cloud, streamer: streamer))
        // Alerts are kept per account, as the iPad keys them by tenant.
        _alerts = StateObject(wrappedValue: AlertsModel(account: account.session.tenant))
    }

    var body: some View {
        // Every choice in the sidebar closes the taf's page, the screen already open too.
        let choosing = Binding(get: { selection }, set: { selection = $0; openTaf = nil })
        ShellView(selection: choosing, needsYou: needsYou.count, needsYouTitle: brief.brief == nil ? nil : brief.tabTitle(words), tafs: overview.tafs, noTafsLine: overview.hasNoTafs ? overview.noTafsLine : nil,
                  held: heldRows, tafPage: tafPage, openTaf: openTaf, open: open,
                  accountLine: accountModel.me?.email ?? accountModel.me?.account,
                  gallery: overview.gallery, openGallery: { showingGallery = $0 }, openRecipe: { openRecipe = $0 }, newTaf: newTaf, screen: { screen in
            switch screen {
            // A taf's knocks are answered on its Activity, so its row opens there.
            case .needsYou: return AnyView(BriefScreen(model: brief, needsYou: NeedsYouView(model: needsYou, tafs: overview.tafs, answersHolds: accountModel.me?.answersHolds ?? true,
                                                                                            openKnocks: { open($0, on: .activity) }, answered: { await needsYou.load(); await readTafs() }),
                                                       beyond: briefBeyond, tafs: overview.tafs, zone: accountModel.me?.timeZone, startNextMove: mayUseCoach ? startNextMove : nil))
            case .overview: return AnyView(OverviewView(model: overview, held: heldRows, openNeedsYou: { selection = .needsYou }, openTaf: open, halt: (accountModel.me?.managesCards ?? true) ? accountHalt : nil, halted: { await readTafs() },
                                                        mayUseCoach: mayUseCoach, ownWords: startNewTaf, hand: handToCoach))
            case .record: return AnyView(RecordView(model: record, tafs: overview.tafs, timeZone: accountModel.me?.timeZone))
            case .calendar: return AnyView(CalendarView(model: calendar))
            case .usage: return AnyView(UsageView(model: usage, managesBilling: accountModel.me?.managesBilling ?? true))
            case .connectApps: return AnyView(ConnectAppsView(model: connect, openCoach: { selection = .coach }))
            case .coach: return AnyView(CoachView(model: coach, canApprove: false,
                                                  openTaf: { agent in if let taf = overview.tafs.first(where: { $0.id == agent }) { open(taf) } else { selection = .overview } },
                                                  listed: Set(overview.tafs.map(\.id)), openUsage: { selection = .usage }, mayUseCoach: mayUseCoach, start: coachStart, close: closeCoach, dictation: dictation,
                                                  hints: Dictating.hints(tafs: overview.tafs.map(\.name))))
            case .account: return AnyView(accountScreen)
            }
        }, startNewTaf: startNewTaf, openCoach: openCoach)
        .sheet(item: $pinSheet) { model in
            PINSheet(model: model).environment(\.words, words)
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
        // A screen chosen from elsewhere (a notification) closes it too. Coach remembers the
        // screen it opened over, for its Back.
        .onChange(of: selection) { screen in
            openTaf = nil
            if screen == .coach, shown != .coach { beforeCoach = shown }
            shown = screen
        }
        // Who is signed in is read once, whatever screen is open.
        .task { await accountModel.load() }
        // Any change of session (a sign-out, a pairing, a new sign-in) rebuilds this window:
        // what the old one started ends with it, as the iPad's `accountGeneration` bumps on
        // every account change (AppModel.swift:887, :1472).
        .onDisappear {
            coach.signedOut()
            tafChat?.signedOut()
            pinSheet?.cancel()
            brief.endSession()
        }
        .task {
            // KIFF's and tafs cloud's lists are read again while the window is open.
            while !Task.isCancelled {
                await readRound()
                try? await Task.sleep(nanoseconds: UInt64(Self.refreshEvery * 1_000_000_000))
            }
        }
        // Back in front, the lists are read again at once, as the iPad's `refresh()` when its
        // scene becomes active (TafsApp.swift:60-68), not only at the next round.
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await readRound() } }
        }
    }

    /// One round: the held calls and the tafs side by side, as the iPad's `refresh`
    /// (AppModel.swift:1815-1821): neither waits for the other. The tafs, for the sidebar and the
    /// Overview, are read with each round, so a taf made in Coach shows without opening the
    /// Overview; what this person may do with each is read after the list, as there (`readTafs`).
    private func readRound() async {
        async let held: Void = needsYou.load()
        async let tafs: Void = readTafs()
        // Your brief with each round, as the iPad's `refresh` reads it with the list.
        async let read: Void = brief.load()
        _ = await (held, tafs, read)
        if case .loaded(let calls) = needsYou.state {
            notifier.announce(announced.new(in: calls).map { Announcement($0, words: words) })
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

    /// What Needs you holds that the brief doesn't show, matched item by item (`BriefModel`):
    /// held calls and steps by their ids, and what the brief can't carry counted.
    private var briefBeyond: Int {
        guard case .loaded(let calls) = needsYou.state else { return 0 }
        return brief.needsYouBeyond(heldIDs: calls.map(\.id), stepIDs: needsYou.steps.map(\.handoff), others: needsYou.unproven.count)
    }

    /// The brief's next move, in Coach's box to edit and send, as the iPad's `startNextMove`.
    private func startNextMove(_ words: String) {
        guard mayUseCoach else { return }
        coach.draft = words
        selection = .coach
    }

    /// The calls held for the person, for the sidebar, each with its taf's name.
    private var heldRows: [HeldRow] {
        guard case .loaded(let calls) = needsYou.state else { return [] }
        return calls.map { HeldRow($0, tafs: overview.tafs) }
    }

    /// The session's security-key side, for what grants authority on this Mac: only on the security
    /// key's route (`ApprovalRoute.passkey`, given once `Features.macPasskeyApprovals` is on), with
    /// the key that goes with this Mac. Never the device key in its place.
    private var passkeySession: PasskeySession? {
        guard route == .passkey, let securityKey else { return nil }
        return PasskeySession(transport: account.transport, session: account.session, language: account.language,
                              approver: PasskeyApprover(authenticator: FidoKey(), credentialID: securityKey, sha256: PasskeyCrypto.sha256))
    }

    /// Coach's Start, on a Mac that may start it (`CoachStart.mayStart`); nil on one that can't
    /// approve, whose Coach says so and follows the start made on the phone.
    private var coachStart: (() async -> Void)? {
        guard CoachStart.mayStart(route: route, approval: passkeySession) else { return nil }
        return { await startCoach() }
    }

    /// Starts Coach on the security key's route, as Windows' `StartAsync`: Setup's draft approved
    /// by the key through the PIN sheet; then planque's calls and KIFF's mint signed by the device
    /// key with no prompt (`signConfirmed`). planque's signer is armed only inside the enrolment,
    /// after the approval and its account check, and cleared when it ends (`AppModel.swift:7569-7575`).
    @MainActor private func startCoach() async {
        guard let passkey = passkeySession else { return }
        let key = deviceKey, reason = words("coach.prompt.connect_tools_mac")
        await coach.startSetup(account: account, approval: passkey,
                               sign: { body in try await askSecurityKey { pin in try await passkey.signDraft(body, pin: pin) } },
                               confirm: { try await NeedsYouModel.confirmOwner(reason) },
                               enrol: { [planque, account] ended in
                                   planque.tenant = account.session.tenant
                                   planque.signer = account.signMessage
                                   planque.bodyHash = Signing.sha256Hex
                                   planque.transport = NetworkTransport(base: URL(string: PlanqueClient.baseURL)!)
                                   defer { planque.signer = nil }
                                   return await PlanqueEnrolment.enrol(planque: planque, account: account, deviceKey: key, ended: ended)
                               },
                               words: words)
    }

    /// Asks this Mac's security key through the PIN sheet: its PIN, then its touch, as many tries
    /// as the person makes; it answers once the key approved, or throws once the sheet is closed.
    @MainActor private func askSecurityKey<Answer>(_ ask: @escaping (SecurityKeyPIN) async throws -> Answer) async throws -> Answer {
        try await withCheckedThrowingContinuation { continuation in
            var answer: Answer?
            pinSheet = PINSheetModel(words: words, attempt: { pin in answer = try await ask(pin) },
                                     readTries: { try await FidoKey().triesLeft() },
                                     done: { error in
                                         pinSheet = nil
                                         if let error { continuation.resume(throwing: error) }
                                         else if let answer { continuation.resume(returning: answer) }
                                         else { continuation.resume(throwing: CancellationError()) }
                                     })
        }
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
    /// conversation in Coach, so Coach mode's start shows, whether Coach was open or not. Own
    /// words and the gallery's own words come here, and the sidebar's + without a gallery.
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

    /// Start a new taf, as the iPad's + New (`HomeSplitView.startNewTaf`, HomeSplitView.swift:434-438):
    /// every ready-made job where tafs cloud sends the gallery; without it, a new conversation in
    /// Coach (`startNewTaf`).
    private func newTaf() {
        if overview.gallery != nil { showingGallery = .create } else { startNewTaf() }
    }

    /// What was chosen in the gallery, once it has closed, as the iPad's `actOnGalleryChoice`
    /// (HomeSplitView.swift:440-448): Coach opens over the Overview.
    private func actOnGalleryChoice() {
        guard let choice = galleryChoice else { return }
        galleryChoice = nil
        switch choice {
        case .recipe(let recipe): handToCoach(recipe)
        case .ownWords: startNewTaf()
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
                               shareLine: ShareLine(agent: taf.kiffAgent, account: account, people: people, email: accountModel.me?.email),
                               dictation: dictation, tab: tafTab).id(taf.id))
    }

    private var accountScreen: some View {
        AccountView(model: accountModel, devices: devices, people: people, exportChats: exportChats, alerts: alerts,
                    tafName: { agent in overview.tafs.first { $0.id == agent }?.name },
                    open: { selection = $0 }, addThisMac: addThisMac, softwareKey: softwareKey, signOut: {
            // A list read still on its way keeps nothing from here.
            overview.endSession()
            brief.endSession()
            // No answer outlives the session it was started in.
            needsYou.cancelAnswers()
            usage.cancelAnswers()
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

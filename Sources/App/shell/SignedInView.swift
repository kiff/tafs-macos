import CryptoKit
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
    /// Files, the account's: Account's row opens them.
    @StateObject private var files: FilesModel
    /// Account › Chrome, on planque's safe routes.
    @StateObject private var chromes: ChromesModel
    @StateObject private var accountModel: AccountModel
    @StateObject private var record: RecordModel
    @StateObject private var overview: OverviewModel
    @StateObject private var calendar: CalendarModel
    @StateObject private var usage: UsageModel
    @StateObject private var connect: ConnectAppsModel
    /// Run now for every taf, kept while signed in, as the iPad's app model keeps it.
    @StateObject private var runs: RunNowModel
    @StateObject private var coach: CoachModel
    /// Coach mode over the window, as the iPad's `CoachPanel`: open or not, its width and ⤢.
    @StateObject private var panel = CoachPanelModel()
    @StateObject private var alerts: AlertsModel
    /// The screen under Coach: Coach opens over it, never in its place.
    @State private var selection: Screen = .overview
    /// The taf whose page is open, by its agent, and its chat.
    @State private var openTaf: String?
    /// A discard tafs cloud refused while KIFF still held Cards in force: those Cards, by agent, revoked on the next try.
    @State private var discardCardsLeft: [String: [String]] = [:]
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
    /// The sample is open (`Sample`, `SampleTransport`): Account says so, and Clear the sample leaves it.
    private let inSample: Bool
    /// The sample's next round (`SampleTransport.playNext`); nil outside the sample.
    private let playNextSample: (() -> Bool)?
    /// This Mac's device key, its public half (SPKI DER), for planque's enrolment.
    private let deviceKey: Data
    /// The credential of the security key that goes with this Mac (`SecurityKeyStore`), if any.
    private let securityKey: Data?
    /// The PIN sheet, while the security key is asked.
    @State private var pinSheet: PINSheetModel?
    /// What's read again while the window is open, and when (`WindowReads`, tafs docs/scale.md).
    @State private var reads = WindowReads()

    /// planque, for the Setup read's proof: kept for this session, with this device's id once
    /// read, as the iPad's `planque` (its `deviceID` and `deviceLoader`).
    @State private var planque: PlanqueClient

    init(account: AccountClient, cloud: CloudClient, route: ApprovalRoute, streamer: LineStream? = nil, signedOut: @escaping () -> Void,
         addThisMac: @escaping () -> Void = {}, softwareKey: Bool = false, deviceKey: Data = Data(), securityKey: Data? = nil,
         startOn: Screen = .overview, inSample: Bool = false, playNextSample: (() -> Bool)? = nil) {
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
        self.inSample = inSample
        self.playNextSample = playNextSample
        _brief = StateObject(wrappedValue: BriefModel(cloud: cloud))
        _devices = StateObject(wrappedValue: DevicesModel(account: account))
        _people = StateObject(wrappedValue: PeopleModel(account: account))
        _accountHalt = StateObject(wrappedValue: HaltModel(cloud: cloud, taf: nil))
        _exportChats = StateObject(wrappedValue: ExportChatsModel(cloud: cloud))
        _files = StateObject(wrappedValue: FilesModel(cloud: cloud))
        // Account › Chrome: planque's safe routes, each signed by the device key for that one request; the enrolment's
        // armed signer is never used for them (`PlanqueClient.Safe`).
        let safePlanque = { [account, planque] () -> PlanqueClient in
            planque.tenant = account.session.tenant
            if planque.transport == nil { planque.transport = NetworkTransport(base: URL(string: PlanqueClient.baseURL)!) }
            return planque
        }
        _chromes = StateObject(wrappedValue: ChromesModel(read: { [account] in
            guard let sign = account.signMessage else { return nil }
            return try await safePlanque().chromes(signedBy: sign)
        }, unpair: { [account] id in
            guard let sign = account.signMessage else { throw PlanqueClient.PlanqueError.notSigning }
            _ = try await safePlanque().safe(.unpairChrome(id), signedBy: sign)
        }))
        _accountModel = StateObject(wrappedValue: AccountModel(account: account, cloud: cloud))
        _record = StateObject(wrappedValue: RecordModel(cloud: cloud, account: account))
        // The list last read shows in the first frame, as the iPad's remembered list.
        // The list last read is kept for the next launch, but never the sample's: nothing of it is kept.
        _overview = StateObject(wrappedValue: OverviewModel(cloud: cloud, remembered: inSample ? nil : .standard))
        _calendar = StateObject(wrappedValue: CalendarModel(cloud: cloud))
        _usage = StateObject(wrappedValue: UsageModel(cloud: cloud, account: account))
        _connect = StateObject(wrappedValue: ConnectAppsModel(cloud: cloud, connections: ConnectionsSource(account: account, planque: planque, transport: NetworkTransport(base: URL(string: PlanqueClient.baseURL)!))))
        _runs = StateObject(wrappedValue: RunNowModel(cloud: cloud))
        // Coach's thread is read with this device's planque proof, as the iPad's `loadSetupThread`, so
        // tafs cloud marks its approval and sign-in cards (`wider`). Signed with no prompt: it reads only.
        let coachProof: () async -> String? = { [account, planque] in
            guard let sign = account.signMessage else { return nil }
            planque.tenant = account.session.tenant
            return try? await planque.grantsReadProof(signedBy: sign)
        }
        _coach = StateObject(wrappedValue: CoachModel(cloud: cloud, streamer: streamer, proof: coachProof))
        // Set aside sends the same read of this device's connections, as the iPad's `setAsideCoach`.
        _needsYou = StateObject(wrappedValue: NeedsYouModel(account: account, route: route, cloud: cloud, proof: coachProof))
        // Alerts are kept per account, as the iPad keys them by tenant.
        _alerts = StateObject(wrappedValue: AlertsModel(account: account.session.tenant, inSample: inSample))
    }

    var body: some View {
        // Coach over the window's screen, as the iPad's Coach mode: the screen stays in view.
        CoachPanelHost(panel: panel, leading: ShellView.sidebarWidth) { shell } coach: { coachPanel }
        .frame(minWidth: ShellView.minimumSize.width, minHeight: ShellView.minimumSize.height)
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
        // A screen chosen from elsewhere (a notification) closes it too. Coach, over it, stays.
        .onChange(of: selection) { _ in openTaf = nil }
        // Who is signed in is read once, whatever screen is open.
        .task { await accountModel.load() }
        // Account's Chrome row shows once planque lists Chromes: read once with the window.
        .task { await chromes.load() }
        // Signing another device out is approved by this Mac's security key, when it has one (kiff/cloud#96).
        .onAppear {
            devices.approveWithKey = approveWithKey
            accountModel.approveWithKey = approveWithKey
            accountHalt.approveWithKey = approveWithKey
            // A reported payment halts its taf: the list is read again.
            record.halted = { await readTafs() }
            // The pictures a paired Chrome kept before a step: planque's safe reads, signed by the device key.
            record.chromeShots = { [account, safePlanque] operation in
                guard let sign = account.signMessage else { return [] }
                return try await safePlanque.chromeShots(operation: operation, signedBy: sign)
            }
            record.chromeShot = { [account, safePlanque] step in
                guard let sign = account.signMessage else { return .failed }
                return await safePlanque.chromeShot(step: step, signedBy: sign, sha256: { Data(SHA256.hash(data: $0)) })
            }
            // An API door's Reopen, Revoke and Remove are approved on the key, as a removal is.
            doorModels.signWithKey = signWithKey
            // A Slack door's subscription is stopped on planque's safe route, signed by the device key, before the door goes.
            doorModels.unsubscribe = { [account, safePlanque] grant, trigger in
                guard let sign = account.signMessage else { throw PlanqueClient.PlanqueError.notSigning }
                _ = try await safePlanque.safe(.deleteTrigger(grant: grant, trigger: trigger), signedBy: sign)
            }
            needsYou.answerWithKey = answerWithKey
            // "Allow this from now on" confirms KIFF's draft on the key, as any act that grants authority.
            needsYou.approveWithKey = approveWithKey
        }
        // Any change of session (a sign-out, a pairing, a new sign-in) rebuilds this window:
        // what the old one started ends with it, as the iPad's `accountGeneration` bumps on
        // every account change (AppModel.swift:887, :1472).
        .onDisappear {
            coach.signedOut()
            tafChat?.signedOut()
            pinSheet?.cancel()
            brief.endSession()
            connect.endSession()
        }
        .task {
            // KIFF's and tafs cloud's lists are read again while the window is open, each on its own schedule, with jitter,
            // and not after 10 minutes in the background (`WindowReads`).
            while !Task.isCancelled {
                switch reads.plan(now: Date()) {
                case .all: await readRound()
                case .held: await readHeld()
                case .nothing: break
                }
                try? await Task.sleep(nanoseconds: UInt64(WindowReads.wait(random: Double.random(in: 0...1)) * 1_000_000_000))
            }
        }
        // Back in front, the lists are read again at once, as the iPad's `refresh()` when its
        // scene becomes active (TafsApp.swift:60-68), not only at the next round.
        .onChange(of: scenePhase) { phase in
            if reads.background(phase != .active, now: Date()) == .all { Task { await readRound() } }
        }
    }

    /// The window's sidebar and the screen chosen in it, under Coach.
    private var shell: some View {
        // Every choice in the sidebar closes the taf's page, the screen already open too.
        let choosing = Binding(get: { selection }, set: { selection = $0; openTaf = nil })
        return ShellView(selection: choosing, needsYou: needsYou.needsYouCount(onScreen: coachChatOnScreen), needsYouTitle: brief.brief == nil ? nil : brief.tabTitle(words), tafs: overview.listedTafs, noTafsLine: overview.hasNoTafs ? overview.noTafsLine : nil,
                  sharedWithMe: { Access.sharedWithMe(access[$0.id]) },
                  settingUp: overview.settingUpList, discard: { await discardSettingUp($0) },
                  held: heldRows, tafPage: tafPage, openTaf: openTaf, open: open,
                  accountLine: accountModel.me?.email ?? accountModel.me?.account,
                  unreachable: overview.unreachable, retrying: overview.retrying, balance: accountModel.balance,
                  gallery: overview.gallery, openGallery: { showingGallery = $0 }, openRecipe: { openRecipe = $0 }, newTaf: newTaf, screen: { screen in
            switch screen {
            // A taf's knocks are answered on its Activity, so its row opens there.
            case .needsYou: return AnyView(BriefScreen(model: brief, needsYou: NeedsYouView(model: needsYou, tafs: overview.tafs, answersHolds: accountModel.me?.answersHolds ?? true, managesCards: accountModel.me?.managesCards ?? true, allowIsLive: accountModel.me?.allowIsLive ?? false,
                                                                                            openKnocks: { open($0, on: .activity) }, answered: { await needsYou.load(); await readTafs() },
                                                                                            mayUseCoach: mayUseCoach, openCoach: openCoachWaiting, setAsideDone: { coach.setAside(chats: $0); await readTafs() }),
                                                       beyond: briefBeyond, tafs: overview.tafs, zone: accountModel.me?.timeZone, startNextMove: mayUseCoach ? startNextMove : nil))
            case .overview: return AnyView(OverviewView(model: overview, held: heldRows, openNeedsYou: { selection = .needsYou }, openTaf: open,
                                                        needsCount: needsYou.needsYouCount(), needsWords: NeedsYouCount.words(needsYou.countParts(), words),
                                                        people: people, manages: { Access.manages(access[$0.id]) }, readShares: { [account] in try await account.shares(agent: $0) },
                                                        mayUseCoach: mayUseCoach, ownWords: startNewTaf, hand: handToCoach,
                                                        chromeOffered: chromes.chromes != nil, discard: { await discardSettingUp($0) },
                                                        // The sample's next round, then every list read again, as after any act here.
                                                        playNextSample: playNextSample.map { play in { if play() { Task { await readRound() } } } }))
            case .record: return AnyView(RecordView(model: record, tafs: overview.tafs, timeZone: accountModel.me?.timeZone))
            case .calendar: return AnyView(CalendarView(model: calendar, tafs: overview.tafs, open: { open($0) }))
            case .usage: return AnyView(UsageView(model: usage, managesBilling: accountModel.me?.managesBilling ?? true,
                                                  tafName: { id in overview.tafs.first { $0.tafID == id }?.name }))
            case .connectApps: return AnyView(ConnectAppsView(model: connect, tafs: overview.tafs, connectable: overview.tafs.filter { $0.tafID != nil && Access.manages(access[$0.id]) }, managesCards: managesCards, openCoach: openCoach))
            // Coach is never a screen of its own: it opens over the one chosen (`coachPanel`).
            case .coach: return nil
            case .account: return AnyView(accountScreen)
            }
        }, startNewTaf: startNewTaf, openCoach: openCoach,
                  coachOpen: panel.open,
                  haltAll: AccountHalt.shown(managesCards: managesCards, tafs: overview.tafs, halt: accountHalt.halt.state) ? accountHalt : nil, halted: { await readTafs() })
    }

    /// Coach, in its panel: Back closes it, ⤢ fills the window. A hand-over's taf, and Plan &
    /// usage, open under it with Coach closed, as the iPad's `requestedTaf` with `coachOpen = false`.
    private var coachPanel: some View {
        CoachView(model: coach, canApprove: false, openTaf: openHandedOver,
                  listed: Set(overview.tafs.map(\.id)), tafCount: overview.tafs.count, managesCards: accountModel.me?.managesCards ?? true,
                  openUsage: { panel.close(); selection = .usage }, mayUseCoach: mayUseCoach, start: coachStart, close: closeCoach,
                  fullScreen: $panel.full, tafs: overview.tafs,
                  managesTaf: { id in overview.tafs.first { $0.tafID == id }.map { Access.manages(access[$0.id]) } ?? false },
                  versions: versionsModel, dictation: dictation,
                  hints: Dictating.hints(tafs: overview.tafs.map(\.name)))
    }

    /// A hand-over's See it on: the taf's page under Coach, which closes; the Overview when the
    /// list doesn't have it.
    private func openHandedOver(_ agent: String?) {
        panel.close()
        if let taf = overview.tafs.first(where: { $0.id == agent }) { open(taf) } else { openTaf = nil; selection = .overview }
    }

    /// A taf's versions, for a new version's See version in Coach.
    private func versionsModel(_ tafID: String) -> TafPagesModel? {
        TafPagesModel(cloud: cloud, taf: tafID, proof: { await setupProof() }, runs: runs)
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
        announceHeld()
    }

    /// The held calls alone, between the lists' reads: what Needs you and its alerts wait on.
    private func readHeld() async {
        await needsYou.load()
        announceHeld()
    }

    private func announceHeld() {
        // The sample's held calls are no one's: macOS is never asked to alert for them.
        guard !inSample else { return }
        if case .loaded(let calls) = needsYou.state {
            notifier.announce(announced.new(in: calls).map { Announcement($0, words: words) })
        }
    }

    /// The tafs, then what this person may do with each, as the iPad's `refresh()` with its
    /// `refreshAccess` (AppModel.swift:1894-1896, 1118-1122): access decides Halt, so it's read
    /// with the list, once the list has read. A read that fails keeps what was read.
    private func readTafs() async {
        await overview.load()
        // Home's steps, Coach's waiting chats and its count for Needs you, as the iPad's `show` takes them with each read.
        if case .loaded(let page) = overview.state { needsYou.show(page) }
        // The account's halt, read with the list when no taf runs, for the sidebar's Halt all.
        if AccountHalt.readsWithList(managesCards: managesCards, tafs: overview.tafs) { await accountHalt.refresh() }
        guard case .loaded = overview.state, let read = try? await account.myAccess() else { return }
        access = read
    }

    /// What Needs you holds that the brief doesn't show, matched item by item (`BriefModel`):
    /// held calls and steps by their ids, and what the brief can't carry counted.
    private var briefBeyond: Int {
        guard case .loaded(let calls) = needsYou.state else { return 0 }
        let parts = needsYou.countParts()
        return brief.needsYouBeyond(heldIDs: calls.map(\.id), stepIDs: needsYou.steps.map(\.handoff), others: parts.unproven + parts.cardUnits + parts.coachWaiting)
    }

    /// Who manages the account's Cards (KIFF's `cards.manage`): Halt all is theirs.
    private var managesCards: Bool { accountModel.me?.managesCards ?? true }

    /// Coach's chat on screen, which Needs you leaves out, as the iPad's `coachChatOnScreen`.
    private var coachChatOnScreen: String? { panel.open ? coach.shownSession : nil }

    /// Needs you's Open Coach, as the iPad's `openCoachWaiting`: Coach on that chat; Coach alone without one.
    private func openCoachWaiting(_ waiting: CoachWaiting) {
        guard mayUseCoach else { return }
        let session = waiting.session
        let chat = coach
        Task { await panel.openWaiting(session, in: chat) }
    }

    /// The brief's next move, in Coach's box to edit and send, as the iPad's `startNextMove`.
    private func startNextMove(_ words: String) {
        guard mayUseCoach else { return }
        panel.hand(words, to: coach)
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
                               confirm: { try await NeedsYouModel.confirmOwnerForCore(reason) },
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

    /// One act approved by this Mac's security key (`KeyAct`, `PasskeySession.approved`), named in the PIN sheet; nil
    /// when this Mac has no key on the security key's route, so the act says to approve elsewhere, as before.
    /// planque for its safe routes, each signed by the device key for that one request, as Account › Chrome's.
    private var safePlanque: PlanqueClient {
        planque.tenant = account.session.tenant
        if planque.transport == nil { planque.transport = NetworkTransport(base: URL(string: PlanqueClient.baseURL)!) }
        return planque
    }

    private var approveWithKey: ((KeyAct, String) async throws -> Data)? {
        guard let passkey = passkeySession else { return nil }
        return { act, title in
            try await askSecurityKey(act: title) { pin in try await passkey.approved(method: act.method, path: act.path, body: act.body, pin: pin) }
        }
    }

    /// An answer that grants authority on this Mac's security key (`PasskeySession.approveOnce`, `extraRoom`), named in
    /// the PIN sheet as the iPad's prompt ("Answer {summary}"); nil without a key on the security key's route, so the
    /// card says to approve elsewhere. A refusal is never the key's.
    private var answerWithKey: ((HeldCall, Answer) async throws -> Void)? {
        guard let passkey = passkeySession else { return nil }
        return { call, answer in
            let title = words("needs_you.prompt.answer", ["summary": call.title ?? call.action])
            switch answer {
            case .approveOnce: try await askSecurityKey(act: title) { pin in try await passkey.approveOnce(call, pin: pin) }
            case .changeCard: try await askSecurityKey(act: title) { pin in try await passkey.extraRoom(call, pin: pin) }
            case .reject: throw PasskeyRefusal.notAnApproval
            }
        }
    }

    /// The security key's assertion over one act's request, named in the PIN sheet, without sending it (a taf's removal
    /// signs before its Cards are revoked); nil without a key on the security key's route.
    private var signWithKey: ((KeyAct, String) async throws -> String)? {
        guard let passkey = passkeySession else { return nil }
        return { act, title in try await askSecurityKey(act: title) { pin in try await passkey.assertion(for: act, pin: pin) } }
    }

    /// Discard for a taf being set up that this person started (Home's `setting_up[].discard`), as the iPad's
    /// `discardSettingUp`, on the security key (`SettingUpDiscard`); without a key, it says to approve on another device.
    private func discardSettingUp(_ setting: SettingUp) async -> String? {
        guard let sign = signWithKey else { return words("approval.device_can_not_approve_approve") }
        let account = account, cloud = cloud
        let done = await SettingUpDiscard.discard(setting, cardsLeftBefore: discardCardsLeft[setting.kiffAgent] ?? [], words: words,
                                                  sign: sign, revoke: { try await account.revoke(cardID: $0) },
                                                  send: { try await cloud.discardSettingUp(setting.kiffAgent, assertion: $0) })
        discardCardsLeft[setting.kiffAgent] = done.cardsLeft.isEmpty ? nil : done.cardsLeft
        await readTafs()
        return done.said
    }

    /// Asks this Mac's security key through the PIN sheet: its PIN, then its touch, as many tries
    /// as the person makes; it answers once the key approved, or throws once the sheet is closed.
    @MainActor private func askSecurityKey<Answer>(act: String? = nil, _ ask: @escaping (SecurityKeyPIN) async throws -> Answer) async throws -> Answer {
        try await withCheckedThrowingContinuation { continuation in
            var answer: Answer?
            pinSheet = PINSheetModel(words: words, act: act, attempt: { pin in answer = try await ask(pin) },
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
        let pages = TafPagesModel(cloud: cloud, taf: id, proof: { await setupProof() }, runs: runs)
        // Resume on this Mac's security key, when it has one (kiff/cloud#96), for this taf's KIFF agent.
        pages.halt.approveWithKey = approveWithKey
        // A version's trial: KIFF's draft read here, its confirm on the security key, going back with the device key.
        pages.account = account
        pages.confirmWithKey = approveWithKey
        pages.tafName = taf.name
        pages.halt.agent = taf.kiffAgent
        pages.halt.name = taf.name
        // Revoke, as the iPad's: each Card revoked in KIFF, then the list read again.
        pages.viewOnly = accountModel.me?.viewOnly == true
        pages.revokeCards = { [account] ids in
            for id in ids { try await account.revoke(cardID: id) }
            await readTafs()
        }
        // Remove for good on this Mac's security key, as the iPad's `removeTaf`.
        if let sign = signWithKey {
            let cardIDs = taf.cards.map(\.id), name = taf.name, words = self.words
            pages.removalPreview = { [cloud] in try? await cloud.removalPreview(id) }
            pages.removeForGood = { [account, cloud] in
                let said = await TafRemoval.remove(taf: name, cloudID: id, cardIDs: cardIDs, words: words, sign: sign,
                                                   revoke: { try await account.revoke(cardID: $0) },
                                                   remove: { try await cloud.remove(id, assertion: $0) })
                await readTafs()
                return said
            }
        }
        tafPages = pages
        openTaf = taf.id
    }

    /// Closes Coach, back to the screen under it, as the iPad's Coach mode's Back: that screen,
    /// a taf's page and its tab too, is as it was.
    private func closeCoach() { panel.close() }

    /// The sidebar's Coach, as the iPad's `openCoach` (AppModel.swift:6767-6778): it only opens
    /// Coach, over the screen. Coach closes from its own Back (Esc too).
    private func openCoach() { panel.openCoach() }

    /// Start a new taf, as the iPad's `startNewTaf` (AppModel.swift:6801-6804): a new
    /// conversation in Coach, so Coach mode's start shows, whether Coach was open or not. Own
    /// words and the gallery's own words come here, and the sidebar's + without a gallery.
    private func startNewTaf() { panel.startNewTaf(in: coach) }

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

    /// A recipe handed to Coach from the Overview or the gallery, as the iPad's `handRecipeToCoach`
    /// (AppModel.swift:8536-8542): a new conversation with its words in Coach's box, to edit and
    /// send. Nothing is sent.
    private func handToCoach(_ recipe: Recipes.Recipe) {
        guard mayUseCoach else { return }
        panel.handRecipe(recipe.say, to: coach)
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
                               shareLine: ShareLine(agent: taf.kiffAgent, account: account, people: people, email: accountModel.me?.email,
                                                    taf: taf.name, approveWithKey: approveWithKey),
                               dictation: dictation, improveInCoach: improving(taf), askCoach: askingCoach(taf),
                               openConnect: { self.openTaf = nil; self.selection = .connectApps }, files: files,
                               record: record, tafs: overview.tafs, timeZone: accountModel.me?.timeZone,
                               needsYou: needsYou, answersHolds: accountModel.me?.answersHolds ?? true,
                               answered: { await needsYou.load(); await readTafs() }, tab: tafTab).id(taf.id))
    }

    /// Coach on a taf, a new conversation, as the iPad's `improveTaf` with `coachOpen`: for
    /// someone who manages the taf and may use Coach; nil for anyone else.
    private func improving(_ taf: Home.Taf) -> (() -> Void)? {
        guard let id = taf.tafID, mayUseCoach, Access.manages(access[taf.id]) else { return nil }
        let name = taf.name
        // Over the taf's page, which stays under Coach.
        return { panel.improve(CoachModel.Improving(id: id, name: name), in: coach) }
    }

    /// Ask Coach on a taf's `ask_coach` card, as the iPad's `askCoachAbout`: Coach on the taf with
    /// the card's words in its box, nothing sent; nil for someone who may not.
    private func askingCoach(_ taf: Home.Taf) -> ((String) -> Void)? {
        guard let id = taf.tafID, mayUseCoach, Access.manages(access[taf.id]) else { return nil }
        let name = taf.name
        let manages = Access.manages(access[taf.id])
        let may = mayUseCoach
        return { words in
            panel.ask(about: CoachModel.Improving(id: id, name: name), words: words, mayUseCoach: may, manages: manages, in: coach)
        }
    }

    private var accountScreen: some View {
        AccountView(model: accountModel, devices: devices, people: people, exportChats: exportChats, alerts: alerts, files: files, chrome: chromes,
                    tafName: { agent in overview.tafs.first { $0.id == agent }?.name },
                    open: { selection = $0 }, addThisMac: addThisMac, softwareKey: softwareKey, route: route, mayUseCoach: mayUseCoach, inSample: inSample, signOut: {
            // A list read still on its way keeps nothing from here.
            overview.endSession()
            brief.endSession()
            // An ending of a connection on its way sends nothing more (`ConnectAppsModel.endSession`).
            connect.endSession()
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

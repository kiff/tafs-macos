import SwiftUI

@MainActor
final class CoachModel: ObservableObject {
    enum State: Equatable {
        case loading
        /// Coach hasn't been started on this account.
        case notStarted
        case loaded(Coach, Thread.Page)
        case unread(why: String)
    }

    /// A message the person sent that the thread doesn't have yet, or that didn't go.
    struct Pending: Equatable {
        let text: String
        /// When the person first sent it.
        var at = Date()
        /// Why it didn't go, in tafs cloud's words when it sent some; nil while it is going.
        var failed: String?
        /// tafs cloud's id for it once taken: the thread's copy carries the same.
        var id: String?
        /// The files that went with it, shown with it until the thread has it.
        var files: [AttachmentRef] = []
    }

    @Published private(set) var state: State = .loading {
        // A thread read, or a new conversation, puts right a reopen that failed, as the
        // iPad's `setupError = nil` on each read.
        didSet { notReopened = nil }
    }
    @Published var draft = ""
    @Published private(set) var pending: Pending?
    /// The card whose answer is on its way, by its key, and why an answer didn't go.
    @Published private(set) var answering: String?
    @Published private(set) var notAnswered: [String: String] = [:]
    /// The AI-data consent to ask for before the message can go.
    @Published private(set) var consent: TafsCloud.AIConsent?
    /// The answer as it is written, while a run streams.
    @Published private(set) var live: LiveAnswer?
    /// tafs cloud's words for why the last run stopped, when it stopped with a reason for the person.
    @Published private(set) var stopped: String?
    /// Coach's chat shown, by its session: the newest when Coach opens, as the iPad's `setupChat`.
    @Published private(set) var chat: String?
    /// A new conversation before its first message, as the iPad's `setupFresh`: nothing is read
    /// for it, and its first message asks tafs cloud for a new chat.
    @Published private(set) var fresh = false
    /// Moves on with each new conversation: what comes back for the one before is dropped.
    private var conversation = 0
    /// The taf a new conversation improves, as the iPad's `setupImproving`: its first message
    /// goes to tafs cloud's improve route, which puts the taf in front of it. Nil otherwise.
    @Published private(set) var improving: Improving?
    /// The files picked for the next message, as they go up, as the iPad's `chatFiles[key]`
    /// (AppModel.swift:4727): sent with the message, and taken from here once it goes.
    @Published private(set) var files = ChatFiles()
    /// Why a file wasn't added, or a message with files didn't go, as the iPad's `fileNotices[key]`.
    @Published private(set) var fileNotice: String?
    /// Where files' bytes go and come from.
    private let store: FileStore

    struct Improving: Equatable {
        /// The taf's id in tafs cloud.
        let id: String
        let name: String
    }
    private let cloud: CloudClient
    /// Opens the answer's stream; nil sends plainly and reads the thread again instead.
    private let streamer: LineStream?
    /// A version's trial chat (`Trials`): its thread and messages are the trial's own routes, text only, never streamed.
    var trial = false
    private let sleep: (TimeInterval) async throws -> Void
    private let now: () -> Date
    private var following = 0
    /// The answer streaming now, as the iPad's `setupStream`: a new conversation cancels it.
    private var streaming: Task<Void, Never>?

    /// While an answer is owed, the thread is read again soon at first, then less and less often, with jitter, and
    /// stops after `followAtMost` reads (`Backoff.answer`, tafs docs/scale.md): a slow fallback, never a fixed loop.
    static let followAtMost = Backoff.answer.reads

    /// The taf whose chat this is, when it isn't Coach's: then nothing is read to find it.
    private let fixed: Coach?
    /// This device's planque proof for Coach's thread read, as the iPad's `loadSetupThread`: signed
    /// with the device key and no prompt, so tafs cloud marks Coach's approval and sign-in cards
    /// (`wider`). Nil, or nil from it, reads the thread unmarked; a taf's chat never sends it.
    private let proof: (() async -> String?)?

    /// `grants` reads planque's grants and `drafts` one of KIFF's drafts, for what Coach's cards
    /// name. Left out, Coach's own chat in the signed-in window (the one given a `proof`) reads them
    /// as the iPad does: planque's grants with this device's proof (`ConnectionsSource`, the read
    /// Connect apps sends), and a draft with the session (`AccountClient.draft(id:)`). Nothing else
    /// reads them.
    init(cloud: CloudClient, taf: Coach? = nil, streamer: LineStream? = nil, sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
         now: @escaping () -> Date = Date.init, store: FileStore = URLSessionFileStore(), proof: (() async -> String?)? = nil,
         grants: (() async throws -> [AppConnections.Grant])? = nil, drafts: ((String) async throws -> AccountClient.Draft)? = nil) {
        self.cloud = cloud
        self.fixed = taf
        self.proof = proof
        self.streamer = streamer
        self.sleep = sleep
        self.now = now
        self.store = store
        if taf == nil, let proof {
            let planque: () async throws -> [AppConnections.Grant] = {
                try await ConnectionsSource(transport: NetworkTransport(base: URL(string: PlanqueClient.baseURL)!), tenant: cloud.session.tenant,
                                            language: cloud.language, proof: proof).grants()
            }
            let kiff: (String) async throws -> AccountClient.Draft = { id in
                try await AccountClient(transport: NetworkTransport(), session: cloud.session, language: cloud.language).draft(id: id)
            }
            self.readGrants = grants ?? planque
            self.readDraft = drafts ?? kiff
        } else {
            self.readGrants = taf == nil ? grants : nil
            self.readDraft = taf == nil ? drafts : nil
        }
    }

    // MARK: What Coach's cards name: planque's grants, KIFF's drafts, Coach's tools

    /// planque's grants, as the iPad's `grants`: a hand-over's tools by their approval's title
    /// (`AppConnections.toolTitle`), an approval's connection line, and the tools "Taking shape"
    /// lists. Kept in memory only, and gone at sign-out.
    @Published private(set) var grants: [AppConnections.Grant] = []
    /// KIFF's drafts the approvals name, by id, as the iPad's `setupDrafts` and `setupDraftErrors`:
    /// read, or why not. Kept in memory only, and gone at sign-out.
    @Published private(set) var drafts: [String: DraftRead] = [:]
    enum DraftRead: Equatable {
        case read(AccountClient.Draft)
        case failed(String)
        var draft: AccountClient.Draft? { if case .read(let draft) = self { return draft } else { return nil } }
    }
    /// Coach's tools as `GET /v1/setup` says them (`tools`), as the iPad's `coachTools`; nil from a
    /// tafs cloud that sends none.
    @Published private(set) var coachTools: CoachTools?
    private let readGrants: (() async throws -> [AppConnections.Grant])?
    private let readDraft: ((String) async throws -> AccountClient.Draft)?

    /// planque is read for Coach's cards with this Mac's proof, as Windows gates "Taking shape" on
    /// planque being there to read tools. It stands for the iPad's `planqueReady`, which this Mac is
    /// only after a Start made on it.
    var readsPlanque: Bool { readGrants != nil }

    /// The drafts read, by id.
    var readDrafts: [String: AccountClient.Draft] { drafts.compactMapValues(\.draft) }

    /// What the chat's cards name that's read from elsewhere, and where each stands: when it
    /// changes, `readNamed` reads again. Empty when nothing is named.
    var named: String {
        guard isCoach, case .loaded(_, let page) = state else { return "" }
        var parts: [String] = []
        for card in page.cards {
            if let grant = card.grant { parts.append("g:\(grant):\(card.answerState ?? "-")") }
            if card.type == "approval", let draft = card.draft { parts.append("d:\(draft):\(card.answerState ?? "-")") }
            if card.isHandOver, !card.tools.isEmpty { parts.append("t:\(card.key)") }
        }
        return parts.joined(separator: "|")
    }

    /// Reads what the chat's cards name, as the iPad's `refreshConnections` and `readCardDraft`:
    /// planque's grants when a card names one or a hand-over lists tools; each draft an approval
    /// names. Reads only. A read that fails keeps what was read; one after sign-out is dropped.
    func readNamed() async {
        guard isCoach, case .loaded(_, let page) = state else { return }
        let gen = accountGeneration
        if let readGrants, page.cards.contains(where: { $0.grant != nil || ($0.isHandOver && !$0.tools.isEmpty) }),
           let read = try? await readGrants(), gen == accountGeneration {
            grants = read
        }
        var ids: [String] = []
        for card in page.cards where card.type == "approval" {
            if let id = card.draft, !ids.contains(id) { ids.append(id) }
        }
        for id in ids { await read(draft: id) }
    }

    /// Reads one of KIFF's drafts again, as the iPad's `readCardDraft`: Try again on a card whose
    /// Card couldn't be read.
    func read(draft id: String) async {
        guard let readDraft else { return }
        let gen = accountGeneration
        do {
            let draft = try await readDraft(id)
            guard gen == accountGeneration else { return }
            drafts[id] = .read(draft)
        } catch {
            guard gen == accountGeneration else { return }
            // A draft read once stays drawn: only one never read says why.
            if drafts[id]?.draft == nil { drafts[id] = .failed(Self.why(error)) }
        }
    }

    /// planque's grant a card asks about, once read.
    func grant(for card: Thread.Card) -> AppConnections.Grant? {
        guard let id = card.grant else { return nil }
        return grants.first { $0.id == id }
    }

    /// Whether a newer approval in the chat asks about the same connection (`Thread.Page.replaced`).
    func replaced(_ card: Thread.Card) -> Bool {
        guard case .loaded(_, let page) = state else { return false }
        return page.replaced(card)
    }

    /// What "Taking shape" shows, from what Coach holds (`SetupShape`).
    func shape(_ words: Words) -> SetupShape? {
        guard isCoach, case .loaded(_, let page) = state else { return nil }
        return SetupShape(page: page, grants: grants, drafts: readDrafts, words)
    }

    /// A tool of a hand-over, by its approval's title, else in words, as the iPad's
    /// `toolTitle($0) ?? KIFFMapping.toolWords($0)` (SetupChatView.swift:1446).
    func toolWords(_ card: Thread.Card) -> [String] {
        card.tools.map { AppConnections.toolTitle($0, in: grants) ?? CallNames.toolWords($0) }
    }

    /// Coach's own chat, not a taf's: only it has conversations, and only its cards are answered.
    var isCoach: Bool { fixed == nil }

    /// Where the next message goes, as the iPad's `setupTarget`: a new chat, the one shown, else
    /// the live one. Coach's all say they follow a new chat after a hand-over. A taf's chat
    /// goes to its live one.
    var target: ChatTarget {
        guard isCoach else { return .live }
        var target = fresh ? ChatTarget.new : chat.map { ChatTarget(session: $0) } ?? .live
        target.newChatAfterHandover = true
        return target
    }

    /// The chat shown, read; nil while a new conversation has nothing to read.
    private func read(_ coach: Coach) async throws -> Thread.Page? {
        if fresh { return nil }
        // Only Coach's own thread carries the proof, as on the iPad.
        var signed: String?
        if trial { return try await cloud.trialThread(of: coach.id) }
        if isCoach, let make = proof { signed = await make() }
        return try await cloud.thread(of: coach.id, session: isCoach ? chat : nil, proof: signed)
    }

    /// A new conversation, as the iPad's `newSetupChat`: nothing in it until its first message.
    /// What's typed stays in the box.
    func newChat() {
        guard isCoach, case .loaded(let coach, _) = state else { return }
        conversation += 1
        following += 1
        streaming?.cancel()
        streaming = nil
        live = nil
        pending = nil
        stopped = nil
        // The Mac keeps a message refused for want of the AI consent as `pending`, where the
        // iPad puts it back in the composer: with `pending` gone, its consent ask goes too.
        consent = nil
        chat = nil
        fresh = true
        improving = nil
        state = .loaded(coach, .empty)
    }

    /// An improvement asked for before Coach was read: the iPad's `improveTaf` doesn't wait for
    /// Coach, so here it's kept and started once Coach is read.
    private var improveWhenRead: Improving?
    /// A new taf asked for before Coach was read: started once Coach is read, as an improvement is.
    private var newWhenRead = false

    /// Start a new taf, as the iPad's `startNewTaf` (AppModel.swift:6801-6804): a new
    /// conversation, so Coach mode's start shows, from wherever Coach is, open or not.
    func startNewTaf() {
        guard isCoach else { return }
        guard case .loaded = state else { newWhenRead = true; improveWhenRead = nil; return }
        newChat()
    }

    /// Coach's past chats, for Previous conversations, as the iPad's `setupChats`.
    @Published private(set) var chats: [CoachChat] = []

    /// Reads Coach's past chats, as the iPad's `loadSetupChats` (AppModel.swift:7138-7143): a read
    /// that fails keeps the list as it was, and one that comes back after sign-out is dropped.
    /// The watch's conversations for Previous conversations (`WatchDaysModel`), read from this Coach's tafs cloud.
    func watchDays() -> WatchDaysModel { WatchDaysModel(cloud: cloud) }

    func loadChats() async {
        guard isCoach, case .loaded(let coach, _) = state else { return }
        let gen = accountGeneration
        guard let read = try? await cloud.chats(of: coach.id), gen == accountGeneration else { return }
        chats = read
    }

    /// Coach's archived chats, for Archived, as the iPad's `archivedSetupChats`.
    @Published private(set) var archivedChats: [CoachChat] = []

    /// The chat shown, by its session: the one opened, else the live chat's, as the iPad's
    /// `setupChat ?? setupThread.session`; nil for a new conversation. Needs you leaves a waiting chat
    /// shown here out while Coach is open (`NeedsYouCount.shown`).
    var shownSession: String? {
        if let chat { return chat }
        guard !fresh, case .loaded(_, let page) = state else { return nil }
        for item in page.items.reversed() {
            if case .message(let message, _) = item, let session = message.session { return session }
        }
        return nil
    }

    /// The chats set aside from Needs you this session, as the iPad's `setAsideChats`: Coach never
    /// goes on in one by itself. Kept in memory only.
    private var setAsideChats: Set<String> = []

    /// Coach's waiting chat, from Needs you's Open Coach, as the iPad's `openCoachWaiting`
    /// (AppModel.swift:7756-7760): Coach opens on that chat, where its card waits. Before Coach is
    /// read, it's the chat Coach opens on once read.
    func open(waiting session: String) async {
        guard isCoach, !session.isEmpty else { return }
        guard case .loaded = state else {
            chat = session
            fresh = false
            improveWhenRead = nil
            newWhenRead = false
            return
        }
        await open(chat: session)
    }

    /// Chats Needs you set aside, as the iPad's `setAsideCoach` after tafs cloud took it
    /// (AppModel.swift:7807-7812): one shown here gives way to a new conversation, since its next
    /// message would go on in the ended session, and Coach never opens one by itself again.
    func setAside(chats ended: Set<String>) {
        setAsideChats.formUnion(ended)
        if let shown = shownSession, ended.contains(shown) { newChat() }
    }

    /// Archives one of Coach's chats, as the iPad's `archiveSetupChat` (AppModel.swift:7533-7551):
    /// it leaves the list, and the one shown gives way to a new conversation. Nil once tafs cloud
    /// has taken it, else why, in the shared words. An answer after sign-out says nothing.
    func archive(chat session: String) async -> String? {
        guard isCoach, case .loaded(let coach, _) = state else { return Words.app("coach.not_archived_try_again") }
        let gen = accountGeneration
        do {
            try await cloud.archive(chat: session, of: coach.id)
        } catch {
            guard gen == accountGeneration else { return nil }
            return Words.app("taf.not_archived", ["why": NeedsYouModel.why(error)])
        }
        guard gen == accountGeneration else { return nil }
        let shown = shownSession == session
        chats.removeAll { $0.session == session }
        if shown { newChat() }
        return nil
    }

    /// Reads Coach's archived chats, as the iPad's `loadArchivedSetupChats`
    /// (AppModel.swift:7553-7559): a read that fails keeps the list as it was, and one that
    /// comes back after sign-out is dropped.
    func loadArchivedChats() async {
        guard isCoach, case .loaded(let coach, _) = state else { return }
        let gen = accountGeneration
        guard let read = try? await cloud.archivedChats(of: coach.id), gen == accountGeneration else { return }
        archivedChats = read
    }

    /// Puts an archived chat back in the list, as the iPad's `unarchiveSetupChat`
    /// (AppModel.swift:7561-7577), then reads the list again. Nil once tafs cloud has taken it,
    /// else why.
    func putBack(chat session: String) async -> String? {
        guard isCoach, case .loaded(let coach, _) = state else { return Words.app("coach.not_put_back_try_again") }
        let gen = accountGeneration
        do {
            try await cloud.putBack(chat: session, of: coach.id)
        } catch {
            guard gen == accountGeneration else { return nil }
            return Words.app("taf.not_put_back", ["why": NeedsYouModel.why(error)])
        }
        guard gen == accountGeneration else { return nil }
        archivedChats.removeAll { $0.session == session }
        await loadChats()
        return nil
    }

    /// Why a past chat reopened from Previous conversations couldn't be read, as the iPad's
    /// `setupError` from `loadSetupThread`: the page shown stays, with this under it.
    @Published private(set) var notReopened: String?

    /// Opens one of Coach's past chats, as the iPad's `openSetupChat` (AppModel.swift:7124-7135):
    /// what was on its way belonged to the chat before; the chat is then read, as
    /// `loadSetupThread` reads it (:7328-7375): an answer after sign-out, or for a chat since left,
    /// is dropped, and a read that fails keeps the page shown and says why.
    func open(chat session: String) async {
        guard isCoach, case .loaded(let coach, _) = state else { return }
        conversation += 1
        following += 1
        streaming?.cancel()
        streaming = nil
        live = nil
        improving = nil
        chat = session
        fresh = false
        pending = nil
        // A consent ask belongs to the `pending` it drops, as in `newChat`.
        consent = nil
        stopped = nil
        notReopened = nil
        let gen = accountGeneration
        let mine = conversation
        do {
            let page = try await read(coach) ?? .empty
            guard gen == accountGeneration, mine == conversation else { return }
            show(coach, page)
        } catch {
            guard gen == accountGeneration, mine == conversation else { return }
            notReopened = NeedsYouModel.why(error)
        }
    }

    /// A new conversation on a taf, as the iPad's `improveTaf`.
    func improve(_ taf: Improving) {
        guard isCoach else { return }
        guard case .loaded = state else { improveWhenRead = taf; newWhenRead = false; return }
        newChat()
        improving = taf
    }

    /// Coach on a taf with these words in the box, nothing sent, as the iPad's `askCoachAbout`:
    /// only for someone who may use Coach and manages the taf.
    func ask(about taf: Improving, words: String, mayUseCoach: Bool, manages: Bool) {
        guard isCoach, mayUseCoach, manages else { return }
        improve(taf)
        draft = words
    }

    /// The sent message is on its way, as the iPad's `setupSending`.
    var sending: Bool { pending != nil && pending?.failed == nil }

    /// How long a sent message waits for the thread to have it, as the iPad's `SentMessages.kept`.
    static let kept: TimeInterval = 120

    /// Drops the sent message once the thread has it, as the iPad's `SentMessages.merge`: by
    /// tafs cloud's id for it when the send answered one; else by its words, written about
    /// when it was sent (`/improve` answers none); and in any case after `kept`.
    private func take(_ page: Thread.Page) {
        guard let sent = pending, sent.failed == nil else { return }
        if now().timeIntervalSince(sent.at) > Self.kept { pending = nil; return }
        if let id = sent.id {
            if page.has(message: id) { pending = nil }
        } else if page.hasPersons(sent.text, since: sent.at.addingTimeInterval(-Self.kept)) {
            pending = nil
        }
    }

    /// Nothing in this conversation and no taf it improves, as the iPad's `coachChatIsEmpty`:
    /// New conversation then has nothing to start.
    var chatIsEmpty: Bool { improving == nil && isEmpty }

    /// The new conversation's first message made its chat, as the iPad's `settleSetupChat`.
    private func settle(_ session: String) {
        guard fresh else { return }
        chat = session
        fresh = false
    }

    /// tafs cloud started a new chat for the message just sent, as the iPad's
    /// `followNewSetupChat`: the chat shown had handed a taf over. Coach goes on in the new
    /// one, with the message just sent; the old one stays tafs cloud's. True once it moved.
    private func followNew(_ session: String, newSession: Bool, _ coach: Coach) -> Bool {
        guard newSession, !session.isEmpty, let open = chat, open != session else { return false }
        conversation += 1
        chat = session
        fresh = false
        state = .loaded(coach, .empty)
        return true
    }

    /// Coach is at work: a message on its way, an answer being written, or tafs cloud says a
    /// run goes on. The box then asks for the next message, as on the iPad.
    var working: Bool {
        if live != nil || (pending != nil && pending?.failed == nil) { return true }
        if case .loaded(_, let page) = state { return page.working }
        return false
    }

    /// Nothing in the chat yet: the screen is Coach mode's start, as on the iPad.
    var isEmpty: Bool {
        switch state {
        case .notStarted: return true
        case .loaded(_, let page): return page.items.isEmpty && pending == nil && !working && stopped == nil
        case .loading, .unread: return false
        }
    }

    /// Coach improving a taf holds the files in its tray back, as the iPad's `improvementHoldsFiles`
    /// (AppModel.swift:5555): an improvement's first message carries none, since tafs cloud adds the
    /// taf to it. The words go alone, the files wait for the next message, and the box says so
    /// (`coach.improve_no_files`).
    var improvementHoldsFiles: Bool { files.heldBy(improving: improving != nil) }

    /// Whether Send goes: words, or files ready, and nothing that holds it (a file still going
    /// up, or files while the chat is at work, as the iPad's `holdsSend`). Files an improvement
    /// holds back hold nothing: the words go alone.
    var canSend: Bool {
        if improvementHoldsFiles { return canSend(draft) }
        guard !files.holdsSend(working: working) else { return false }
        let ready = files.files.compactMap(\.ref)
        guard !ready.isEmpty else { return canSend(draft) }
        guard case .loaded = state else { return false }
        return Outgoing.text(draft, files: ready) != nil && (pending == nil || pending?.failed != nil)
    }

    private func canSend(_ text: String) -> Bool {
        guard case .loaded = state else { return false }
        return Outgoing.text(text) != nil && (pending == nil || pending?.failed != nil)
    }

    /// Sends one of the start screen's examples as it is, as the iPad's `submitSetup`.
    func send(example: String) async {
        guard case .loaded(let coach, _) = state, canSend(example), let text = Outgoing.text(example) else { return }
        await deliver(text, to: coach)
    }

    /// Sends what the person wrote. It stays in view, as written, until the thread has it;
    /// if it doesn't go, it stays with why, to send again.
    func send() async {
        guard case .loaded(let coach, _) = state, canSend else { return }
        // An improvement's first message goes without them: they stay in the tray for the next
        // one, as the iPad's `send` (SetupChatView.swift:825-826).
        if improvementHoldsFiles {
            guard let text = Outgoing.text(draft) else { return }
            draft = ""
            await deliver(text, to: coach)
            return
        }
        // A message with files goes as a message of its own, with the ready ones, as the iPad's
        // `submitSetup` (AppModel.swift:7825-7826); ones that failed stay in the tray.
        let taken = files.take()
        let refs = taken.compactMap(\.ref)
        guard let text = refs.isEmpty ? Outgoing.text(draft) : Outgoing.text(draft, files: refs) else {
            files.putBack(taken)
            return
        }
        draft = ""
        if refs.isEmpty {
            await deliver(text, to: coach)
            return
        }
        fileNotice = nil
        // Not taken: left with the composer, files and all (SetupChatView.swift:790-795).
        if !(await deliver(text, to: coach, files: refs)) {
            if draft.isEmpty { draft = text }
            files.putBack(taken)
        }
    }

    // MARK: Files (the iPad's AppModel.swift:4723-4835)

    /// Where this chat's files go on tafs cloud: Coach's, or the taf's. Nil where nothing can be
    /// attached: before the chat is read, or a new conversation that improves a taf, whose first
    /// message tafs cloud writes (the iPad's `filesTarget`).
    var filesTarget: String? {
        guard case .loaded(let coach, _) = state else { return nil }
        if isCoach { return improving == nil ? coach.id : nil }
        return coach.id
    }

    /// Adds a file to the next message and uploads it, as the iPad's `attach(_:to:)`: declared
    /// to tafs cloud, which checks its type and size, then its bytes straight to storage. One
    /// that can't go says why in the tray, and is left out of the message. One that comes back
    /// after sign-out is the session before's: dropped.
    func attach(_ file: PreparedFile) async {
        guard let target = filesTarget else { return }
        fileNotice = nil
        guard files.count < FilePrep.perMessage else {
            fileNotice = Words.app("chat.message_carries_most_files", ["per_message": String(FilePrep.perMessage)])
            return
        }
        let pending = PendingFile(id: UUID(), name: file.name, mediaType: file.mediaType, thumbnail: file.thumbnail, state: .uploading)
        files.add(pending)
        let gen = accountGeneration
        let state: PendingFile.State
        do {
            let (ref, upload) = try await cloud.attach(target, mediaType: file.mediaType, name: file.name, size: file.data.count,
                                                       sha256: FilePrep.sha256(file.data))
            // A session that ended while it was declared puts no bytes up, as the iPad's check
            // after each wait (AppModel.swift:4766).
            guard gen == accountGeneration else { return }
            try await store.put(file.data, to: upload)
            state = .ready(ref)
        } catch {
            state = .failed(Self.fileWhy(error))
        }
        guard gen == accountGeneration else { return }
        files.set(pending.id, state)
    }

    /// A file picked that can't be attached: said in the tray, never uploaded.
    func refuseFile(_ problem: Error) {
        fileNotice = Self.fileWhy(problem)
    }

    func removeFile(_ id: UUID) {
        files.remove(id)
    }

    /// A file the person attached, downloaded to open full size, as the iPad's `openFile`: a
    /// temporary copy under its own name, removed at sign-out. Nil when it couldn't be read; the
    /// notice says why.
    func openFile(_ ref: AttachmentRef) async -> URL? {
        guard case .loaded(let coach, _) = state else { return nil }
        // A file read after sign-out is the session before's: nothing is written or opened.
        let gen = accountGeneration
        do {
            let url = try await cloud.attachmentURL(coach.id, file: ref.id)
            guard gen == accountGeneration else { return nil }
            let data = try await store.get(url)
            guard gen == accountGeneration else { return nil }
            // tafs cloud's id and the file's name, each made one safe component, so the copy stays in its own folder
            // whatever the server sends ("../x", "/etc/x", ".."), as the Android app does.
            guard let dir = LocalName.file(ref.id, in: Self.openedFiles, fallback: "attachment"),
                  let local = LocalName.file(ref.name, in: dir) else { throw KIFFError.unreadable }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: local, options: .atomic)
            return local
        } catch {
            guard gen == accountGeneration else { return nil }
            fileNotice = Words.app("chat.file.not_opened", ["file": ref.name, "why": Self.fileWhy(error)])
            return nil
        }
    }

    /// Where files opened full size are copied: removed at sign-out, so nothing a person attached
    /// stays on the Mac after them (the iPad's `openedFiles`).
    static let openedFiles = FileManager.default.temporaryDirectory.appendingPathComponent("attachments", isDirectory: true)

    static func removeOpenedFiles() {
        try? FileManager.default.removeItem(at: openedFiles)
    }

    /// Why a file didn't go or open: its own words, else tafs cloud's, as the iPad's
    /// `localizedDescription`.
    static func fileWhy(_ error: Error) -> String {
        (error as? FileProblem)?.message ?? why(error)
    }

    /// Answers a card with one of its options. A card that no longer waits is read again as
    /// it is; any other refusal stays on the card with why.
    func answer(_ card: Thread.Card, with option: Thread.Card.Option) async {
        guard case .loaded(let coach, _) = state, answering == nil, card.waitsForPerson else { return }
        answering = card.key
        defer { answering = nil }
        do {
            try await cloud.answer(card, with: option, in: coach.id)
            notAnswered[card.key] = nil
            await follow(coach)
        } catch let refusal as CloudRefusal where refusal.status == 409 {
            notAnswered[card.key] = nil
            await reload(coach)
        } catch {
            notAnswered[card.key] = Self.why(error)
        }
    }

    /// The card an answer for `id` is for, as the iPad's `cardRef` (AppModel.swift:6708-6711): the
    /// one waiting under that id, since Coach can use an id again, else the latest.
    func cardRef(_ id: String) -> Thread.Card? {
        guard case .loaded(_, let page) = state else { return nil }
        let cards = page.items.compactMap { item -> Thread.Card? in if case .card(let card, _) = item { return card } else { return nil } }
        return cards.last { $0.id == id && $0.answerState == nil } ?? cards.last { $0.id == id }
    }

    /// The key a card's answer goes by, its `cardRef`'s: what's on its way and why it didn't go.
    func refKey(_ card: Thread.Card) -> String { cardRef(card.id)?.key ?? card.key }

    /// Answers a questions card with every one of its questions answered, as the iPad's
    /// `answer(_:_:)` (AppModel.swift:8355-8385): only in Coach's chat (`setupTaf`), for someone
    /// who may use Coach (`mayUseCoach`, Keyboard.swift:70), to the card its id names now
    /// (`cardRef`), in that card's chat. Whatever `waits` says, a card with no answer is answered,
    /// as the iPad's `QuestionsCard`. The run that waited goes on in the chat tafs cloud names
    /// (`settleSetupChat`), and it's followed. A card that no longer waits is read again as it is;
    /// one refused for want of the AI-data consent stays quiet; anything else, a refusal too, says
    /// the answer didn't reach Setup. An answer that comes back after sign-out is the session
    /// before's: it's dropped.
    func answer(_ card: Thread.Card, questions answers: [String: QuestionAnswers.Answer], mayUseCoach: Bool) async {
        guard isCoach, mayUseCoach, case .loaded(let coach, _) = state, answering == nil else { return }
        guard let ref = cardRef(card.id), ref.answerState != "answered", ref.isQuestions,
              answers.count == ref.questions.count else { return }
        answering = ref.key
        defer { answering = nil }
        let gen = accountGeneration
        do {
            let answered = try await cloud.answer(ref, questions: answers, in: coach.id)
            guard gen == accountGeneration else { return }
            notAnswered[ref.key] = nil
            settle(answered.session)
            await follow(coach)
        } catch let refusal as CloudRefusal where refusal.status == 409 {
            guard gen == accountGeneration else { return }
            notAnswered[ref.key] = nil
            await reload(coach)
        } catch let refusal as CloudRefusal where refusal.code == TafsCloud.aiConsentRequired {
            // Refused for want of the AI-data consent: the card stays as it was, its answers as
            // chosen, with nothing said, as the iPad's (AppModel.swift:8372-8376).
            guard gen == accountGeneration else { return }
            notAnswered[ref.key] = nil
        } catch {
            // Anything else, a refusal too, as the iPad's `answerDidNotReachSetup` (:8377-8381).
            guard gen == accountGeneration else { return }
            notAnswered[ref.key] = Words.app("coach.answer_did_not_reach_setup")
        }
    }

    /// Says no to an approval or a sign-in. It grants nothing, so any Mac may.
    func decline(_ card: Thread.Card) async {
        guard case .loaded(let coach, _) = state, answering == nil, card.grants else { return }
        // A sign-in while it waits; an approval as the iPad offers Decline, failed ones answered too.
        if card.type == "approval" {
            guard ApprovalLines.declinable(card, ApprovalLines.state(card, grant: grant(for: card)), replaced: replaced(card), grant: grant(for: card)) else { return }
        } else {
            guard card.waitsForPerson else { return }
        }
        answering = card.key
        defer { answering = nil }
        do {
            try await cloud.decline(card, in: coach.id)
            notAnswered[card.key] = nil
            await follow(coach)
        } catch let refusal as CloudRefusal where refusal.status == 409 {
            notAnswered[card.key] = nil
            await reload(coach)
        } catch {
            notAnswered[card.key] = Self.why(error)
        }
    }

    /// Sends the message that didn't go, again. If the first try reached tafs cloud after all
    /// (its answer was lost), the thread already has it: then nothing is sent a second time.
    func retry() async {
        guard case .loaded(let coach, _) = state, let tried = pending, tried.failed != nil else { return }
        if let page = try? await read(coach), page.hasPersonsLast(tried.text, since: tried.at) {
            pending = Pending(text: tried.text, at: tried.at)
            show(coach, page)
            pending = nil
            if page.working { await follow(coach) }
            return
        }
        await deliver(tried.text, to: coach, firstTried: tried.at)
    }

    /// The person read the consent's words and allows AI use: then their message goes.
    func allowAI() async {
        guard let asked = consent, case .loaded(let coach, _) = state else { return }
        // A message with files refused for the consent went back to the composer: Allow then
        // only allows, and the words and files wait there to send again, as the iPad's consent
        // screen (AppModel.swift:6791-6800, 7767-7773).
        guard let text = pending?.text else {
            consent = nil
            do { try await cloud.allowAI(version: asked.version) } catch { fileNotice = Self.why(error) }
            return
        }
        consent = nil
        do {
            try await cloud.allowAI(version: asked.version)
            await deliver(text, to: coach, firstTried: pending?.at)
        } catch {
            pending?.failed = Self.why(error)
        }
    }

    /// Not now: nothing is allowed, and the message stays unsent. Only while the consent is
    /// being asked: a sheet that closes after Allow calls this late, and then it does nothing.
    func declineAI() {
        guard consent != nil else { return }
        consent = nil
        pending?.failed = ""
    }

    /// Sends a message, with its files when it has some. False when a message with files
    /// wasn't taken: it goes back to the composer, files and all, with why, as the iPad's
    /// `deliverSetupOnce` (AppModel.swift:7781-7790); one without files stays as not sent.
    @discardableResult
    private func deliver(_ text: String, to coach: Coach, firstTried: Date? = nil, files sent: [AttachmentRef] = []) async -> Bool {
        pending = Pending(text: text, at: firstTried ?? now(), files: sent)
        stopped = nil
        var mine = conversation
        do {
            // An improvement's first message goes through tafs cloud, which adds the taf's
            // context; the conversation goes on as any other (the iPad's `deliverSetup`).
            // A trial's turn goes to the trial's own chat, then it's followed as any other.
            if trial {
                try await cloud.trialMessage(to: coach.id, text: text)
                guard mine == conversation else { return true }
                await follow(coach)
                return true
            }
            if isCoach, let taf = improving {
                let sent = try await cloud.improve(taf.id, text: text)
                guard mine == conversation else { return true }
                improving = nil
                pending?.id = sent.message?.id
                settle(sent.session)
                await follow(coach)
                return true
            }
            if let streamer, let request = cloud.streamRequest(text, to: coach.id, target: target, files: sent) {
                var opened: AsyncThrowingStream<String, Error>?
                do {
                    opened = try await streamer.lines(request)
                } catch let refusal as CloudRefusal {
                    throw refusal
                } catch {
                    // The stream couldn't open. If tafs cloud has the message all the same, the
                    // thread is followed; only if it doesn't is the message sent plainly, below.
                    if let page = try? await read(coach), mine == conversation, let tried = pending,
                       page.hasPersonsLast(tried.text, since: tried.at, files: tried.files.map(\.id)) {
                        show(coach, page)
                        pending = nil
                        await follow(coach)
                        return true
                    }
                }
                if let opened {
                    // tafs cloud answered the stream route: it has the message. Whatever the
                    // stream does from here, the message is never sent again.
                    let started = mine
                    let task = Task { await self.stream(opened, coach, started) }
                    streaming = task
                    await task.value
                    return true
                }
            }
            let answer = try await cloud.send(text, to: coach.id, target: target, files: sent)
            guard mine == conversation else { return true }
            settle(answer.session)
            if followNew(answer.session, newSession: answer.newSession, coach) { mine = conversation }
            pending?.id = answer.message?.id
            await follow(coach)
        } catch let refusal as CloudRefusal where refusal.needsConsent {
            guard mine == conversation else { return true }
            live = nil
            consent = refusal.consent
            // With files, it goes back to the composer, to send once allowed.
            if !sent.isEmpty { pending = nil; return false }
        } catch {
            guard mine == conversation else { return true }
            live = nil
            if !sent.isEmpty {
                pending = nil
                fileNotice = Self.fileWhy(error)
                return false
            }
            pending?.failed = Self.why(error)
        }
        return true
    }

    /// Draws the answer as its events come, then reads the thread, which has it whole. A
    /// stream that breaks, at any point, only ends the drawing: the thread has the rest.
    private func stream(_ lines: AsyncThrowingStream<String, Error>, _ coach: Coach, _ started: Int) async {
        var reader = EventReader()
        var answer = LiveAnswer()
        var mine = started
        live = answer
        do {
            for try await line in lines {
                // A new conversation since: this answer is the one before's, and tafs cloud keeps it.
                guard mine == conversation else { return }
                guard let event = reader.read(line) else { continue }
                if case .session(let session, let newSession, let id) = event {
                    if followNew(session, newSession: newSession, coach) { mine = conversation } else { settle(session) }
                    pending?.id = id
                }
                if case .end(let words) = event {
                    stopped = words
                    break
                }
                if case .broke = event { break }
                if answer.take(event) {
                    await reload(coach)
                    guard mine == conversation else { return }
                }
                live = answer
            }
        } catch {}
        // A new conversation since: what follows the end is the new one's, never this answer's.
        guard mine == conversation else { return }
        streaming = nil
        live = nil
        await follow(coach)
        // A new conversation while this one was followed: its message is the new one's, as the
        // iPad's `followSetupStream` checks again after `loadSetupThread`.
        guard mine == conversation else { return }
        // The message was taken even if the thread didn't show it in time: it is not left
        // looking unsent, with a Retry that would send it again.
        if pending?.failed == nil { pending = nil }
    }

    private func reload(_ coach: Coach) async {
        let mine = conversation
        guard let page = try? await read(coach), mine == conversation else { return }
        show(coach, page)
        take(page)
    }

    // MARK: An app connected: the receipt, as the iPad's `ConnectApprovalSheet.receipt`

    /// The receipt of an app connected while Coach's chat was shown (`ConnectReceipt`), until
    /// Done; nil draws none.
    @Published private(set) var receipt: ConnectReceipt?
    /// The chat the page shown was read for: a page is compared only with the same chat's.
    private var pageChat: String?

    /// Shows a page read for the chat shown. A connection card it had without its connection
    /// made, marked made now, shows its receipt: on this Mac, that's where an app's sign-in
    /// finishes (`ConnectReceipt.made`). Coach's own chat only: a taf's connects nothing.
    private func show(_ coach: Coach, _ page: Thread.Page) {
        if isCoach, case .loaded(let shown, let before) = state, shown.id == coach.id, pageChat == chat,
           let made = ConnectReceipt.made(before: before, after: page) {
            receipt = made
        }
        pageChat = chat
        state = .loaded(coach, page)
    }

    /// Done on the receipt, as the iPad's `finish`: it closes, and the chat stays as read.
    func closeReceipt() { receipt = nil }

    /// While Coach's chat waits on a connection (`ConnectReceipt.watches`), it is read again, backing off with jitter
    /// (`Backoff.connection`), at most `watchAtMost` times, so the sign-in made on the phone shows its receipt here. Only while Coach is on screen (`CoachView`'s task).
    static let watchAtMost = Backoff.connection.reads

    /// Whether Coach's own chat waits on a connection.
    var watchesConnection: Bool {
        guard isCoach, case .loaded(_, let page) = state else { return false }
        return ConnectReceipt.watches(page)
    }

    /// Reads the chat again while it waits on a connection. A message on its way, or an answer
    /// being written, has its own reads: none is added then.
    func watchConnection() async {
        for n in 0..<Self.watchAtMost {
            guard watchesConnection, !Task.isCancelled, (try? await sleep(Backoff.connection.wait(n))) != nil, !Task.isCancelled else { return }
            guard watchesConnection, !sending, live == nil, case .loaded(let coach, _) = state else { continue }
            await reload(coach)
        }
    }

    /// Reads the thread again while an answer is owed. A newer send takes over the following.
    private func follow(_ coach: Coach) async {
        following += 1
        let mine = following
        for n in 0..<Self.followAtMost {
            guard mine == following, let page = try? await read(coach), mine == following else { return }
            show(coach, page)
            take(page)
            if pending == nil, !page.working { return }
            guard (try? await sleep(Backoff.answer.wait(n))) != nil else { return }
        }
    }

    enum ReportOutcome: Equatable { case sent, already, failed(String) }

    /// Moves on when the person signs out, as the iPad's `accountGeneration`: an answer that
    /// comes after is the session before's.
    private(set) var accountGeneration = 0
    /// The session ended: what comes back for it is dropped, and the files picked or opened
    /// with it go, as the iPad's sign-out (`chatFiles = [:]`, `removeOpenedFiles`).
    func signedOut() {
        accountGeneration += 1
        grants = []
        drafts = [:]
        coachTools = nil
        files = ChatFiles()
        fileNotice = nil
        Self.removeOpenedFiles()
    }

    // MARK: Start, as the iPad's `startSetup`

    /// A start on its way: Start says "Starting…" and waits, as the iPad's `startingSetup`.
    @Published private(set) var startingSetup = false
    /// Why the last start didn't go, as the iPad's `setupError`.
    @Published private(set) var setupError: String?
    /// Whether this Mac is set up with planque for the account, as the iPad's `planqueReady`:
    /// for this session.
    private(set) var planqueReady = false

    /// Starts Coach, as the iPad's `startSetup` and Windows' `StartAsync` on its passkey route
    /// (`CoachStart.start`): Setup's draft approved by this Mac's security key through the PIN
    /// sheet (`sign`), planque, then the draft sent and claimed; then Coach's thread is read. Only
    /// Coach's own chat starts.
    @discardableResult
    func startSetup(account: AccountClient, approval: PasskeySession?, sign: @escaping (Data) async throws -> PasskeySession.Signed,
                    confirm: @escaping () async throws -> Void, enrol: @escaping (@escaping () -> Bool) async -> PlanqueEnrolment.Stop?,
                    words: Words) async -> Bool {
        guard isCoach, !startingSetup else { return false }
        startingSetup = true
        defer { startingSetup = false }
        let gen = accountGeneration
        let coach: Coach?
        if case .loaded(let known, _) = state { coach = known } else { coach = nil }
        let (outcome, ready) = await CoachStart.start(coach: coach, planqueReady: planqueReady, cloud: cloud, account: account, approval: approval,
                                                     sign: sign, confirm: confirm, enrol: enrol,
                                                     ended: { [weak self] in self?.accountGeneration != gen }, words: words)
        guard gen == accountGeneration else { return false }
        planqueReady = ready
        switch outcome {
        case .started:
            setupError = nil
            await load()
            return true
        case .firstStart:
            // tafs cloud's first start, signed once with Coach's tools: not on this Mac yet.
            setupError = words("approval.device_can_not_approve_approve")
            return false
        case .stopped(let why):
            if let why { setupError = why }
            return false
        }
    }

    /// While Coach isn't there and this Mac can't start it, Coach is started on a device that can
    /// (the phone): Setup is read again until it's there, then its thread shows here. Only reads.
    /// It backs off with jitter and stops after `Backoff.start.reads` (about an hour), so a Mac left open doesn't read
    /// forever (tafs docs/scale.md); the screen's next open reads it again.
    func followStart() async {
        let gen = accountGeneration
        for n in 0..<Backoff.start.reads {
            guard state == .notStarted, gen == accountGeneration, !Task.isCancelled else { return }
            do { try await sleep(Backoff.start.wait(n)) } catch { return }
            guard gen == accountGeneration, !Task.isCancelled else { return }
            await load()
        }
    }

    /// Reports an answer in this chat to tafs cloud, with its chat's session, as the iPad's
    /// `reportAnswer`: tafs cloud's words when it refuses with some; a gone answer says so; any
    /// other failure is the app's own line, since tafs cloud's codes are for developers.
    func report(_ message: Thread.Message, reason: AnswerReport.Reason, note: String) async -> ReportOutcome {
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .loaded(let coach, _) = state, let id = message.id else { return .failed(Words.app("report.cant_from_here")) }
        let gen = accountGeneration
        do {
            let kept = try await cloud.report(id, of: coach.id, reason: reason, note: note.isEmpty ? nil : note, session: message.session)
            // Signed out while it went: what tafs cloud answered is the session before's.
            guard gen == accountGeneration else { return .failed(Words.app("common.you_signed_out")) }
            return kept.new ? .sent : .already
        } catch let refusal as CloudRefusal where refusal.words != nil {
            return .failed(refusal.words!)
        } catch let refusal as CloudRefusal where refusal.status == 404 {
            return .failed(Words.app("needs_you.answer_gone"))
        } catch {
            return .failed(Words.app("kiff.did_not_reach_kiff_try"))
        }
    }

    /// tafs cloud's words for a refusal, as the iPad's `CloudError`; else the network's own words.
    static func why(_ error: Error) -> String { NeedsYouModel.why(error) }

    func load() async {
        do {
            let found: Coach?
            if let fixed {
                found = fixed
            } else {
                // Coach's tools come with the same read, as the iPad's `setupRead`'s `tools`.
                let (setup, tools) = try await cloud.coachAndTools()
                found = setup
                coachTools = tools
            }
            guard let coach = found else { state = .notStarted; return }
            // Coach opens on its newest chat, as the iPad's `loadSetupThread`; without the list,
            // or with none yet, the thread reads as before.
            let mine = conversation
            if isCoach, chat == nil, !fresh, let chats = try? await cloud.chats(of: coach.id), mine == conversation,
               let newest = chats.max(by: { $0.updated < $1.updated }) {
                // A chat set aside here is never the one Coach goes on in: a new conversation
                // instead, as the iPad's `loadSetupThread` (AppModel.swift:8036-8037).
                if setAsideChats.contains(newest.session) { newWhenRead = true } else { chat = newest.session }
            }
            guard mine == conversation else { return }
            show(coach, try await read(coach) ?? .empty)
            if let taf = improveWhenRead {
                improveWhenRead = nil
                improve(taf)
            } else if newWhenRead {
                newWhenRead = false
                newChat()
            }
        } catch {
            state = .unread(why: NeedsYouModel.why(error))
        }
    }
}

/// Coach's chat: read it, and write to Coach. Answering its cards arrives in its own pull
/// request.
struct CoachView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: CoachModel
    var canApprove = false
    /// Whether an approval can be signed on this Mac. Approve comes with approvals (#16): turn
    /// this on only with its button, never alone.
    /// Opens a hand-over's taf, by its KIFF agent.
    var openTaf: (String?) -> Void = { _ in }
    /// The KIFF agents of the tafs listed: a hand-over shows its button once its taf is one.
    var listed: Set<String> = []
    /// How many tafs the account has, as the iPad's `model.tafs.count`: its empty chat draws
    /// board 7 with none or one (`ArtBoard.coach`).
    var tafCount = 0
    /// Whether this person manages the account's Cards (KIFF's `cards.manage`): the connect
    /// receipt draws Disconnect only then, as the iPad's.
    var managesCards = true
    /// Opens Plan & usage, for a hand-over whose taf needs a plan.
    var openUsage: () -> Void = {}
    /// Whether this person may use Coach, as the iPad's `mayUseCoach`: only then are its cards
    /// answered here.
    var mayUseCoach = false
    /// Starts Coach for the account, on a Mac that may (`CoachStart.mayStart`: its security key
    /// approves); nil on one that can't approve, which says so and follows the start made on the
    /// phone.
    var start: (() async -> Void)? = nil
    /// Closes Coach, back to the screen it opened over, as the iPad's Coach mode's Back; nil
    /// draws no Back.
    var close: (() -> Void)? = nil
    /// Coach's own screen has its name at the top and its wash; a taf's chat sits in its page.
    var embedded = false
    /// Coach over the screen fills the window while this is on, as the iPad's ⤢; nil draws no ⤢.
    var fullScreen: Binding<Bool>? = nil
    /// The tafs listed, for the taf a new version's card is about (`Thread.Card.improvedTaf`).
    var tafs: [Home.Taf] = []
    /// A taf's versions, by its tafs cloud id, for a new version's See version; nil opens none.
    var versions: ((String) -> TafPagesModel?)? = nil
    /// The Versions sheet a new version's card opened.
    @State private var versionsShown: CoachVersions?
    /// The answered approvals opened again from their folded line, by card key.
    @State private var opened: Set<String> = []
    /// The answers whose work is unfolded, and the plan.
    @State private var unfolded: Set<Int> = []
    /// The answer being reported, in its sheet.
    @State private var reporting: ReportedAnswer?
    /// Previous conversations is open.
    @State private var showingChats = false
    /// Speaking a message instead of typing it, into this chat's box (`MicButton`).
    /// The signed-in app's one dictation, as the iPad's `model.dictation`; nil draws no mic.
    var dictation: Dictation? = nil
    /// The words the person is likely to say, so dictation spells them right (`Dictating.hints`).
    var hints: [String] = []
    /// In a taf's chat, Ask Coach on its `ask_coach` cards: Coach on the taf with the card's words
    /// in its box, nothing sent, as the iPad's `askCoachAbout`. Nil for someone who may not, who
    /// reads the card alone.
    var askCoach: ((String) -> Void)? = nil
    /// In a taf's page, its chat scrolled a step down (true) or up (false): the page folds its header line,
    /// as the iPad's `TafChatView(onScroll:)`. Nil reads nothing.
    var onScroll: ((Bool) -> Void)? = nil
    @State private var scrollFold = ScrollFold()
    @State private var planOpen = false
    /// Coach's width, for "Taking shape" beside its conversation at 780 or wider.
    @State private var width: CGFloat = 0

    /// "Taking shape" shows beside the conversation, as the iPad's `shaping`: Coach's own screen,
    /// read, at least 780 across (dragged wide, or ⤢), while planque can be read for its tools
    /// (`readsPlanque`). The plan then shows there, not in the chat.
    private var shaping: Bool {
        guard !embedded, model.readsPlanque, case .loaded = model.state else { return false }
        return SetupShape.shows(width: Double(width), coach: model.isCoach)
    }

    var body: some View {
        HStack(spacing: 0) {
            chat
            if shaping, let shape = model.shape(words) {
                Rectangle().fill(Theme.line).frame(width: 1)
                SetupShapePanel(shape: shape).frame(width: CGFloat(SetupShape.width))
            }
        }
        .background(GeometryReader { space in Color.clear.preference(key: CoachWidth.self, value: space.size.width) })
        .onPreferenceChange(CoachWidth.self) { width = $0 }
        // What Coach's cards name, read as they change: planque's grants and KIFF's drafts.
        .task(id: model.named) { await model.readNamed() }
    }

    /// The conversation, with its title row above and its message box below.
    private var chat: some View {
        Group {
            // A taf's chat with nothing in it yet is its empty thread, never Coach mode's start.
            if model.isEmpty, !embedded {
                // Coach mode's start, centred in the height, as the iPad's.
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 18)
                    intro
                    Spacer(minLength: 18)
                }
                .padding(.horizontal, Look.inset)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                thread
            }
        }
        .background(embedded ? Theme.background : Theme.coachWash)
        // The screen's name sits small and centred on the background's own colour, as on the iPad.
        .safeAreaInset(edge: .top, spacing: 0) {
            if !embedded {
                VStack(spacing: 0) {
                    header
                        .background(Theme.background)
                    // Coach's tools still to give, one line above the conversation, as the iPad's `CoachToolsRow`.
                    if model.isCoach, let tools = model.coachTools, tools.showsRow { CoachToolsRow(tools: tools) }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .task { await model.load() }
        .sheet(item: Binding(get: { model.consent }, set: { if $0 == nil { model.declineAI() } })) { consent in
            consentSheet(consent)
        }
        .sheet(item: $reporting) { ReportAnswerSheet(model: model, answer: $0).environment(\.words, words) }
        // An app connected while Coach is shown: its receipt, as the iPad's (docs/connections.md › The receipt).
        .sheet(item: Binding(get: { model.receipt }, set: { if $0 == nil { model.closeReceipt() } })) { receipt in
            ConnectReceiptSheet(receipt: receipt, managesCards: managesCards, done: { model.closeReceipt() }).environment(\.words, words)
        }
        // Coach's chat is read again while a connection waits, so its sign-in's end is seen here.
        .task(id: model.watchesConnection) { if model.watchesConnection { await model.watchConnection() } }
        .sheet(isPresented: $showingChats) {
            CoachChatsSheet(model: model, watch: model.watchDays()) { session in
                showingChats = false
                Task { await model.open(chat: session) }
            }
            .environment(\.words, words)
        }
    }

    /// Coach's title row, as the iPad's Coach mode: ⤢ and Back on the left, Back closing Coach (Esc
    /// too), and on the right New conversation (the pencil) and the conversations' menu with
    /// Previous conversations (`CoachMode.swift:13-31`, `SetupChatView.swift:105-110`).
    private var header: some View {
        HStack(spacing: 14) {
            // ⤢ first, then Back, as the iPad's Coach mode orders them (`CoachMode.swift:13-31`).
            if let fullScreen { fullScreenButton(fullScreen) }
            if let close {
                Button(action: close) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                        Text(words("common.back")).font(.system(size: 14))
                    }
                    .foregroundColor(Theme.coach).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(words("common.back"))
            }
            Spacer(minLength: 0)
            // New conversation, as the iPad's `newConversation`: an empty chat is already one.
            Button { if !model.chatIsEmpty { model.newChat() } } label: {
                Image(systemName: "square.and.pencil").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.soft)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(words("coach.new_conversation"))
            Menu {
                Button(words("coach.chats.previous")) { showingChats = true }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.soft)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(words("coach.conversations"))
        }
        .padding(.horizontal, Look.inset)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        // The screen's name, centred over the row whatever its ends hold.
        .overlay {
            Text(words("coach.title")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                .accessibilityAddTraits(.isHeader)
                .allowsHitTesting(false)
        }
    }

    /// ⤢, as the iPad's (CoachMode.swift:19-26): Coach fills the window, and goes back to the
    /// width it had.
    private func fullScreenButton(_ full: Binding<Bool>) -> some View {
        Button { full.wrappedValue.toggle() } label: {
            Image(systemName: full.wrappedValue ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.coach)
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(words(full.wrappedValue ? "coach.back_width" : "coach.full_screen"))
    }

    /// A new version's card, with See version opening that taf's Versions here.
    private func improvement(_ card: Thread.Card) -> some View {
        let taf = card.improvedTaf(in: tafs)
        let make = versions
        var open: ((Home.Taf) -> Void)?
        if let make, taf?.tafID != nil {
            open = { chosen in
                if let id = chosen.tafID, let model = make(id) { versionsShown = CoachVersions(model: model) }
            }
        }
        return ImprovementCard(card: card, taf: taf, openVersions: open)
    }

    private var thread: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch model.state {
                case .loading:
                    ProgressView().controlSize(.small)
                case .notStarted:
                    // Coach's own screen shows its start instead; a taf's chat is never unstarted.
                    EmptyView()
                case .unread(let why):
                    Text(words("coach.conversation_not_loaded", ["why": why])).font(.system(size: 14)).foregroundColor(Theme.no)
                    Button(words("common.try_again")) { Task { await model.load() } }
                case .loaded(_, let page):
                    ForEach(Array(page.items.enumerated()), id: \.offset) { index, item in
                        // A time on the first item, and after an hour's gap, as on the iPad.
                        if page.showsTime(at: index), let at = item.at {
                            Text(verbatim: Self.when(at, words: words)).font(.system(size: 12)).foregroundColor(Theme.dim).frame(maxWidth: .infinity)
                        }
                        self.item(item)
                    }
                    if let pending = model.pending { unsent(pending) }
                    if let live = model.live { writing(live) }
                    if let stopped = model.stopped {
                        Text(verbatim: stopped).font(.system(size: 13)).foregroundColor(Theme.no)
                    }
                    if page.working, model.live == nil {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(words("chat.working")).font(.system(size: 13)).foregroundColor(Theme.soft)
                        }
                    }
                    // A past chat that couldn't be reopened: what was shown stays, as the iPad's.
                    if let why = model.notReopened, let chat = model.chat {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(words("coach.conversation_not_loaded", ["why": why])).font(.system(size: 14)).foregroundColor(Theme.no)
                            Button(words("common.try_again")) { Task { await model.open(chat: chat) } }
                        }
                    }
                }
            }
            .padding(.horizontal, Look.inset).padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { drawn in
                Color.clear.preference(key: ThreadTop.self, value: drawn.frame(in: .named(ThreadTop.space)).minY)
            })
        }
        .coordinateSpace(name: ThreadTop.space)
        .onPreferenceChange(ThreadTop.self) { top in
            guard let onScroll, let down = scrollFold.moved(to: top) else { return }
            onScroll(down)
        }
        // A new version's See version: that taf's Versions, as the iPad's `VersionsScreen`.
        .sheet(item: $versionsShown) { shown in
            VersionsView(model: shown.model) { versionsShown = nil }.environment(\.words, words)
        }
    }

    /// A taf's chat says "Message {taf}", and "Write the next message" while the taf works;
    /// Coach's says "Ask anything", and "Write the next message" while Coach works.
    private var placeholder: String {
        guard embedded else { return words(model.working ? "chat.write_next" : "coach.ask_anything") }
        guard case .loaded(let taf, let page) = model.state else { return words("chat.write_next") }
        return page.working || model.live != nil ? words("chat.write_next") : words("chat.message_taf", ["taf": taf.name])
    }

    /// The message box, to the iPad's: a rounded panel with the words, and the send circle at
    /// its foot. Return sends; nothing goes until the person sends it.
    @ViewBuilder private var composer: some View {
        if case .loaded = model.state {
            VStack(alignment: .leading, spacing: 0) {
            // The files for the next message, above the box, as the iPad's `FileTray`.
            FileTray(model: model)
            // While Coach improves a taf, files in the tray wait for the next message: the words go alone.
            if model.improvementHoldsFiles {
                Text(words("coach.improve_no_files")).font(.system(size: 13)).foregroundColor(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 26).padding(.top, 8)
                    .accessibilityIdentifier("coach.improve-no-files")
            }
            VStack(alignment: .leading, spacing: 4) {
                // While Coach or the taf works, the box asks for the next message, as on the iPad.
                TextField(placeholder, text: $model.draft)
                    .textFieldStyle(.plain).font(.system(size: 16))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .onSubmit { send() }
                HStack {
                    // The paperclip, where files can go: not on a new conversation that improves a taf.
                    if model.filesTarget != nil { AttachButton(model: model) }
                    Spacer()
                    // Speak instead of typing, as the iPad's: the words wait in the box, unsent.
                    if let dictation {
                        MicButton(dictation: dictation, text: $model.draft, hints: hints.isEmpty ? Dictating.hints(tafs: []) : hints)
                    }
                    Button { send() } label: {
                        Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundColor(Theme.onFill)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Theme.coach.opacity(model.canSend ? 1 : 0.4)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canSend)
                    .accessibilityLabel(words(model.files.sendKey(working: model.working, improving: model.improving != nil)))
                }
                .padding(.horizontal, 8).padding(.bottom, 8)
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.line))
            .padding(.horizontal, 12).padding(.vertical, 10)
            }
            // The iPad's bar: the background with a faint shadow upward, apart from the wash.
            .background(Theme.background.shadow(color: Theme.ink.opacity(0.06), radius: 6, x: 0, y: -2))
            // Leaving the chat stops dictating, so its words never land in another chat's box.
            .onDisappear { leave() }
            if let dictation { DictationBar(dictation: dictation) }
        }
    }

    /// Leaving the chat stops dictating, so its words never land in another chat's box, as the
    /// iPad's `.onDisappear { model.dictation.stop() }` (SetupChatView.swift:759).
    func leave() { dictation?.stop() }

    /// Sending stops dictating, as the iPad's `send()`: what was heard goes with it, as it
    /// stands in the box.
    func send() {
        dictation?.stop()
        Task { await model.send() }
    }

    /// The answer as it is written, as on the iPad: the live line, the steps done under it,
    /// then Coach's words so far.
    private func writing(_ live: LiveAnswer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(verbatim: live.line ?? words("chat.thinking")).font(.system(size: 13)).foregroundColor(Theme.dim)
            }
            if !live.rows.isEmpty { steps(live.rows) }
            if !live.text.isEmpty { SteadyText(text: live.text) { rich($0) } }
        }
    }

    /// A run's steps, folded, as the iPad's `StepList`: a mark, the step's words, and "not made
    /// · read first" or "{n} tries" beside them.
    private func steps(_ rows: [WorkRows.Row]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: row.status == .error ? "exclamationmark.circle" : row.status == .notMade ? "arrow.uturn.left" : "checkmark")
                        .font(.system(size: 11)).foregroundColor(row.status == .error ? Theme.no : Theme.dim).frame(width: 14)
                    Text(verbatim: row.words.hasSuffix("…") ? String(row.words.dropLast()) : row.words)
                        .font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
                    if row.status == .notMade {
                        Text(words("chat.work.not_made_read_first")).font(.system(size: 12)).foregroundColor(Theme.dim)
                    } else if row.tries > 1 {
                        Text(words.count("chat.work.tries", row.tries)).font(.system(size: 12)).foregroundColor(Theme.dim)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.leading, 6)
        .overlay(Rectangle().fill(Theme.line).frame(width: 1), alignment: .leading)
        .padding(.leading, 4)
    }

    /// Coach's or a taf's words, as the iPad's `MarkdownText` draws them: no mark shows, and a
    /// link is its label only.
    private func rich(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Rich.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let spans):
                    line(spans)
                case .heading(let spans):
                    line(spans, size: 17, weight: .semibold)
                case .bullet(let spans):
                    item("•", spans)
                case .numbered(let number, let spans):
                    item(number, spans)
                case .code(let lines):
                    // As the iPad's code block: the lines as written, in mono, on the raised ground.
                    Text(verbatim: lines).font(.system(size: 14, design: .monospaced)).foregroundColor(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised))
                }
            }
        }
        .textSelection(.enabled)
    }

    private func item(_ mark: String, _ spans: [Rich.Span]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: mark).font(.system(size: 16)).foregroundColor(Theme.ink)
            line(spans)
        }
    }

    private func line(_ spans: [Rich.Span], size: CGFloat = 16, weight: Font.Weight = .regular) -> some View {
        spans.reduce(Text(verbatim: "")) { all, span in
            var piece = Text(verbatim: span.text)
            if span.code { piece = piece.font(.system(size: size - 1, design: .monospaced)) }
            if span.bold { piece = piece.fontWeight(.semibold) }
            if span.italic { piece = piece.italic() }
            return all + piece
        }
        .font(.system(size: size, weight: weight)).foregroundColor(Theme.ink).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
    }

    /// The person's message, faded until the thread has it; with why and Retry if it didn't go.
    private func unsent(_ pending: CoachModel.Pending) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Spacer(minLength: 48)
                // Still going: the whole bubble at 0.7, as on the iPad; one that didn't go, fainter.
                if !pending.text.isEmpty {
                    Text(verbatim: pending.text).font(.system(size: 15)).foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.brand))
                        .opacity(pending.failed == nil ? 0.7 : 0.45)
                }
            }
            if !pending.files.isEmpty { MessageFiles(model: model, files: pending.files).opacity(0.7) }
            if let why = pending.failed {
                HStack(spacing: 8) {
                    Text(why.isEmpty ? words("chat.not_sent_short") : words("coach.answer.failed_why", ["value": why]))
                        .font(.system(size: 12)).foregroundColor(Theme.no)
                    Button(words("chat.retry")) { Task { await model.retry() } }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.coach)
                }
            } else {
                Text(words("common.sending")).font(.system(size: 12)).foregroundColor(Theme.dim)
            }
        }
    }

    /// The AI-data consent, in tafs cloud's words: what is sent to the AI, Allow and Not now.
    private func consentSheet(_ consent: TafsCloud.AIConsent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: consent.words.title).font(Theme.display(20)).foregroundColor(Theme.ink)
            ForEach(Array(consent.words.lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line).font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(consent.words.notNow) { model.declineAI() }.key(ConsentKeys.notNow)
                Spacer()
                // No key allows: consent is a deliberate click, never the Return that sent the message.
                Button(consent.words.allow) { Task { await model.allowAI() } }.key(ConsentKeys.allow)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: 460)
    }

    /// Coach mode's start, as the iPad's `introBefore`: its name in 30 rounded bold in Coach's
    /// colour, then the lead in 16 soft. The lead is the Mac's own shared line: the iPad's says
    /// the person approves with Face ID, which this Mac can't do yet.
    @ViewBuilder private var intro: some View {
        if let taf = model.improving {
            improvingStart(taf)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                // Board 9 before Coach is started (the iPad's `introBefore`, at its width), board 7 in
                // an empty chat with no taf or one (its `starts`): docs/window.md › Illustrations.
                switch ArtBoard.coach(started: model.state != .notStarted, improving: false, tafs: tafCount) {
                case .coachStarting?: Illustration.coachStarting.frame(maxWidth: .infinity)
                case .coachFirst?: Illustration.coachFirst
                default: EmptyView()
                }
                Text(words("coach.coach_mode")).font(Theme.display(30)).foregroundColor(Theme.coach)
                    .accessibilityAddTraits(.isHeader)
                Text(words("coach.ask_anything_line")).font(.system(size: 16)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
                if model.isCoach, model.state == .notStarted { startArea }
            }
        }
    }

    /// Start, for an account with no Coach yet, as the iPad's `introBefore`: Start on a Mac whose
    /// security key approves (the PIN sheet asks for its PIN); else why it can't, in the words for
    /// a device that can't approve, while Coach is started on the phone and read again here until
    /// it's there.
    @ViewBuilder private var startArea: some View {
        if let why = model.setupError {
            Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
        }
        if let start {
            Button(words(model.startingSetup ? "common.starting" : "coach.start")) { Task { await start() } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.startingSetup)
        } else {
            Text(words("approval.device_can_not_approve_approve")).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .task { await model.followStart() }
        }
    }

    /// A new conversation on a taf, as the iPad's `starts` while improving: what it's about as
    /// a choice (a new taf, or this one), "Improve {taf}", what Coach starts from, and three
    /// examples that send as they are.
    private func improvingStart(_ taf: CoachModel.Improving) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                startChoice(words("home.new_taf"), selected: false) { model.newChat() }
                startChoice(words("coach.improve_taf", ["taf": taf.name]), selected: true) {}
            }
            .padding(3)
            .background(Theme.panel)
            .overlay(Capsule().stroke(Theme.line))
            .clipShape(Capsule())
            .accessibilityElement(children: .contain)
            .accessibilityLabel(words("coach.what_conversation_about"))
            Text(words("coach.improve_taf", ["taf": taf.name])).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(words("coach.improve_line", ["name": taf.name])).font(.system(size: 15)).foregroundColor(Theme.soft)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Self.improveExamples, id: \.self) { key in
                Button { Task { await model.send(example: words(key)) } } label: {
                    Text(words(key)).font(.system(size: 15)).foregroundColor(Theme.ink).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Theme.panel)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(model.sending)
            }
        }
        .padding(.vertical, 16)
    }

    /// The iPad's `improveExamples`, by their keys.
    static let improveExamples = ["coach.improve.how_is_it_going", "coach.improve.why_refused", "coach.improve.cant_find_work"]

    private func startChoice(_ title: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button { if !selected { action() } } label: {
            Text(verbatim: title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                .foregroundColor(selected ? Theme.onFill : Theme.coach)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(selected ? Theme.coach : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.sending)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }


    /// "Worked for 32 s", which opens the steps the run took.
    private func workFold(_ work: Thread.Work, id: Int) -> some View {
        let rows = work.rows
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                if unfolded.contains(id) { unfolded.remove(id) } else { unfolded.insert(id) }
            } label: {
                HStack(spacing: 4) {
                    Text(words("chat.work.worked_for", ["ms": work.took(words)])).font(.system(size: 13)).foregroundColor(Theme.dim)
                    if !rows.isEmpty {
                        Image(systemName: unfolded.contains(id) ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.dim)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(rows.isEmpty)
            if unfolded.contains(id) { steps(rows) }
        }
    }

    /// A time in the chat: the time today, else the date and the time.
    static func when(_ at: Date, words: Words) -> String {
        AppDates.formatter(words, date: Calendar.current.isDateInToday(at) ? .none : .medium, time: .short).string(from: at)
    }

    @ViewBuilder private func item(_ item: Thread.Item) -> some View {
        switch item {
        case .message(let message, _):
            if message.isNote {
                Text(verbatim: message.text).font(.system(size: 12)).foregroundColor(Theme.dim)
            } else {
                // The words are a person's or the model's: plain text, never a line of the app's.
                if message.fromPerson {
                    // The person's words on the brand's gradient, then the files sent with them.
                    VStack(alignment: .trailing, spacing: 6) {
                        if !message.text.isEmpty {
                            HStack {
                                Spacer(minLength: 48)
                                Text(verbatim: message.text).font(.system(size: 15)).foregroundColor(.white)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.brand))
                            }
                        }
                        if !message.attachments.isEmpty { MessageFiles(model: model, files: message.attachments) }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    // Coach's words, as text on the page, with no bubble; its work folded above them.
                    VStack(alignment: .leading, spacing: 8) {
                        if let work = message.work { workFold(work, id: item.id) }
                        rich(message.text)
                    }
                    // Report this answer, on an answer that can be reported, as the iPad's `reportable`.
                    .contextMenu {
                        if AnswerReport.can(message) {
                            Button { reporting = ReportedAnswer(message: message) } label: {
                                Label(words("report.menu"), systemImage: "flag")
                            }
                        }
                    }
                }
            }
        case .card(let card, _):
            self.card(card)
        case .held:
            waiting(words("coach.needs_you_approve"))
        case .other:
            EmptyView()
        }
    }

    /// Ask Coach for an `ask_coach` card's words; nil without it.
    private func askingCoach(_ text: String) -> (() -> Void)? {
        guard let askCoach else { return nil }
        return { askCoach(text) }
    }

    /// A card, by its kind, as the iPad draws each.
    @ViewBuilder private func card(_ card: Thread.Card) -> some View {
        if let text = card.askCoach {
            AskCoachCard(text: text, ask: askingCoach(text))
        } else if card.isPlan {
            // Beside the conversation while "Taking shape" shows, as the iPad's (SetupChatView.swift:86).
            if !shaping { plan(card) }
        } else if card.isImprovement {
            improvement(card)
        } else if card.isHandOver {
            handOver(card)
        } else if card.type == "sign_in" {
            signIn(card)
        } else if card.grants {
            approval(card)
        } else if card.type == "notice" {
            notice(card)
        } else if card.type == "questions" {
            questions(card)
        } else if card.drawsAsChoice {
            // Never a drive's card: Coach driving the phone's screen is the phone's (docs/drive.md).
            choice(card)
        }
    }

    /// The plan: tafs cloud's line and the step in hand with its mark, opening to every step.
    private func plan(_ card: Thread.Card) -> some View {
        let current = card.plan.first { $0.status == "active" } ?? card.plan.first { $0.status != "done" && $0.status != "skipped" } ?? card.plan.last
        return VStack(alignment: .leading, spacing: 8) {
            Button { planOpen.toggle() } label: {
                HStack(spacing: 10) {
                    if !planOpen, let current { mark(current.status, size: 16) }
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: card.planLine ?? words("coach.plan.progress", ["done": words.number(card.planDone), "total": words.number(card.plan.count)]))
                        if !planOpen, let current {
                            Text(verbatim: current.label).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink).lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: planOpen ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.soft)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(words(planOpen ? "coach.plan.fold" : "coach.plan.show"))
            if planOpen {
                ForEach(Array(card.plan.enumerated()), id: \.offset) { _, step in
                    HStack(spacing: 10) {
                        mark(step.status, size: 18)
                        Text(verbatim: step.label).font(.system(size: 14, weight: step.status == "active" ? .semibold : .regular))
                            .foregroundColor(step.status == "pending" || step.status == "skipped" ? Theme.dim : Theme.ink)
                            .strikethrough(step.status == "skipped")
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
    }

    /// A plan step's mark: done, failed, an amber ring while active, else a faint ring.
    @ViewBuilder private func mark(_ status: String, size: CGFloat) -> some View {
        switch status {
        case "done": Image(systemName: "checkmark.circle.fill").font(.system(size: size)).foregroundColor(Theme.ok)
        case "failed": Image(systemName: "exclamationmark.circle.fill").font(.system(size: size)).foregroundColor(Theme.no)
        case "active": Circle().stroke(Theme.amber, lineWidth: 2).frame(width: size - 2, height: size - 2).frame(width: size, height: size)
        default: Circle().stroke(Theme.dim.opacity(0.5), lineWidth: 1.5).frame(width: size - 2, height: size - 2).frame(width: size, height: size)
        }
    }

    /// A note Coach leaves in the chat, as the iPad's: a panel in its tone's colour.
    private func notice(_ card: Thread.Card) -> some View {
        let tone: Color = card.tone == "error" ? Theme.no : card.tone == "warning" ? Theme.amber : card.tone == "success" ? Theme.ok : Theme.soft
        let titleColor: Color = card.tone == "error" ? Theme.no : card.tone == "warning" ? Theme.amberText : card.tone == "success" ? Theme.ok : Theme.soft
        return VStack(alignment: .leading, spacing: 4) {
            if let title = card.title { Text(verbatim: title).font(.system(size: 14, weight: .semibold)).foregroundColor(titleColor) }
            if let text = card.text { Text(verbatim: text).font(.system(size: 14)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tone.opacity(0.10)))
    }

    /// An answered card, folded into one line, as the iPad's `OutcomeLine`.
    /// `more`: a click opens the card again, which the iPad marks with a ⌄ at the line's end.
    private func outcomeLine(_ symbol: String, _ color: Color, _ text: String, detail: String? = nil, more: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundColor(color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: text).font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
                if let detail { Text(verbatim: detail).font(.system(size: 12)).foregroundColor(Theme.soft) }
            }
            Spacer(minLength: 0)
            if more { Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundColor(Theme.dim).accessibilityHidden(true) }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.raised.opacity(0.6)))
    }

    /// The hand-over: the taf Coach made, what it does, its tools, and the way to it. When it
    /// failed, why, and no button; when it needs a plan, the way to choose one.
    private func handOver(_ card: Thread.Card) -> some View {
        let name = card.tafName ?? ""
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: words("coach.result.set_up", ["taf": name]), color: Theme.ok)
            if let text = card.text { Text(verbatim: text).font(.system(size: 15)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true) }
            if !card.tools.isEmpty {
                // In words, as the iPad's (`KIFFMapping.toolWords`), never a tool's own name.
                // Each by its approval's title, else in words, as the iPad's `toolTitle` (SetupChatView.swift:1446).
                Text(verbatim: model.toolWords(card).joined(separator: " · ")).font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            }
            if let failed = card.outcome?.failed {
                Text(words("coach.not_set_up", ["name": name, "why": failed])).font(.system(size: 14)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
                Text(words("coach.coach_knows")).font(.system(size: 13)).foregroundColor(Theme.dim)
            } else {
                if let needed = card.outcome?.planNeeded {
                    Text(verbatim: needed).font(.system(size: 13)).foregroundColor(Theme.amberText).fixedSize(horizontal: false, vertical: true)
                    outline(words("usage.choose_plan"), color: Theme.ink, openUsage)
                }
                if card.tafAgent.map(listed.contains) == true {
                    Button { openTaf(card.tafAgent) } label: {
                        Text(verbatim: card.yes ?? words("coach.result.see_it", ["taf": name])).font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.brand)).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(words("coach.setting_up", ["name": name])).font(.system(size: 13)).foregroundColor(Theme.dim)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).stroke(Theme.ok))
    }

    /// The iPad's outlined button: 15 medium, at least 48 high, corner 14, its colour at 0.4.
    private func outline(_ title: String, color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title).font(.system(size: 15, weight: .medium)).foregroundColor(color)
                .frame(maxWidth: .infinity, minHeight: 48)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(color.opacity(0.4)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A sign-in, as the iPad's: "Needs you · sign in", "Sign in at {app}", its note, and Not
    /// now. Signing in is on the phone for now; Not now grants nothing.
    @ViewBuilder private func signIn(_ card: Thread.Card) -> some View {
        if card.answered != nil || !card.waitsForPerson {
            if let answered = card.answered { outcomeLine("checkmark.circle.fill", Theme.ok, [answered, card.service].compactMap { $0 }.joined(separator: " · ")) }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: words("coach.sign_in.eyebrow"), color: Theme.amberText)
                Text(card.service.map { words("coach.sign_in.at", ["vendor": $0]) } ?? words("coach.sign_in.at_vendor"))
                    .font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(Theme.ink)
                if let note = card.note ?? card.text { Text(verbatim: note).font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true) }
                // A sign-in that asks for more than the job, said above the button, in tafs cloud's words.
                if let wider = card.widerWords { WiderLine(words: wider) }
                Text(words("approval.device_can_not_approve_approve")).font(.system(size: 12)).foregroundColor(Theme.soft)
                if model.answering == card.key {
                    Text(words("coach.answering")).font(.system(size: 13)).foregroundColor(Theme.soft)
                } else {
                    Button { Task { await model.decline(card) } } label: {
                        Text(verbatim: card.no ?? words("common.not_now")).font(.system(size: 14)).foregroundColor(Theme.dim)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.answering != nil)
                }
                if let why = model.notAnswered[card.key] {
                    Text(words("coach.answer.failed_why", ["value": why])).font(.system(size: 12)).foregroundColor(Theme.no)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).stroke(Theme.amber))
        }
    }

    /// An approval, as the iPad's `SetupApproval` (SetupChatView.swift:1523-1546): one a newer request
    /// for the same connection replaced folds to a line of history; an answered one to a line of what
    /// was approved or declined; each opens again with a click, as `SetupApprovalCard`. Waiting or
    /// failed, the card. One the person wrote past draws nothing.
    private func approval(_ card: Thread.Card) -> some View {
        let replaced = model.replaced(card)
        let grant = model.grant(for: card)
        let draft = card.draft.flatMap { model.drafts[$0]?.draft }
        let state = ApprovalLines.state(card, grant: grant)
        let open = opened.contains(card.key)
        let done = state == .done
        let lines = ApprovalLines.signedLines(state, draft: draft, words)
        return Group {
            if replaced && !open {
                // A newer request for this connection is below: this one is history, and never shows
                // that connection's live state or its error.
                Button { opened.insert(card.key) } label: {
                    outcomeLine("arrow.down.circle.fill", Theme.dim, ApprovalLines.replacedLine(card, words), more: true).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(words("coach.shows_earlier_request"))
            } else if (done || state == .declined) && !open {
                Button { opened.insert(card.key) } label: {
                    outcomeLine(done ? "checkmark.circle.fill" : "minus.circle.fill", done ? Theme.ok : Theme.dim,
                                ApprovalLines.outcome(card, state, grant: grant, draft: draft, words),
                                detail: lines.isEmpty ? nil : lines.joined(separator: "\n"), more: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(words("coach.shows_approval"))
            } else if replaced || open || card.waitsForPerson || state.isFailure {
                SetupApprovalCard(model: model, card: card, replaced: replaced, state: state, grant: grant, canApprove: canApprove,
                                  open: open, fold: { opened.remove(card.key) })
            }
        }
    }

    /// Several questions at once, as the iPad's `QuestionsCard` (QuestionsCard.swift:17-24):
    /// answered, one folded line, "Your answers · {tafs cloud's words}"; with no answer, whatever
    /// `waits` says, the card, in Coach's own chat for someone who may use Coach; else what it asks.
    @ViewBuilder private func questions(_ card: Thread.Card) -> some View {
        if card.answerState == "answered" {
            outcomeLine("checkmark.circle.fill", Theme.ok, words("coach.questions.your_answers") + (card.answered ?? ""))
        } else if model.isCoach, mayUseCoach, card.isQuestions {
            QuestionsCard(model: model, card: card, mayUseCoach: mayUseCoach)
        } else {
            asking(card)
        }
    }

    /// A choice or a question: what it asks, as Coach wrote it, then its pills. Answered: one
    /// folded line, "{question} · {chosen}".
    @ViewBuilder private func choice(_ card: Thread.Card) -> some View {
        if let answered = card.answered {
            outcomeLine("checkmark.circle.fill", Theme.ok, [card.title ?? card.text, answered].compactMap { $0 }.joined(separator: " · "))
        } else {
            asking(card)
        }
    }

    private func asking(_ card: Thread.Card) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = card.title { Text(verbatim: title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink) }
            if let text = card.text { rich(text) }
            if card.waitsForPerson, card.isChoice {
                if model.answering == card.key {
                    Text(words("coach.answering")).font(.system(size: 13)).foregroundColor(Theme.soft)
                } else {
                    // The choices wrap onto more rows, as the iPad's WrapRow, never squeezed.
                    WrapRow(count: card.options.count) { index in
                        let option = card.options[index]
                        Button { Task { await model.answer(card, with: option) } } label: {
                            Text(verbatim: option.label).font(.system(size: 14)).foregroundColor(Theme.ink)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(Capsule().fill(Theme.panel)).overlay(Capsule().stroke(Theme.ink.opacity(0.18)))
                                // Clipped to the pill, as the iPad: no sliver past its ends.
                                .clipShape(Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(model.answering != nil)
                    }
                }
                if let why = model.notAnswered[card.key] {
                    Text(words("coach.answer.failed_why", ["value": why])).font(.system(size: 12)).foregroundColor(Theme.no)
                }
            } else if card.waitsForPerson {
                waiting(words("coach.needs_you_question"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func waiting(_ line: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.amber).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(line).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.amberText)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
    }
}

/// The keys of the AI-data consent's two answers. Return and Space answer nothing: the
/// person has just pressed Return to send, and one more must not say yes to sending their
/// words to the AI. Esc says Not now.
enum ConsentKeys {
    static let allow: KeyboardShortcut? = nil
    static let notNow: KeyboardShortcut? = .cancelAction
}

private extension View {
    /// A key for a button, or none. (The system's own optional form needs macOS 12.3.)
    @ViewBuilder func key(_ shortcut: KeyboardShortcut?) -> some View {
        if let shortcut { keyboardShortcut(shortcut) } else { self }
    }
}

/// Cells in rows that wrap at the width they are given, as the iPad's `WrapRow`. A Mac on
/// macOS 12 has no `Layout`, so each cell is placed by alignment guides.
struct WrapRow<Cell: View>: View {
    let count: Int
    let spacing: CGFloat
    let cell: (Int) -> Cell
    @State private var height: CGFloat = 0

    init(count: Int, spacing: CGFloat = 8, @ViewBuilder cell: @escaping (Int) -> Cell) {
        self.count = count
        self.spacing = spacing
        self.cell = cell
    }

    var body: some View {
        GeometryReader { space in placed(in: space.size.width) }
            .frame(height: height)
    }

    private func placed(in width: CGFloat) -> some View {
        var x: CGFloat = 0
        var y: CGFloat = 0
        return ZStack(alignment: .topLeading) {
            ForEach(0..<count, id: \.self) { index in
                cell(index)
                    .padding(.trailing, spacing).padding(.bottom, spacing)
                    .alignmentGuide(.leading) { d in
                        // A cell that doesn't fit what is left of the row starts the next one.
                        if x != 0, abs(x - d.width) > width {
                            x = 0
                            y -= d.height
                        }
                        let placedAt = x
                        x = index == count - 1 ? 0 : x - d.width
                        return placedAt
                    }
                    .alignmentGuide(.top) { _ in
                        let placedAt = y
                        if index == count - 1 { y = 0 }
                        return placedAt
                    }
            }
        }
        .background(GeometryReader { drawn in Color.clear.preference(key: WrapHeight.self, value: drawn.size.height) })
        .onPreferenceChange(WrapHeight.self) { height = $0 }
    }
}

/// Coach's width, as drawn.
private struct CoachWidth: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Where the chat's thread starts in its scroll view: lower as it scrolls down.
private struct ThreadTop: PreferenceKey {
    static let space = "coach-thread"
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct WrapHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A taf's card handing a setting to Coach, as the iPad's `AskCoachCardView` (TafChatView.swift:812-826):
/// the person's request in the taf's words, and Ask Coach, which opens Coach on this taf with them
/// in the box to send, as written or changed. Nothing is sent. Someone who can't change the taf
/// reads it alone.
struct AskCoachCard: View {
    @Environment(\.words) private var words
    let text: String
    let ask: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: text).font(.system(size: 15)).foregroundColor(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            if let ask {
                Button(words("coach.ask"), action: ask).buttonStyle(OutlineButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
    }
}

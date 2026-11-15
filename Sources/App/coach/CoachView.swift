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
    }

    @Published private(set) var state: State = .loading
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

    struct Improving: Equatable {
        /// The taf's id in tafs cloud.
        let id: String
        let name: String
    }
    private let cloud: CloudClient
    /// Opens the answer's stream; nil sends plainly and reads the thread again instead.
    private let streamer: LineStream?
    private let sleep: (TimeInterval) async throws -> Void
    private let now: () -> Date
    private var following = 0
    /// The answer streaming now, as the iPad's `setupStream`: a new conversation cancels it.
    private var streaming: Task<Void, Never>?

    /// As the phones do on the plain route: the thread is read again every 4 seconds, at
    /// most 30 times, while an answer is owed.
    static let followEvery: TimeInterval = 4
    static let followAtMost = 30

    /// The taf whose chat this is, when it isn't Coach's: then nothing is read to find it.
    private let fixed: Coach?

    init(cloud: CloudClient, taf: Coach? = nil, streamer: LineStream? = nil, sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
         now: @escaping () -> Date = Date.init) {
        self.cloud = cloud
        self.fixed = taf
        self.streamer = streamer
        self.sleep = sleep
        self.now = now
    }

    /// Coach's own chat, not a taf's: only it has conversations.
    private var isCoach: Bool { fixed == nil }

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
        return try await cloud.thread(of: coach.id, session: isCoach ? chat : nil)
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

    /// A new conversation on a taf, as the iPad's `improveTaf`.
    func improve(_ taf: Improving) {
        guard isCoach, case .loaded = state else { return }
        newChat()
        improving = taf
    }

    /// Coach on a taf with these words in the box, nothing sent, as the iPad's `askCoachAbout`.
    /// Whoever calls it checks first that the person may use Coach and manages the taf.
    func ask(about taf: Improving, words: String) {
        improve(taf)
        if improving == taf { draft = words }
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

    var canSend: Bool { canSend(draft) }

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
        guard case .loaded(let coach, _) = state, canSend, let text = Outgoing.text(draft) else { return }
        draft = ""
        await deliver(text, to: coach)
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

    /// Says no to an approval or a sign-in. It grants nothing, so any Mac may.
    func decline(_ card: Thread.Card) async {
        guard case .loaded(let coach, _) = state, answering == nil, card.waitsForPerson, card.grants else { return }
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
            state = .loaded(coach, page)
            pending = nil
            if page.working { await follow(coach) }
            return
        }
        await deliver(tried.text, to: coach, firstTried: tried.at)
    }

    /// The person read the consent's words and allows AI use: then their message goes.
    func allowAI() async {
        guard let asked = consent, case .loaded(let coach, _) = state, let text = pending?.text else { return }
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

    private func deliver(_ text: String, to coach: Coach, firstTried: Date? = nil) async {
        pending = Pending(text: text, at: firstTried ?? now())
        stopped = nil
        var mine = conversation
        do {
            // An improvement's first message goes through tafs cloud, which adds the taf's
            // context; the conversation goes on as any other (the iPad's `deliverSetup`).
            if isCoach, let taf = improving {
                let sent = try await cloud.improve(taf.id, text: text)
                guard mine == conversation else { return }
                improving = nil
                pending?.id = sent.message?.id
                settle(sent.session)
                await follow(coach)
                return
            }
            if let streamer, let request = cloud.streamRequest(text, to: coach.id, target: target) {
                var opened: AsyncThrowingStream<String, Error>?
                do {
                    opened = try await streamer.lines(request)
                } catch let refusal as CloudRefusal {
                    throw refusal
                } catch {
                    // The stream couldn't open. If tafs cloud has the message all the same, the
                    // thread is followed; only if it doesn't is the message sent plainly, below.
                    if let page = try? await read(coach), mine == conversation, let tried = pending, page.hasPersonsLast(tried.text, since: tried.at) {
                        state = .loaded(coach, page)
                        pending = nil
                        await follow(coach)
                        return
                    }
                }
                if let opened {
                    // tafs cloud answered the stream route: it has the message. Whatever the
                    // stream does from here, the message is never sent again.
                    let started = mine
                    let task = Task { await self.stream(opened, coach, started) }
                    streaming = task
                    await task.value
                    return
                }
            }
            let sent = try await cloud.send(text, to: coach.id, target: target)
            guard mine == conversation else { return }
            settle(sent.session)
            if followNew(sent.session, newSession: sent.newSession, coach) { mine = conversation }
            pending?.id = sent.message?.id
            await follow(coach)
        } catch let refusal as CloudRefusal where refusal.needsConsent {
            guard mine == conversation else { return }
            live = nil
            consent = refusal.consent
        } catch {
            guard mine == conversation else { return }
            live = nil
            pending?.failed = Self.why(error)
        }
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
        state = .loaded(coach, page)
        if let id = pending?.id, page.has(message: id) { pending = nil }
    }

    /// Reads the thread again while an answer is owed. A newer send takes over the following.
    private func follow(_ coach: Coach) async {
        following += 1
        let mine = following
        for _ in 0..<Self.followAtMost {
            guard mine == following, let page = try? await read(coach), mine == following else { return }
            state = .loaded(coach, page)
            if let id = pending?.id, page.has(message: id) { pending = nil }
            if pending == nil, !page.working { return }
            guard (try? await sleep(Self.followEvery)) != nil else { return }
        }
    }

    /// tafs cloud's words for a refusal, as the iPad's `CloudError`; else the network's own words.
    static func why(_ error: Error) -> String { NeedsYouModel.why(error) }

    func load() async {
        do {
            let found = try await (fixed == nil ? cloud.coach() : fixed)
            guard let coach = found else { state = .notStarted; return }
            // Coach opens on its newest chat, as the iPad's `loadSetupThread`; without the list,
            // or with none yet, the thread reads as before.
            let mine = conversation
            if isCoach, chat == nil, !fresh, let chats = try? await cloud.chats(of: coach.id), mine == conversation,
               let newest = chats.max(by: { $0.updated < $1.updated }) {
                chat = newest.session
            }
            guard mine == conversation else { return }
            state = .loaded(coach, try await read(coach) ?? .empty)
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
    /// Opens Plan & usage, for a hand-over whose taf needs a plan.
    var openUsage: () -> Void = {}
    /// Coach's own screen has its name at the top and its wash; a taf's chat sits in its page.
    var embedded = false
    /// The answers whose work is unfolded, and the plan.
    @State private var unfolded: Set<Int> = []
    @State private var planOpen = false

    var body: some View {
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
                Text(words("coach.title")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    // New conversation, as the iPad's pencil: an empty chat is already one.
                    .overlay(alignment: .trailing) {
                        Button { if !model.chatIsEmpty { model.newChat() } } label: {
                            Image(systemName: "square.and.pencil").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.soft)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(words("coach.new_conversation"))
                        .padding(.trailing, Look.inset)
                    }
                    .background(Theme.background)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .task { await model.load() }
        .sheet(item: Binding(get: { model.consent }, set: { if $0 == nil { model.declineAI() } })) { consent in
            consentSheet(consent)
        }
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
                            Text(verbatim: Self.when(at)).font(.system(size: 12)).foregroundColor(Theme.dim).frame(maxWidth: .infinity)
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
                }
            }
            .padding(.horizontal, Look.inset).padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            VStack(alignment: .leading, spacing: 4) {
                // While Coach or the taf works, the box asks for the next message, as on the iPad.
                TextField(placeholder, text: $model.draft)
                    .textFieldStyle(.plain).font(.system(size: 16))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .onSubmit { Task { await model.send() } }
                HStack {
                    Spacer()
                    Button { Task { await model.send() } } label: {
                        Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundColor(Theme.onFill)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Theme.coach.opacity(model.canSend ? 1 : 0.4)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canSend)
                    .accessibilityLabel(words("common.send"))
                }
                .padding(.horizontal, 8).padding(.bottom, 8)
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.line))
            .padding(.horizontal, 12).padding(.vertical, 10)
            // The iPad's bar: the background with a faint shadow upward, apart from the wash.
            .background(Theme.background.shadow(color: Theme.ink.opacity(0.06), radius: 6, x: 0, y: -2))
        }
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
            if !live.text.isEmpty { rich(live.text) }
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
                Text(verbatim: pending.text).font(.system(size: 15)).foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.brand))
                    .opacity(pending.failed == nil ? 0.7 : 0.45)
            }
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
                Text(words("coach.coach_mode")).font(Theme.display(30)).foregroundColor(Theme.coach)
                    .accessibilityAddTraits(.isHeader)
                Text(words("coach.ask_anything_line")).font(.system(size: 16)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                .disabled(model.working)
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
        .disabled(model.working)
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
    static func when(_ at: Date) -> String {
        DateFormatter.localizedString(from: at, dateStyle: Calendar.current.isDateInToday(at) ? .none : .medium, timeStyle: .short)
    }

    @ViewBuilder private func item(_ item: Thread.Item) -> some View {
        switch item {
        case .message(let message, _):
            if message.isNote {
                Text(verbatim: message.text).font(.system(size: 12)).foregroundColor(Theme.dim)
            } else {
                // The words are a person's or the model's: plain text, never a line of the app's.
                if message.fromPerson {
                    // The person's words on the brand's gradient.
                    HStack {
                        Spacer(minLength: 48)
                        Text(verbatim: message.text).font(.system(size: 15)).foregroundColor(.white)
                            .textSelection(.enabled)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.brand))
                    }
                } else {
                    // Coach's words, as text on the page, with no bubble; its work folded above them.
                    VStack(alignment: .leading, spacing: 8) {
                        if let work = message.work { workFold(work, id: item.id) }
                        rich(message.text)
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

    /// A card, by its kind, as the iPad draws each.
    @ViewBuilder private func card(_ card: Thread.Card) -> some View {
        if card.isPlan {
            plan(card)
        } else if card.isHandOver {
            handOver(card)
        } else if card.type == "sign_in" {
            signIn(card)
        } else if card.grants {
            approval(card)
        } else if card.type == "notice" {
            notice(card)
        } else if card.title != nil || card.text != nil || card.waitsForPerson || card.answered != nil {
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
                        Text(verbatim: (card.planLine ?? words("coach.plan.progress", ["done": words.number(card.planDone), "total": words.number(card.plan.count)])).uppercased())
                            .font(Theme.mono(12)).tracking(0.7).foregroundColor(Theme.dim)
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
    private func outcomeLine(_ symbol: String, _ color: Color, _ text: String, detail: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundColor(color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: text).font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
                if let detail { Text(verbatim: detail).font(.system(size: 12)).foregroundColor(Theme.soft) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.raised.opacity(0.6)))
    }

    /// The hand-over: the taf Coach made, what it does, its tools, and the way to it. When it
    /// failed, why, and no button; when it needs a plan, the way to choose one.
    private func handOver(_ card: Thread.Card) -> some View {
        let name = card.tafName ?? ""
        return VStack(alignment: .leading, spacing: 10) {
            Text(words("coach.result.set_up", ["taf": name]).uppercased()).font(Theme.mono(12)).tracking(0.7).foregroundColor(Theme.ok)
            if let text = card.text { Text(verbatim: text).font(.system(size: 15)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true) }
            if !card.tools.isEmpty {
                Text(verbatim: card.tools.joined(separator: " · ")).font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
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
                Text(words("coach.sign_in.eyebrow").uppercased()).font(Theme.mono(12)).tracking(0.7).foregroundColor(Theme.amberText)
                Text(card.service.map { words("coach.sign_in.at", ["vendor": $0]) } ?? words("coach.sign_in.at_vendor"))
                    .font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(Theme.ink)
                if let note = card.note ?? card.text { Text(verbatim: note).font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true) }
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

    /// An approval or a sign-in. Answered: one folded line of what it was. Waiting: what it
    /// asks, Decline, and Approve only on a Mac that can sign one; otherwise where to approve.
    @ViewBuilder private func approval(_ card: Thread.Card) -> some View {
        if let answered = card.answered {
            // tafs cloud's words for the answer are the only sign of a decline in the thread:
            // the shared "Declined" in the app's language, which tafs cloud writes in too.
            if answered == words("coach.answer.declined_short") {
                outcomeLine("minus.circle.fill", Theme.dim, card.title.map { words("coach.answer.declined_title", ["title": $0]) } ?? answered)
            } else {
                outcomeLine("checkmark.circle.fill", Theme.ok, [answered, card.title].compactMap { $0 }.joined(separator: " · "), detail: card.connectionWords)
            }
        } else if card.waitsForPerson {
            VStack(alignment: .leading, spacing: 12) {
                Text(words("coach.needs_you_approve").uppercased()).font(Theme.mono(12)).tracking(0.7).foregroundColor(Theme.amberText)
                if let title = card.title { Text(verbatim: title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink) }
                if let text = card.text { Text(verbatim: text).font(.system(size: 15)).foregroundColor(Theme.ink).lineSpacing(2).fixedSize(horizontal: false, vertical: true) }
                if let connection = card.connectionWords { Text(verbatim: connection).font(.system(size: 13)).foregroundColor(Theme.soft) }
                if model.answering == card.key {
                    Text(words("coach.answering")).font(.system(size: 13)).foregroundColor(Theme.soft)
                } else {
                    outline(words("coach.answer.decline"), color: Theme.ink) { Task { await model.decline(card) } }
                        .disabled(model.answering != nil)
                }
                if !canApprove {
                    // No Approve here: this Mac can't sign one. The phone has the same card.
                    Text(words("approval.device_can_not_approve_approve")).font(.system(size: 12)).foregroundColor(Theme.soft)
                        .frame(maxWidth: .infinity)
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

private struct WrapHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

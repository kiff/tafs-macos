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
    /// The AI-data consent to ask for before the message can go.
    @Published private(set) var consent: TafsCloud.AIConsent?
    /// The answer as it is written, while a run streams.
    @Published private(set) var live: LiveAnswer?
    /// tafs cloud's words for why the last run stopped, when it stopped with a reason for the person.
    @Published private(set) var stopped: String?
    private let cloud: CloudClient
    /// Opens the answer's stream; nil sends plainly and reads the thread again instead.
    private let streamer: LineStream?
    private let sleep: (TimeInterval) async throws -> Void
    private let now: () -> Date
    private var following = 0

    /// As the phones do on the plain route: the thread is read again every 4 seconds, at
    /// most 30 times, while an answer is owed.
    static let followEvery: TimeInterval = 4
    static let followAtMost = 30

    init(cloud: CloudClient, streamer: LineStream? = nil, sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
         now: @escaping () -> Date = Date.init) {
        self.cloud = cloud
        self.streamer = streamer
        self.sleep = sleep
        self.now = now
    }

    var canSend: Bool {
        guard case .loaded = state else { return false }
        return Outgoing.text(draft) != nil && (pending == nil || pending?.failed != nil)
    }

    /// Sends what the person wrote. It stays in view, as written, until the thread has it;
    /// if it doesn't go, it stays with why, to send again.
    func send() async {
        guard case .loaded(let coach, _) = state, canSend, let text = Outgoing.text(draft) else { return }
        draft = ""
        await deliver(text, to: coach)
    }

    /// Sends the message that didn't go, again. If the first try reached tafs cloud after all
    /// (its answer was lost), the thread already has it: then nothing is sent a second time.
    func retry() async {
        guard case .loaded(let coach, _) = state, let tried = pending, tried.failed != nil else { return }
        if let page = try? await cloud.thread(of: coach.id), page.hasPersonsLast(tried.text, since: tried.at) {
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
        do {
            if let streamer, let request = cloud.streamRequest(text, to: coach.id) {
                var opened: AsyncThrowingStream<String, Error>?
                do {
                    opened = try await streamer.lines(request)
                } catch let refusal as CloudRefusal {
                    throw refusal
                } catch {
                    // The stream couldn't open. If tafs cloud has the message all the same, the
                    // thread is followed; only if it doesn't is the message sent plainly, below.
                    if let page = try? await cloud.thread(of: coach.id), let tried = pending, page.hasPersonsLast(tried.text, since: tried.at) {
                        state = .loaded(coach, page)
                        pending = nil
                        await follow(coach)
                        return
                    }
                }
                if let opened {
                    // tafs cloud answered the stream route: it has the message. Whatever the
                    // stream does from here, the message is never sent again.
                    await stream(opened, coach)
                    return
                }
            }
            let sent = try await cloud.send(text, to: coach.id)
            pending?.id = sent.message?.id
            await follow(coach)
        } catch let refusal as CloudRefusal where refusal.needsConsent {
            live = nil
            consent = refusal.consent
        } catch {
            live = nil
            pending?.failed = Self.why(error)
        }
    }

    /// Draws the answer as its events come, then reads the thread, which has it whole. A
    /// stream that breaks, at any point, only ends the drawing: the thread has the rest.
    private func stream(_ lines: AsyncThrowingStream<String, Error>, _ coach: Coach) async {
        var reader = EventReader()
        var answer = LiveAnswer()
        live = answer
        do {
            for try await line in lines {
                guard let event = reader.read(line) else { continue }
                if case .session(let id) = event { pending?.id = id }
                if case .end(let words) = event {
                    stopped = words
                    break
                }
                if case .broke = event { break }
                if answer.take(event) { await reload(coach) }
                live = answer
            }
        } catch {}
        live = nil
        await follow(coach)
        // The message was taken even if the thread didn't show it in time: it is not left
        // looking unsent, with a Retry that would send it again.
        if pending?.failed == nil { pending = nil }
    }

    private func reload(_ coach: Coach) async {
        guard let page = try? await cloud.thread(of: coach.id) else { return }
        state = .loaded(coach, page)
        if let id = pending?.id, page.has(message: id) { pending = nil }
    }

    /// Reads the thread again while an answer is owed. A newer send takes over the following.
    private func follow(_ coach: Coach) async {
        following += 1
        let mine = following
        for _ in 0..<Self.followAtMost {
            guard mine == following, let page = try? await cloud.thread(of: coach.id) else { return }
            state = .loaded(coach, page)
            if let id = pending?.id, page.has(message: id) { pending = nil }
            if pending == nil, !page.working { return }
            guard (try? await sleep(Self.followEvery)) != nil else { return }
        }
    }

    /// tafs cloud's words for a refusal when it sent some; else its code, or the network's own words.
    static func why(_ error: Error) -> String {
        if let refusal = error as? CloudRefusal { return refusal.words ?? refusal.code ?? String(refusal.status) }
        return NeedsYouModel.why(error)
    }

    func load() async {
        do {
            guard let coach = try await cloud.coach() else { state = .notStarted; return }
            state = .loaded(coach, try await cloud.thread(of: coach.id))
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(words("coach.title")).font(Theme.display(28)).foregroundColor(Theme.coach)
                switch model.state {
                case .loading:
                    ProgressView().controlSize(.small)
                case .notStarted:
                    intro
                case .unread(let why):
                    Text(words("coach.conversation_not_loaded", ["why": why])).font(.system(size: 14)).foregroundColor(Theme.no)
                    Button(words("common.try_again")) { Task { await model.load() } }
                case .loaded(_, let page):
                    if page.items.isEmpty { intro }
                    ForEach(page.items) { item($0) }
                    if let pending = model.pending { unsent(pending) }
                    if let live = model.live { writing(live) }
                    if let stopped = model.stopped {
                        Text(verbatim: stopped).font(.system(size: 13)).foregroundColor(Theme.no)
                    }
                    if page.working, model.live == nil {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(words("chat.working")).font(.system(size: 13)).foregroundColor(Theme.dim)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.coachWash)
        .safeAreaInset(edge: .bottom) { composer }
        .task { await model.load() }
        .sheet(item: Binding(get: { model.consent }, set: { if $0 == nil { model.declineAI() } })) { consent in
            consentSheet(consent)
        }
    }

    /// The message box. Return sends; nothing goes until the person sends it.
    @ViewBuilder private var composer: some View {
        if case .loaded = model.state {
            HStack(spacing: 10) {
                TextField(words("coach.ask_anything"), text: $model.draft)
                    .textFieldStyle(.roundedBorder).font(.system(size: 14))
                    .onSubmit { Task { await model.send() } }
                Button(words("common.send")) { Task { await model.send() } }
                    .buttonStyle(.plain).font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 7)
                    .background(Capsule().fill(model.canSend ? Theme.coach : Theme.dim))
                    .disabled(!model.canSend)
            }
            .padding(.horizontal, 28).padding(.vertical, 12)
            .frame(maxWidth: 760 + 56, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.coachPanel)
        }
    }

    /// The answer as it is written: Coach's words so far, and one line for where the run is.
    private func writing(_ live: LiveAnswer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !live.text.isEmpty {
                HStack {
                    Text(verbatim: live.text).font(.system(size: 14)).foregroundColor(Theme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
                    Spacer(minLength: 80)
                }
            }
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(verbatim: live.line ?? words("chat.thinking")).font(.system(size: 13)).foregroundColor(Theme.dim)
            }
            if let trouble = live.trouble { Text(verbatim: trouble).font(.system(size: 12)).foregroundColor(Theme.no) }
        }
    }

    /// The person's message, faded until the thread has it; with why and Retry if it didn't go.
    private func unsent(_ pending: CoachModel.Pending) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Spacer(minLength: 80)
                Text(verbatim: pending.text).font(.system(size: 14)).foregroundColor(Theme.onFill)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.coach.opacity(pending.failed == nil ? 0.55 : 0.35)))
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

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(words("coach.ask_anything")).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.ink)
            Text(words("coach.ask_anything_line")).font(.system(size: 14)).foregroundColor(Theme.soft)
        }
    }

    @ViewBuilder private func item(_ item: Thread.Item) -> some View {
        switch item {
        case .message(let message, _):
            if message.isNote {
                Text(verbatim: message.text).font(.system(size: 12)).foregroundColor(Theme.dim)
            } else {
                HStack {
                    if message.fromPerson { Spacer(minLength: 80) }
                    // The words are a person's or the model's: plain text, never a line of the app's.
                    Text(verbatim: message.text).font(.system(size: 14)).foregroundColor(message.fromPerson ? Theme.onFill : Theme.ink)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(message.fromPerson ? Theme.coach : Theme.panel))
                    if !message.fromPerson { Spacer(minLength: 80) }
                }
            }
        case .card(_, let waits, _):
            if waits == "owner" { waiting(words("coach.needs_you_question")) }
        case .held:
            waiting(words("coach.needs_you_approve"))
        case .other:
            EmptyView()
        }
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

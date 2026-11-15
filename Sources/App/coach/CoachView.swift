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
    /// Whether an approval can be signed on this Mac. When it can't, the card says where to.
    var canApprove = false
    /// Opens the taf a hand-over made.
    /// Opens a hand-over's taf, by its KIFF agent.
    var openTaf: (String?) -> Void = { _ in }
    /// The answers whose work is unfolded, and the plan.
    @State private var unfolded: Set<Int> = []
    @State private var planOpen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
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
                            Text(words("chat.working")).font(.system(size: 13)).foregroundColor(Theme.soft)
                        }
                    }
                }
            }
            .padding(.horizontal, Look.inset).padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.coachWash)
        // The screen's name sits small and centred on the background's own colour, as on the iPad.
        .safeAreaInset(edge: .top, spacing: 0) {
            Text(words("coach.title")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 14).background(Theme.background)
                .accessibilityAddTraits(.isHeader)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .task { await model.load() }
        .sheet(item: Binding(get: { model.consent }, set: { if $0 == nil { model.declineAI() } })) { consent in
            consentSheet(consent)
        }
    }

    /// The message box, to the iPad's: a rounded panel with the words, and the send circle at
    /// its foot. Return sends; nothing goes until the person sends it.
    @ViewBuilder private var composer: some View {
        if case .loaded = model.state {
            VStack(alignment: .leading, spacing: 10) {
                TextField(words("coach.ask_anything"), text: $model.draft)
                    .textFieldStyle(.plain).font(.system(size: 16))
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
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
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
                Text(verbatim: live.line ?? words("chat.thinking")).font(.system(size: 13)).foregroundColor(Theme.soft)
            }
            if !live.steps.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(live.steps.enumerated()), id: \.offset) { _, step in
                        stepRow(step.words, done: step.done, failed: step.failed, why: nil, notMade: step.notMade)
                    }
                }
                .padding(.leading, 10)
                .overlay(Rectangle().fill(Theme.line).frame(width: 1), alignment: .leading)
            }
            if let trouble = live.trouble { Text(verbatim: trouble).font(.system(size: 12)).foregroundColor(Theme.no) }
            if !live.text.isEmpty { rich(live.text) }
        }
    }

    private func stepRow(_ text: String, done: Bool, failed: Bool, why: String?, notMade: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: failed ? "xmark" : (notMade ? "arrow.uturn.backward" : (done ? "checkmark" : "circle.dotted")))
                    .font(.system(size: 10, weight: .semibold)).foregroundColor(failed ? Theme.no : Theme.soft).frame(width: 12)
                Text(verbatim: text).font(.system(size: 13)).foregroundColor(failed ? Theme.no : Theme.soft)
            }
            if let why { Text(verbatim: why).font(.system(size: 12)).foregroundColor(Theme.no).padding(.leading, 20) }
        }
    }

    /// Coach's or a taf's words, as the iPad's `MarkdownText` draws them: no mark shows, and a
    /// link is its label only.
    private func rich(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
                }
            }
        }
        .textSelection(.enabled)
    }

    private func item(_ mark: String, _ spans: [Rich.Span]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: mark).font(.system(size: 16)).foregroundColor(Theme.ink)
            line(spans)
        }
        .padding(.leading, 4)
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
                Spacer(minLength: 80)
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

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(words("coach.ask_anything")).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.ink)
            Text(words("coach.ask_anything_line")).font(.system(size: 14)).foregroundColor(Theme.soft)
        }
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// "Worked for 32 s", which opens the steps the run took.
    private func workFold(_ work: Thread.Work, id: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if unfolded.contains(id) { unfolded.remove(id) } else { unfolded.insert(id) }
            } label: {
                HStack(spacing: 4) {
                    Text(words("chat.work.worked_for", ["ms": work.took(words)])).font(.system(size: 13)).foregroundColor(Theme.soft)
                    if !work.steps.isEmpty {
                        Image(systemName: unfolded.contains(id) ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.soft)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(work.steps.isEmpty)
            if unfolded.contains(id) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(work.steps.enumerated()), id: \.offset) { _, step in
                        stepRow(step.words, done: true, failed: step.failed, why: step.why, notMade: step.notMade)
                    }
                }
                .padding(.leading, 10)
                .overlay(Rectangle().fill(Theme.line).frame(width: 1), alignment: .leading)
            }
        }
    }

    @ViewBuilder private func item(_ item: Thread.Item) -> some View {
        switch item {
        case .message(let message, _):
            if message.isNote {
                Text(verbatim: message.text).font(.system(size: 12)).foregroundColor(Theme.dim)
            } else {
                // The words are a person's or the model's: plain text, never a line of the app's.
                if message.fromPerson {
                    // When it was sent, small and centred, then the person's words on the brand's gradient.
                    if let at = message.at {
                        Text(verbatim: Self.clock.string(from: at)).font(.system(size: 12)).foregroundColor(Theme.soft)
                            .frame(maxWidth: .infinity)
                    }
                    HStack {
                        Spacer(minLength: 80)
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
        } else if card.grants {
            approval(card)
        } else if card.type == "notice" {
            notice(card)
        } else if card.title != nil || card.text != nil || card.waitsForPerson || card.answered != nil {
            choice(card)
        }
    }

    /// The plan: its progress and the step in hand, opening to every step.
    private func plan(_ card: Thread.Card) -> some View {
        let current = card.plan.first { $0.status == "active" } ?? card.plan.first { $0.status != "done" } ?? card.plan.last
        return VStack(alignment: .leading, spacing: 8) {
            Button { planOpen.toggle() } label: {
                HStack(spacing: 10) {
                    Circle().stroke(Theme.amber, lineWidth: 2).frame(width: 16, height: 16).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        // tafs cloud's line for the plan, else the shared words for its count.
                        Text(verbatim: (card.planLine ?? words("coach.plan.progress", ["done": words.number(card.planDone), "total": words.number(card.plan.count)])).uppercased())
                            .font(Theme.mono(10)).tracking(1.5).foregroundColor(Theme.soft)
                        Text(verbatim: card.title ?? current?.label ?? "").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink).lineLimit(1)
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
                    stepRow(step.label, done: step.status == "done", failed: step.status == "failed", why: nil, notMade: false)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
    }

    /// A line Coach leaves in the chat, with a small arrow, in its tone's colour.
    private func notice(_ card: Thread.Card) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "arrow.turn.down.right").font(.system(size: 10)).foregroundColor(Theme.soft)
            Text(verbatim: [card.title, card.text].compactMap { $0 }.joined(separator: ": ")).font(.system(size: 13))
                .foregroundColor(card.tone == "error" ? Theme.no : Theme.soft).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The hand-over: the taf Coach made, what it does, its tools, and the way to it.
    private func handOver(_ card: Thread.Card) -> some View {
        let name = card.tafName ?? ""
        return VStack(alignment: .leading, spacing: 10) {
            Text(words("coach.result.set_up", ["taf": name]).uppercased()).font(Theme.mono(11)).tracking(1.5).foregroundColor(Theme.ok)
            if let text = card.text { Text(verbatim: text).font(.system(size: 15)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true) }
            if !card.tools.isEmpty {
                Text(verbatim: card.tools.joined(separator: " · ")).font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            }
            // What came of it, in tafs cloud's words, when it didn't simply make the taf.
            if let failed = card.outcome?.failed {
                Text(verbatim: failed).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
            }
            if let needed = card.outcome?.planNeeded {
                Text(verbatim: needed).font(.system(size: 13)).foregroundColor(Theme.amberText).fixedSize(horizontal: false, vertical: true)
            }
            Button { openTaf(card.tafAgent) } label: {
                Text(words("coach.result.open", ["taf": name])).font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.brand)).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.ok.opacity(0.6)))
    }

    /// An approval or a sign-in. Answered: one folded line of what it was. Waiting: what it
    /// asks, Decline, and Approve only on a Mac that can sign one; otherwise where to approve.
    @ViewBuilder private func approval(_ card: Thread.Card) -> some View {
        if let answered = card.answered {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundColor(Theme.ok).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: [answered, card.title].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 14)).foregroundColor(Theme.ink)
                    if let connection = card.connectionWords { Text(verbatim: connection).font(.system(size: 12)).foregroundColor(Theme.soft) }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised.opacity(0.7)))
        } else if card.waitsForPerson {
            VStack(alignment: .leading, spacing: 12) {
                Text(words("coach.needs_you_approve").uppercased()).font(Theme.mono(11)).tracking(1.5).foregroundColor(Theme.amberText)
                if let title = card.title { Text(verbatim: title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink) }
                if let text = card.text { Text(verbatim: text).font(.system(size: 15)).foregroundColor(Theme.ink).lineSpacing(2).fixedSize(horizontal: false, vertical: true) }
                if let connection = card.connectionWords { Text(verbatim: connection).font(.system(size: 13)).foregroundColor(Theme.soft) }
                if model.answering == card.key {
                    Text(words("coach.answering")).font(.system(size: 13)).foregroundColor(Theme.soft)
                } else {
                    Button { Task { await model.decline(card) } } label: {
                        Text(words("coach.answer.decline")).font(.system(size: 15)).foregroundColor(Theme.ink)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.soft.opacity(0.5))).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.amber.opacity(0.7)))
        }
    }

    /// A choice or a question: what it asks, as Coach wrote it, then its answer or its pills.
    private func choice(_ card: Thread.Card) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = card.title { Text(verbatim: title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink) }
            if let text = card.text { rich(text) }
            if let answered = card.answered {
                Text(verbatim: answered).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.ok)
            } else if card.waitsForPerson, card.isChoice {
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

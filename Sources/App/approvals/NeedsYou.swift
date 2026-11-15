import SwiftUI

/// The calls waiting for the person, and their answers, for the Needs you screen.
@MainActor
final class NeedsYouModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded([HeldCall])
        /// The list couldn't be read: KIFF's code, or the network's own words.
        case unread(why: String)
    }

    @Published private(set) var state: State = .loading
    /// Why the last answer wasn't taken, by the call it was for.
    @Published private(set) var notTaken: [String: String] = [:]
    /// The call being answered now: its buttons wait.
    @Published private(set) var answering: String?
    /// "Did this happen?": the money calls whose outcome KIFF can't prove, newest first.
    @Published private(set) var unproven: [Unproven] = []
    /// The steps the tafs handed their owner, as Home last listed them, less those answered here.
    @Published private(set) var steps: [YourStep] = []
    /// The steps being answered now: their buttons wait.
    @Published private(set) var answeringSteps: Set<String> = []
    /// Why the last step wasn't answered, in the iPad's words.
    @Published private(set) var stepNotAnswered: String?
    /// Steps answered or ended here that Home may still list.
    private var answeredSteps: Set<String> = []

    private let account: AccountClient
    /// Where an approval is signed on this Mac.
    let route: ApprovalRoute

    init(account: AccountClient, route: ApprovalRoute) {
        self.account = account
        self.route = route
    }

    var count: Int {
        if case .loaded(let calls) = state { return calls.count }
        return 0
    }

    func load() async {
        do { state = .loaded(try await account.heldCalls()) } catch { state = .unread(why: Self.why(error)) }
    }

    /// Home's steps, less those answered here that it still lists, as the iPad's `showSteps`;
    /// an answered step Home no longer lists is forgotten.
    func showSteps(_ listed: [YourStep]) {
        answeredSteps.formIntersection(listed.map(\.handoff))
        steps = listed.filter { !answeredSteps.contains($0.handoff) }
    }

    /// Whether this Mac can answer a step, as the iPad's `canAnswerSteps`: KIFF checks the device
    /// key's signature, so the session must hold it.
    var canAnswerSteps: Bool { account.signMessage != nil }

    /// Answers a step a taf handed its owner, "done" or "skipped", as the iPad's `answerYourStep`:
    /// the hand-off is read from KIFF first, for the version signed; one KIFF no longer waits on
    /// isn't sent. The answer is signed with the device key over `kiff.handoff.v1`: it grants
    /// nothing, so no approval key is asked for. `answered` reads the lists again after.
    func answer(_ step: YourStep, done: Bool, now: Date = Date(), answered: () async -> Void = {}) async {
        guard !answeringSteps.contains(step.handoff), !answeredSteps.contains(step.handoff) else { return }
        guard canAnswerSteps, let signMessage = account.signMessage else { return }
        answeringSteps.insert(step.handoff)
        defer { answeringSteps.remove(step.handoff) }
        stepNotAnswered = nil
        let answer = done ? "done" : "skipped"
        let current: Handoff
        do {
            current = try await account.handoff(step.handoff)
        } catch {
            stepNotAnswered = Words.app("needs_you.your_step.not_answered", ["why": Self.answerRefusedWords(error)])
            return
        }
        guard current.status.isEmpty || current.status == "waiting" else {
            stepNotAnswered = Words.app("needs_you.your_step.ended")
            drop(step)
            return
        }
        let at = SigningTime.next(now: now)
        let message = KIFFMessage.handoff(tenant: account.session.tenant, handoffID: current.id, answer: answer, version: current.version, signedAt: at)
        let value: String
        do {
            value = try signMessage(message)
        } catch {
            stepNotAnswered = Words.app("needs_you.your_step.not_answered_unconfirmed")
            return
        }
        do {
            try await account.answerHandoff(current.id, answer: answer, signedAt: at, signature: value)
        } catch KIFFError.refused(409, _) {
            // Answered meanwhile, on another device, or ended: nothing more to do here.
            stepNotAnswered = Words.app("needs_you.your_step.ended")
            drop(step)
            return
        } catch {
            stepNotAnswered = Words.app("needs_you.your_step.not_answered", ["why": Self.answerRefusedWords(error)])
            return
        }
        drop(step)
        await answered()
    }

    /// Takes an answered or ended step off Needs you at once, while Home still lists it.
    private func drop(_ step: YourStep) {
        answeredSteps.insert(step.handoff)
        steps.removeAll { $0.handoff == step.handoff }
    }

    /// KIFF's reason it didn't take an answer, in the iPad's words (`answerRefusedWords`,
    /// `refusalWords`); else "KIFF didn't take the answer", with why.
    static func answerRefusedWords(_ error: Error) -> String {
        if case KIFFError.refused(_, let code) = error, let key = refusalKeys[code] { return Words.app(key) }
        return Words.app("needs_you.refused.other", ["why": why(error)])
    }

    static let refusalKeys = [
        "self_review": "needs_you.refused.self_review", "separation_of_duties_role": "needs_you.refused.approver_only",
        "separation_of_duties_key": "needs_you.refused.signed_in_approver", "card_changer": "needs_you.refused.card_changer",
        "hold_check_unavailable": "needs_you.refused.check_unavailable", "role_forbidden": "needs_you.refused.role",
    ]

    /// Reads "Did this happen?" from KIFF, for someone who answers held calls, as the iPad's
    /// `loadUnproven`. A read that fails keeps the list: it's read again next time.
    /// The model lives and dies with the signed-in window, so a read that ends after a sign-out
    /// lands on a model no longer shown: the iPad's `gen == accountGeneration` check comes to that.
    func loadUnproven(answersHolds: Bool) async {
        guard answersHolds, let calls = try? await account.didThisHappen() else { return }
        unproven = calls
    }

    /// Refuses a call, then reads the list again: KIFF's list is the truth, not this screen's.
    func refuse(_ call: HeldCall, nextStep: String? = nil) async {
        answering = call.id
        defer { answering = nil }
        do {
            try await account.refuse(call, nextStep: nextStep)
            notTaken[call.id] = nil
            await load()
        } catch {
            notTaken[call.id] = Self.why(error)
        }
    }

    static func why(_ error: Error) -> String {
        switch error {
        case let refusal as CloudRefusal: return refusal.why(Words.app)
        case KIFFError.refused(_, let code) where !code.isEmpty: return code
        case KIFFError.refused(let status, _): return String(status)
        case let error as KIFFError: return String(describing: error)
        default: return error.localizedDescription
        }
    }
}

/// Needs you: each held call in KIFF's words and the taf's, with its answers, as the iPad's
/// `HeldCallCard`.
struct NeedsYouView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: NeedsYouModel
    /// The person's tafs: a call's header names its taf, by the KIFF agent it acts as.
    var tafs: [Home.Taf] = []
    /// The time the countdowns start from; the live view ticks every second from it.
    var now: Date?
    /// Whether this person answers the account's held calls (KIFF's `holds.answer`).
    var answersHolds = true
    /// Reads the lists again once a step is answered: the taf's run goes on.
    var answered: () async -> Void = {}
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(words("needs_you.title")).font(Theme.display(34)).foregroundColor(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let why = model.stepNotAnswered {
                    Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
                }
                // A step a taf handed its owner comes first, oldest first, as the iPad's.
                ForEach(model.steps) { step($0) }
                // A money call whose outcome KIFF can't prove: the owner says whether it happened.
                ForEach(model.unproven) { happened($0) }
                switch model.state {
                case .loading:
                    ProgressView().controlSize(.small)
                case .unread(let why):
                    Text(words("needs_you.request_not_read", ["why": why])).font(.system(size: 14)).foregroundColor(Theme.no)
                case .loaded(let calls) where calls.isEmpty:
                    if model.unproven.isEmpty, model.steps.isEmpty { nothing }
                case .loaded(let calls):
                    ForEach(calls) { card($0) }
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task {
            await model.load()
            await model.loadUnproven(answersHolds: answersHolds)
        }
    }

    private var nothing: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(words("needs_you.nothing")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
            Text(words("needs_you.empty_hint")).font(.system(size: 14)).foregroundColor(Theme.soft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
    }

    /// A step a taf handed its owner, as the iPad's `YourStepCard`: tafs cloud's title, the taf,
    /// what to do and why, the vendor's page only as tafs cloud vouched for it, and Done or Skip
    /// when this Mac can answer.
    private func step(_ step: YourStep) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !step.words.title.isEmpty { Eyebrow(text: step.words.title) }
            if let name = step.taf?.name, !name.isEmpty {
                Text(verbatim: name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
            }
            Text(verbatim: step.what).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !step.why.isEmpty {
                Text(verbatim: step.why).font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            }
            if let link = step.openLink {
                VStack(alignment: .leading, spacing: 4) {
                    Button { openURL(link.url) } label: {
                        Label(link.words, systemImage: "arrow.up.right.square").padding(.horizontal, 16)
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .fixedSize()
                    // Where it really goes, as tafs cloud read the link.
                    Text(verbatim: link.host).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.dim)
                }
            }
            if model.canAnswerSteps {
                HStack(spacing: 8) {
                    Button { Task { await model.answer(step, done: true, answered: answered) } } label: {
                        Text(verbatim: step.words.done).padding(.horizontal, 16)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button { Task { await model.answer(step, done: false, answered: answered) } } label: {
                        Text(verbatim: step.words.skip).padding(.horizontal, 16)
                    }
                    .buttonStyle(OutlineButtonStyle())
                }
                .fixedSize()
                .disabled(model.answeringSteps.contains(step.handoff))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).stroke(Theme.amber.opacity(0.4)))
        .accessibilityElement(children: .contain)
    }

    /// "Did this happen?", as the iPad's `DidThisHappenCard`: KIFF's words for the call (else its
    /// title and amount) and for why it asks. The answer is signed like an approval, which this
    /// Mac can't do yet: for someone who answers held calls, it says to approve on another
    /// device, the iPad's line where an approval can't be made (`Biometry.short`).
    private func happened(_ call: Unproven) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(words("record.did_this_happen.title")).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.amberText)
            Text(verbatim: call.words ?? call.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if call.words == nil, let money = call.money {
                Text(verbatim: Self.amount(money, words: words)).font(.system(size: 15)).foregroundColor(Theme.ink)
            }
            if let why = call.statusWords {
                Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            }
            if Self.saysCantApprove(answersHolds: answersHolds, route: model.route) {
                Text(words("approval.device_can_not_approve_approve")).font(.system(size: 13)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).stroke(Theme.amber.opacity(0.4)))
        .accessibilityElement(children: .contain)
    }

    /// An amount as the iPad's `Money.formatted`: with its unit, or saying it has none.
    static func amount(_ money: TafCard.Amount, words: Words) -> String {
        let figure = money.written(language: words.language)
        return money.unit == nil ? words("card.no_currency", ["amount": figure]) : figure
    }

    /// Where the iPad's `ApprovalGate` shows `ApprovalNotReady`: someone who answers held calls,
    /// on a Mac that approves elsewhere, as the held calls' card says it. A Mac with its own
    /// approval key gets neither the line nor the buttons until its Yes or No is ported.
    static func saysCantApprove(answersHolds: Bool, route: ApprovalRoute) -> Bool {
        answersHolds && route == .phoneOrPasskey
    }

    private func card(_ call: HeldCall) -> some View {
        let taf = tafs.first { $0.kiffAgent == call.subject }
        return VStack(alignment: .leading, spacing: 12) {
            // The taf, and the time left to answer, counted down every second.
            HStack(spacing: 10) {
                if let taf {
                    RoundedRectangle(cornerRadius: 32 * 0.3, style: .continuous).fill(Theme.tafColor(taf.color)).frame(width: 32, height: 32)
                        .overlay(Text(verbatim: String(taf.name.prefix(1)).uppercased()).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.white))
                        .accessibilityHidden(true)
                }
                Text(verbatim: taf?.name ?? words("needs_you.a_taf")).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
                Spacer()
                if let expires = call.expiresAt {
                    if let now {
                        countdown(expires, at: now)
                    } else {
                        TimelineView(.periodic(from: Date(), by: 1)) { context in countdown(expires, at: context.date) }
                    }
                }
            }
            // What it moves, in KIFF's numbers, then what it is.
            if let amount = call.amount {
                Text(verbatim: amount.written(language: words.language)).font(.system(size: 44, weight: .bold, design: .rounded)).foregroundColor(Theme.ink)
            }
            Text(verbatim: call.title ?? call.action).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            // Why KIFF held it, on the amber pill.
            if let reason = call.reasonText {
                Text(verbatim: reason).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.amberText)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.amber.opacity(0.14)))
            }
            if call.tafAbout != nil || call.tafReason != nil {
                // The taf's own words, possibly a customer's: in their own box, drawn plain and
                // apart from KIFF's, never in place of KIFF's amount, rule or action.
                VStack(alignment: .leading, spacing: 4) {
                    Text(words("needs_you.taf_says")).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.soft)
                    if let about = call.tafAbout { Text(verbatim: about).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true) }
                    if let reason = call.tafReason { Text(verbatim: reason).font(.system(size: 14)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true) }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.soft.opacity(0.08)))
                .accessibilityElement(children: .combine)
            }
            Text(words("needs_you.nothing_sent")).font(.system(size: 14)).foregroundColor(Theme.soft)
            if model.route == .phoneOrPasskey {
                Text(words("approval.device_can_not_approve_approve")).font(.system(size: 13)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Refuse, as the iPad's outlined button: the card's width, in red.
            Button { Task { await model.refuse(call) } } label: {
                HStack(spacing: 8) {
                    Text(words("needs_you.refuse")).font(.system(size: 15, weight: .medium))
                    if model.answering == call.id { ProgressView().controlSize(.small) }
                }
                .foregroundColor(Theme.no)
                .frame(maxWidth: .infinity, minHeight: 48)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.no.opacity(0.4), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.answering != nil)
            if let why = model.notTaken[call.id] {
                Text(words("needs_you.refused.other", ["why": why])).font(.system(size: 13)).foregroundColor(Theme.no)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).stroke(Theme.amber.opacity(0.4)))
        .accessibilityElement(children: .contain)
    }

    private func countdown(_ expires: Date, at date: Date) -> some View {
        Text(verbatim: Self.left(until: expires, at: date, words: words))
            .font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.amberText)
    }

    /// "8:06 left", as a clock counts down: m:ss, or h:mm:ss past an hour; "expired" at the end.
    static func left(until expires: Date, at date: Date, words: Words) -> String {
        let seconds = Int(expires.timeIntervalSince(date))
        guard seconds >= 1 else { return words("needs_you.expired") }
        let time = seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
        return words("needs_you.left", ["time": time])
    }
}

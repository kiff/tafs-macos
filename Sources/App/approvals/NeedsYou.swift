import LocalAuthentication
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
    /// The answers on their way: cancelled at sign-out, so none outlives its session.
    private var stepAnswers: [String: Task<Void, Never>] = [:]

    private let account: AccountClient
    /// Where an approval is signed on this Mac.
    let route: ApprovalRoute
    /// The person confirms before the device key signs a step, as the iPad's `sign(_:reason:)`
    /// does: Touch ID, or the Mac's login password, which every Mac has. Throws when not
    /// confirmed; the prompt's words are tafs cloud's for the answer and the step.
    let confirm: (String) async throws -> Void

    init(account: AccountClient, route: ApprovalRoute, confirm: @escaping (String) async throws -> Void = NeedsYouModel.confirmOwner) {
        self.account = account
        self.route = route
        self.confirm = confirm
    }

    /// The owner's presence, as the iPad's `authenticate(reason:)` with `.deviceOwnerAuthentication`.
    nonisolated static func confirmOwner(_ reason: String) async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { throw error ?? LAError(.authenticationFailed) }
        guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else { throw LAError(.authenticationFailed) }
    }

    /// The words for a prompt the person closed, as the iPad's `ApprovalReadiness.cancelled`; nil
    /// for any other failure.
    static func cancelled(_ error: Error) -> String? {
        switch (error as? LAError)?.code {
        case .userCancel?, .systemCancel?, .appCancel?, .userFallback?:
            return Words.app("approval.cancelled_nothing_approved_request_kept")
        default:
            return nil
        }
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
    /// key's signature, so the session must hold it, and the person must answer the account's
    /// holds (KIFF's `holds.answer`).
    func canAnswerSteps(answersHolds: Bool) -> Bool { answersHolds && account.signMessage != nil }

    /// Starts an answer that sign-out can stop (`cancelAnswers`).
    func startAnswer(_ step: YourStep, done: Bool, answersHolds: Bool, answered: @escaping () async -> Void = {}) {
        guard stepAnswers[step.handoff] == nil else { return }
        stepAnswers[step.handoff] = Task { [weak self] in
            await self?.answer(step, done: done, answersHolds: answersHolds, answered: answered)
            self?.stepAnswers[step.handoff] = nil
        }
    }

    /// Stops every answer on its way: the session is ending, as the iPad's `accountGeneration`.
    func cancelAnswers() {
        stepAnswers.values.forEach { $0.cancel() }
        stepAnswers = [:]
    }

    /// Answers a step a taf handed its owner, "done" or "skipped", as the iPad's `answerYourStep`:
    /// the hand-off is read from KIFF first, for the version signed; one KIFF no longer waits on
    /// isn't sent. The person confirms (Touch ID or the Mac's password), then the device key
    /// signs `kiff.handoff.v1`: never the approval key. An answer whose session ended stops after
    /// each step. `answered` reads the lists again after.
    func answer(_ step: YourStep, done: Bool, answersHolds: Bool = true, now: Date = Date(), answered: () async -> Void = {}) async {
        guard !answeringSteps.contains(step.handoff), !answeredSteps.contains(step.handoff) else { return }
        guard canAnswerSteps(answersHolds: answersHolds), let signMessage = account.signMessage else {
            stepNotAnswered = Words.app(account.signMessage == nil ? "needs_you.sign_in_again_to_answer" : "needs_you.answer_in_kiff")
            return
        }
        answeringSteps.insert(step.handoff)
        defer { if !Task.isCancelled { answeringSteps.remove(step.handoff) } }
        stepNotAnswered = nil
        let answer = done ? "done" : "skipped"
        let current: Handoff
        do {
            current = try await account.handoff(step.handoff)
        } catch {
            if !Task.isCancelled { stepNotAnswered = Words.app("needs_you.your_step.not_answered", ["why": Self.answerRefusedWords(error)]) }
            return
        }
        guard !Task.isCancelled else { return }
        guard current.status.isEmpty || current.status == "waiting" else {
            stepNotAnswered = Words.app("needs_you.your_step.ended")
            drop(step)
            return
        }
        let at = SigningTime.next(now: now)
        let message = KIFFMessage.handoff(tenant: account.session.tenant, handoffID: current.id, answer: answer, version: current.version, signedAt: at)
        let value: String
        do {
            // The prompt is tafs cloud's words for the answer and the step: "Done · Approve the transfer to Acme".
            try await confirm([done ? step.words.done : step.words.skip, step.what].filter { !$0.isEmpty }.joined(separator: " · "))
            guard !Task.isCancelled else { return }
            value = try signMessage(message)
        } catch {
            guard !Task.isCancelled else { return }
            stepNotAnswered = Self.cancelled(error) ?? Words.app("needs_you.your_step.not_answered_unconfirmed")
            return
        }
        guard !Task.isCancelled else { return }
        do {
            try await account.answerHandoff(current.id, answer: answer, signedAt: at, signature: value)
        } catch let refusal as StepRefusal where refusal.status == 409 {
            // Answered meanwhile, on another device, or ended: nothing more to do here.
            if !Task.isCancelled { stepNotAnswered = Words.app("needs_you.your_step.ended"); drop(step) }
            return
        } catch {
            if !Task.isCancelled { stepNotAnswered = Words.app("needs_you.your_step.not_answered", ["why": Self.answerRefusedWords(error)]) }
            return
        }
        guard !Task.isCancelled else { return }
        drop(step)
        await answered()
    }

    /// Takes an answered or ended step off Needs you at once, while Home still lists it.
    private func drop(_ step: YourStep) {
        answeredSteps.insert(step.handoff)
        steps.removeAll { $0.handoff == step.handoff }
    }

    /// Why KIFF didn't take an answer, in words, never its code, as the iPad's
    /// `answerRefusedWords`: KIFF's `error`, else its `reason`, in the iPad's words; else "KIFF
    /// didn't take the answer" with the app's own line for the status (`PlainError.words`).
    static func answerRefusedWords(_ error: Error) -> String {
        if let refusal = error as? StepRefusal {
            if let key = refusal.error.flatMap({ refusalKeys[$0] }) ?? refusal.reason.flatMap({ refusalKeys[$0] }) { return Words.app(key) }
            // A 401 from KIFF is the iPad's `KIFFError.unauthorized` (KIFFClient.swift:1586), whose
            // words are `error.signed_out` (:34): it never reaches `PlainError`.
            if refusal.status == 401 { return Words.app("needs_you.refused.other", ["why": Words.app("error.signed_out")]) }
            return Words.app("needs_you.refused.other", ["why": Words.app(StepRefusal.plainKey(status: refusal.status))])
        }
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
    /// The person confirms first, Touch ID or the Mac's password, as the iPad's `answer(_:with:)`
    /// signs with `signer.sign(_:reason:)`: "Answer {summary}". A prompt the person closed keeps
    /// the call ("Cancelled. Nothing was approved"); any other failure says it wasn't sent for
    /// want of a confirmation. Neither signs nor sends.
    func refuse(_ call: HeldCall, nextStep: String? = nil) async {
        answering = call.id
        defer { answering = nil }
        do {
            try await account.refuse(call, nextStep: nextStep) {
                try await self.confirm(Words.app("needs_you.prompt.answer", ["summary": call.title ?? call.action]))
            }
            notTaken[call.id] = nil
            await load()
        } catch let unconfirmed as Unconfirmed {
            notTaken[call.id] = Self.cancelled(unconfirmed.error) ?? Words.app("common.not_sent_unconfirmed")
        } catch {
            // Only KIFF's refusal reads "KIFF didn't take the answer", as the iPad's
            // `answerRefusedWords` (AppModel.swift:2994); a prompt's words are its own (:2972-2979).
            notTaken[call.id] = Words.app("needs_you.refused.other", ["why": Self.why(error)])
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
    /// Opens a taf where its door knocks are answered: its Activity.
    var openKnocks: (Home.Taf) -> Void = { _ in }
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
                case .loaded(let calls) where calls.isEmpty && knocked.isEmpty:
                    if model.unproven.isEmpty, model.steps.isEmpty { nothing }
                case .loaded(let calls):
                    ForEach(calls) { card($0) }
                }
                // A knock at a taf's door waits for the owner too, after the held calls, as on the
                // iPad (NeedsYouView.swift:21, 33): its count is Home's, so the rows show whether
                // KIFF's list has been read or not.
                ForEach(knocked) { knockRow($0) }
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
            if model.canAnswerSteps(answersHolds: answersHolds) {
                HStack(spacing: 8) {
                    Button { model.startAnswer(step, done: true, answersHolds: answersHolds, answered: answered) } label: {
                        Text(verbatim: step.words.done).padding(.horizontal, 16)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button { model.startAnswer(step, done: false, answersHolds: answersHolds, answered: answered) } label: {
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

    /// The tafs with knocks at their doors, as Home counts them (`NeedsYouView.knocks`).
    private var knocked: [Home.Taf] { tafs.filter { TafDoors.knocks($0.doors) > 0 } }

    /// A taf's knocks, as the iPad's row: its avatar, its name and how many knocked, opening it
    /// where they're answered.
    private func knockRow(_ taf: Home.Taf) -> some View {
        Button { openKnocks(taf) } label: {
            HStack(spacing: 10) {
                TafAvatar(name: taf.name, color: taf.color, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: taf.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
                    Text(words.count("needs_you.knocks", TafDoors.knocks(taf.doors)))
                        .font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.dim)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).stroke(Theme.amber.opacity(0.4)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(words("needs_you.opens_where_you_answer", ["taf": taf.name]))
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
            Text(verbatim: call.summary).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink)
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
            if let line = Self.notTakenLine(model, call) {
                Text(verbatim: line).font(.system(size: 13)).foregroundColor(Theme.no)
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

    /// The line under a call's answers when the last one wasn't taken, as it is: KIFF's refusal
    /// in "KIFF didn't take the answer" words, a prompt's in its own.
    @MainActor static func notTakenLine(_ model: NeedsYouModel, _ call: HeldCall) -> String? { model.notTaken[call.id] }

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

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
    /// Why the run a held call paused didn't go on after its answer (`HeldContinue`): tafs cloud's words when the run had
    /// already ended, or what didn't go through and why. Nil once it went on.
    @Published private(set) var runNotContinued: String?
    /// The taf at tafs cloud that acts as a KIFF agent (Home's `tafID`), set by the window: a held call's run is continued
    /// by it. Nil for an agent tafs doesn't run, whose call has no run to continue.
    var tafOf: @MainActor (String) -> String? = { _ in nil }
    /// Steps answered or ended here that Home may still list.
    private var answeredSteps: Set<String> = []
    /// The answers on their way: cancelled at sign-out, so none outlives its session.
    private var stepAnswers: [String: Task<Void, Never>] = [:]
    /// Of tafs cloud's count, the steps answered here that it still counts, as the iPad's.
    private var answeredStillCounted = 0
    /// Coach's chats waiting on the person, as Home last listed them (`coach_waiting`), and its
    /// "Set all aside" (`coach_waiting_clear`).
    @Published private(set) var coachWaitingListed: [CoachWaiting] = []
    /// The saved sign-ins that need the owner, as Home lists them (`sign_ins`), less those put off here just now.
    @Published private(set) var signIns: [SignInNeed] = []
    /// Asks planque for a cloud connection's live sign-in view, signed by this Mac's device key; nil where it can't.
    var siteSignIn: ((String) async throws -> SiteSignInView)?
    /// The sign-in view open now, and a sign-in item's line when its button didn't go through.
    @Published var signInView: ConnectAppsModel.OpenSignIn?
    @Published private(set) var signInProblem: [String: String] = [:]
    @Published private(set) var coachWaitingClear: CoachWaitingClear?
    /// The chats being set aside now: one call per chat at a time, so a second click sends
    /// nothing until tafs cloud answers.
    @Published private(set) var settingAside: Set<String> = []
    /// Why the last Set aside wasn't taken, in tafs cloud's words.
    @Published private(set) var setAsideNotDone: String?
    /// What Home counted for Needs you (`needs_you`), and the Card unit requests it listed.
    @Published private(set) var homeCount: Int?
    @Published private(set) var homeWords: String?
    @Published private(set) var cardUnits = 0
    /// tafs cloud, for Set aside; nil where nothing is set aside.
    let cloud: CloudClient?
    /// This device's signed read of its connections, sent with Set aside, as the iPad's.
    private let proof: (() async -> String?)?

    let account: AccountClient
    /// Where an approval is signed on this Mac.
    let route: ApprovalRoute
    /// An answer that grants authority on this Mac's security key, through its PIN sheet (`PasskeySession.approveOnce`,
    /// `extraRoom`), set by the window; nil where this Mac has no key, and the card says to approve on another device.
    var answerWithKey: ((HeldCall, Answer) async throws -> Void)?
    /// Any act this Mac's security key approves (`KeyAct`), named in its sheet, set by the window: "Allow this from now
    /// on" confirms KIFF's draft with it. Nil where this Mac has no key.
    var approveWithKey: ((KeyAct, String) async throws -> Data)?
    /// "Allow this from now on", open on a held call (`AllowSheetView`).
    @Published var allow: AllowSheet?
    /// The person confirms before the device key signs a step, as the iPad's `sign(_:reason:)`
    /// does: Touch ID, or the Mac's login password, which every Mac has. Throws when not
    /// confirmed; the prompt's words are tafs cloud's for the answer and the step.
    let confirm: (String) async throws -> Void

    init(account: AccountClient, route: ApprovalRoute, confirm: @escaping (String) async throws -> Void = NeedsYouModel.confirmOwner,
         cloud: CloudClient? = nil, proof: (() async -> String?)? = nil) {
        self.account = account
        self.route = route
        self.confirm = confirm
        self.cloud = cloud
        self.proof = proof
    }

    /// The owner's presence, as the iPad's `authenticate(reason:)` with `.deviceOwnerAuthentication`.
    nonisolated static func confirmOwner(_ reason: String) async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { throw error ?? LAError(.authenticationFailed) }
        guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else { throw LAError(.authenticationFailed) }
    }

    /// The words for a prompt the person closed, as the iPad's `ApprovalReadiness.cancelled`; nil
    /// for any other failure. For a call still waiting (Refuse, Your step), so the request is kept.
    static func cancelled(_ error: Error) -> String? {
        closed(error) ? Words.app("approval.cancelled_nothing_approved_request_kept") : nil
    }

    /// Whether the person closed the prompt, rather than it failing.
    nonisolated static func closed(_ error: Error) -> Bool {
        if error is OwnerPrompt.Closed { return true }
        switch (error as? LAError)?.code {
        case .userCancel?, .systemCancel?, .appCancel?, .userFallback?: return true
        default: return false
        }
    }

    /// `confirmOwner` for Core, which can't read the system's errors: a closed prompt throws
    /// `OwnerPrompt.Closed`, and any other failure as it is.
    nonisolated static func confirmOwnerForCore(_ reason: String) async throws {
        do { try await confirmOwner(reason) } catch where closed(error) { throw OwnerPrompt.Closed() }
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
        answeredStillCounted = answeredSteps.count
        steps = listed.filter { !answeredSteps.contains($0.handoff) }
    }

    /// What Home lists for Needs you, as the iPad's `show` (AppModel.swift:2302-2310): its steps,
    /// Coach's waiting chats and Set all aside, its count, and its Card unit requests.
    func show(_ page: Home.Page) {
        showSteps(page.yourSteps)
        coachWaitingListed = page.coachWaiting
        coachWaitingClear = page.coachWaitingClear
        signIns = page.signIns
        homeCount = page.needsYouCount
        homeWords = page.needsYouWords
        cardUnits = page.cardUnits
    }

    /// Sign in again on a sign-in item: planque's live view, opened only on planque's own origin.
    func signIn(_ need: SignInNeed) async {
        guard let siteSignIn else { return }
        signInProblem[need.id] = nil
        do {
            let view = try await siteSignIn(need.grant)
            guard view.opens else {
                signInProblem[need.id] = Words.app("error.changed")
                return
            }
            signInView = ConnectAppsModel.OpenSignIn(grant: need.grant, view: view)
        } catch {
            signInProblem[need.id] = NeedsYouModel.why(error)
        }
    }

    /// Later (soon) or Skip this run (stopped), each a request tafs cloud keeps for everyone on the account. The item
    /// leaves the list here at once; the next Home read is tafs cloud's word on it.
    func putOff(_ need: SignInNeed) async {
        guard let cloud else { return }
        signInProblem[need.id] = nil
        do {
            if need.stopped { try await cloud.skipHeldSignIn(taf: need.taf.id) } else { try await cloud.laterSignIn(grant: need.grant, site: need.site) }
            signIns.removeAll { $0.id == need.id }
        } catch {
            signInProblem[need.id] = NeedsYouModel.why(error)
        }
    }

    /// Coach's waiting chats as Needs you draws them: less the one open in Coach (`onScreen`), and
    /// less those being set aside.
    func coachWaiting(onScreen: String? = nil) -> [CoachWaiting] {
        NeedsYouCount.shown(coachWaitingListed, onScreen: onScreen, settingAside: settingAside)
    }

    /// "Set all aside", above two or more waiting chats, when tafs cloud sent it, as the iPad's `setAllAside`.
    func setAllAside(onScreen: String? = nil) -> CoachWaitingClear? {
        coachWaiting(onScreen: onScreen).count > 1 ? coachWaitingClear : nil
    }

    /// What Needs you's count is made of, as the iPad's `needsYouCount` reads it.
    func countParts(onScreen: String? = nil) -> NeedsYouCount.Parts {
        let shown = coachWaiting(onScreen: onScreen).count
        return NeedsYouCount.Parts(home: homeCount, homeWords: homeWords, held: count, cardUnits: cardUnits, steps: steps.count,
                                   unproven: unproven.count, coachWaiting: shown, coachWaitingHidden: coachWaitingListed.count - shown,
                                   answeredStillCounted: answeredStillCounted)
    }

    /// Needs you's number in the sidebar and on the Overview, as the iPad's `needsYouCount`.
    func needsYouCount(onScreen: String? = nil) -> Int { NeedsYouCount.count(countParts(onScreen: onScreen)) }

    /// Sets a waiting Coach chat aside, or every one with nil, as the iPad's `setAsideCoach`
    /// (AppModel.swift:7781-7814): tafs cloud's "not now", never an approval, and nothing is
    /// signed: only this device's read of its connections goes with it, as with Coach's thread.
    /// One call per chat at a time. The row goes once tafs cloud says so; a refusal keeps it and
    /// says why, in tafs cloud's words. `done` gets the chats it ended, then the lists are read again.
    func setAside(_ session: String?, done: (Set<String>) async -> Void = { _ in }) async {
        guard let cloud = self.cloud else { return }
        // Set all aside ends every chat tafs cloud listed, so it's guarded by all of them.
        let sessions = session.map { Set([$0]) } ?? Set(coachWaitingListed.map(\.session))
        guard !sessions.isEmpty, settingAside.isDisjoint(with: sessions) else { return }
        settingAside.formUnion(sessions)
        setAsideNotDone = nil
        let make = proof
        var signed: String?
        if let make { signed = await make() }
        let answer: CoachSetAside
        do {
            answer = try await cloud.setAsideCoach(session, proof: signed)
        } catch {
            settingAside.subtract(sessions)
            setAsideNotDone = Self.why(error)
            return
        }
        settingAside.subtract(sessions)
        let ended = Set(answer.setAside)
        coachWaitingListed.removeAll { ended.contains($0.session) }
        await done(ended)
    }

    /// Whether this Mac can answer a step, as the iPad's `canAnswerSteps`: KIFF checks the device
    /// key's signature, so the session must hold it, and the person must answer the account's
    /// holds (KIFF's `holds.answer`).
    func canAnswerSteps(answersHolds: Bool) -> Bool { answersHolds && account.signMessage != nil }

    /// Whether a step's card still shows, as the iPad's `canAnswer(step:)`: not answered or ended
    /// here, while a list read before that may still carry it.
    func canAnswer(step handoff: String) -> Bool { !answeredSteps.contains(handoff) }

    /// The step `handoff` waits on as Home lists it, as the iPad's `yourStep(_:)`: Home's carries
    /// the vendor's link when tafs cloud vouched for it, a request's own never does.
    func listedStep(_ handoff: String) -> YourStep? { steps.first { $0.handoff == handoff } }

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
        if steps.contains(where: { $0.handoff == step.handoff }) { answeredStillCounted += 1 }
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
        if case KIFFError.refused(let status, let code) = error {
            if let key = refusalKeys[code] { return Words.app(key) }
            // KIFF's own refusal reads as the iPad's `KIFFError.server`'s `PlainError.words(status:)`: the app's line
            // for its status, never KIFF's code, which is for the log. A 401 is the iPad's `.unauthorized`. A status of 0
            // is this app's own refusal before anything was sent, whose words are `why`'s.
            if status == 401 { return Words.app("needs_you.refused.other", ["why": Words.app("error.signed_out")]) }
            if status != 0 { return Words.app("needs_you.refused.other", ["why": Words.app(StepRefusal.plainKey(status: status))]) }
        }
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

    /// The answer to "Did this happen?", on the security key, as the iPad's `answerHappened`: KIFF's approval route, so
    /// the key approves this one answer (`KeyAct.happened`), named in its sheet as the iPad's prompt ("Say it happened:
    /// {title}"). Then the call leaves the list and the list is read again: KIFF's list is the truth. A closed sheet
    /// sends nothing and says nothing; "Approve on your phone instead" says to approve on another device; KIFF's refusal
    /// reads the list again too, and says why in the app's words while the call is still listed. One answer at a time,
    /// as the held calls'.
    func answerHappened(_ call: Unproven, happened: Bool) async {
        guard let approveWithKey, answering == nil else { return }
        let key = Self.happenedKey(call)
        answering = key
        defer { answering = nil }
        let act = KeyAct.happened(proposal: call.proposal, happened)
        do {
            _ = try await approveWithKey(act, act.title(Words.app, device: call.title))
            notTaken[key] = nil
            unproven.removeAll { $0.proposal == call.proposal }
            await loadUnproven(answersHolds: true)
        } catch is CancellationError {
            notTaken[key] = nil
        } catch is ApproveOnPhone {
            notTaken[key] = Self.why(ApproveOnPhone())
        } catch {
            // KIFF's refusal: the list is read again, so a call answered elsewhere ("already answered") leaves at once;
            // its line is said after the read, which keeps it while the call is still listed.
            let line = Self.answerRefusedWords(error)
            if case KIFFError.refused(let status, _) = error, status != 0 { await loadUnproven(answersHolds: true) }
            notTaken[key] = unproven.contains { $0.proposal == call.proposal } ? line : nil
        }
    }

    /// Whether "Did this happen?" offers Yes and No: for someone who answers held calls, on a Mac that approves with
    /// its security key. Elsewhere the card says to approve on another device, or nothing.
    func offersHappened(answersHolds: Bool) -> Bool { answersHolds && approveWithKey != nil }

    /// A "Did this happen?" answer's key in `answering` and `notTaken`, apart from the held calls' ids.
    nonisolated static func happenedKey(_ call: Unproven) -> String { "happened:\(call.proposal)" }

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
            await goOn(call)
            await load()
        } catch let unconfirmed as Unconfirmed {
            notTaken[call.id] = Self.cancelled(unconfirmed.error) ?? Words.app("common.not_sent_unconfirmed")
        } catch {
            // Only KIFF's refusal reads "KIFF didn't take the answer", as the iPad's
            // `answerRefusedWords` (AppModel.swift:2994); a prompt's words are its own (:2972-2979).
            notTaken[call.id] = Self.answerRefusedWords(error)
        }
    }

    /// Approve once, on the security key, as the iPad's `answer(_:with: .approveOnce)`: one approval for this one call,
    /// then the list read again. A closed sheet sends nothing and says nothing; "Approve on your phone instead" says to
    /// approve on another device; anything else says KIFF didn't take it, with why.
    func approveOnce(_ call: HeldCall) async { await answerOnKey(call, .approveOnce) }

    /// Extra room, on the security key, as the iPad's `answer(_:with: .extraRoom)`: KIFF's `change-card` for this one call,
    /// over a total approving once can't pass. Then as Approve once.
    func extraRoom(_ call: HeldCall) async { await answerOnKey(call, .changeCard) }

    private func answerOnKey(_ call: HeldCall, _ answer: Answer) async {
        guard let answerWithKey, answer.grants, answering == nil else { return }
        // A fill in Chrome is allowed only with the phone's release: nothing is asked or sent here.
        guard !call.fillsInChrome else {
            notTaken[call.id] = Self.why(ApproveOnPhone())
            return
        }
        answering = call.id
        defer { answering = nil }
        do {
            try await answerWithKey(call, answer)
            notTaken[call.id] = nil
            await goOn(call)
            await load()
        } catch is CancellationError {
            notTaken[call.id] = nil
        } catch is ApproveOnPhone {
            notTaken[call.id] = Self.why(ApproveOnPhone())
        } catch {
            notTaken[call.id] = Self.answerRefusedWords(error)
        }
    }

    /// Once KIFF took an answer to a held call, the run that paused on it is asked to go on now (`HeldContinue`, as the
    /// iPad's `continueHeld` and Windows'), not only when KIFF's alert reaches tafs cloud. A run that had already ended
    /// says so at the top of Needs you, in tafs cloud's words; one KIFF's alert already continued says nothing.
    private func goOn(_ call: HeldCall) async {
        runNotContinued = nil
        guard let cloud, let taf = tafOf(call.subject) else { return }
        do {
            try await cloud.continueHeld(taf: taf, hold: call.id)
        } catch {
            runNotContinued = HeldContinue.said(Words.app, summary: call.summary, error: error)
        }
    }

    /// Whether this card offers Approve once: KIFF allows it for the call, and this Mac approves with its key.
    /// Never for a step that fills a field in Chrome: that needs the phone's release, which this Mac can't make.
    func offersApproveOnce(_ call: HeldCall) -> Bool {
        call.canApproveOnce && call.accountingVersion != nil && answerWithKey != nil && !call.fillsInChrome && !call.purchaseUnreadable
    }

    /// Whether this card offers Extra room, as the iPad's: over a total approving once can't pass, for someone who
    /// manages the Cards (KIFF's `cards.manage`), on a Mac that approves with its key.
    func offersExtraRoom(_ call: HeldCall, managesCards: Bool) -> Bool {
        // Never on a purchase: its room is the case's, approved once (the purchase approval design, "Extra room is never offered").
        !call.canApproveOnce && managesCards && call.accountingVersion != nil && answerWithKey != nil && !call.fillsInChrome
            && call.purchase == nil && !call.purchaseUnreadable
    }

    static func why(_ error: Error) -> String {
        switch error {
        case is ApproveOnPhone: return Words.app("approval.device_can_not_approve_approve")
        case let refusal as CloudRefusal: return refusal.why(Words.app)
        // KIFF no longer accepts the sign-in: its words, never KIFF's code ("unauthorized"). The window
        // ends and sign-in opens (`SessionWatch`).
        case KIFFError.refused(401, _): return Words.app("error.signed_out")
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
    /// Whether this person manages the account's Cards (KIFF's `cards.manage`): the over-total line says they can give
    /// extra room.
    var managesCards = true
    /// Whether "Allow this from now on" is live for this account (tafs cloud lists `holds.allow`).
    var allowIsLive = false
    /// Opens a taf where its door knocks are answered: its Activity.
    var openKnocks: (Home.Taf) -> Void = { _ in }
    /// The held purchases whose lines are open (Show more): closed each time Needs you is drawn anew, never remembered.
    @State private var purchaseOpen: Set<String> = []
    /// Purchases drawn with their lines open from the start: a screenshot's, as a tap on Show more would leave them.
    var linesOpenAtStart: Set<String> = []
    /// Reads the lists again once a step is answered: the taf's run goes on.
    var answered: () async -> Void = {}
    /// Whether this person may use Coach: a waiting chat's Open Coach is theirs alone.
    var mayUseCoach = false
    /// Opens Coach on a waiting chat.
    var openCoach: (CoachWaiting) -> Void = { _ in }
    /// What follows chats set aside: Coach leaves them, and the lists are read again.
    var setAsideDone: (Set<String>) async -> Void = { _ in }
    /// Alerts on this Mac: in a `PUSH=1` build, `AlertsCard` offers them while they're off.
    var alerts: AlertsModel?
    @Environment(\.openURL) private var openURL
    /// The held calls whose Details the person folded away: open by default, since a held browser
    /// call's steps are what the person reads before approving.
    @State private var folded: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(words("needs_you.title")).font(Theme.display(34)).foregroundColor(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let alerts, alerts.pushes, answersHolds { AlertsCard(model: alerts) }
                if let why = model.stepNotAnswered {
                    Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
                }
                if let why = model.runNotContinued {
                    Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("needs-you.run-not-continued")
                }
                // A step a taf handed its owner comes first, oldest first, as the iPad's.
                ForEach(model.steps) { YourStepCard(model: model, step: $0, answersHolds: answersHolds, answered: answered) }
                // Coach waits on the person in a chat, after the steps, as on the iPad
                // (NeedsYouView.swift:16-19): Set all aside above them, with two or more.
                coachWaiting
                // A saved sign-in that needs the owner: soon, or stopped and holding a run (browser batch 2).
                ForEach(model.signIns) { SignInNeedCard(model: model, need: $0) }
                // A money call whose outcome KIFF can't prove: the owner says whether it happened.
                ForEach(model.unproven) { happened($0) }
                switch model.state {
                case .loading:
                    ProgressView().controlSize(.small)
                case .unread(let why):
                    Text(words("needs_you.request_not_read", ["why": why])).font(.system(size: 14)).foregroundColor(Theme.no)
                case .loaded(let calls) where calls.isEmpty && knocked.isEmpty:
                    if model.unproven.isEmpty, model.steps.isEmpty, model.coachWaiting().isEmpty, model.signIns.isEmpty { nothing }
                case .loaded(let calls):
                    ForEach(calls) { card($0) }
                }
                // A knock at a taf's door waits for the owner too, after the held calls, as on the
                // iPad (NeedsYouView.swift:21, 33): its count is Home's, so the rows show whether
                // KIFF's list has been read or not.
                ForEach(knocked) { knockRow($0) }
            }
            .padding(28)
            .pageColumn(.reading)
        }
        .background(Theme.background)
        // "Allow this from now on", over Needs you, while it's open on a call.
        .sheet(isPresented: Binding(get: { model.allow != nil }, set: { if !$0 { model.allow = nil } })) {
            AllowSheetView(model: model).environment(\.words, words)
        }
        // Sign in again: planque's live view until Close; then Home is read again, so the item follows its check.
        .sheet(item: $model.signInView) { open in
            SiteSignInSheet(view: open.view) { Task { model.signInView = nil; await answered() } }
                .environment(\.words, words)
        }
        .task {
            await model.load()
            await model.loadUnproven(answersHolds: answersHolds)
        }
    }

    /// Coach's waiting chats, as the iPad's: tafs cloud's words, its way in, and Set aside; why
    /// the last Set aside wasn't taken over them.
    @ViewBuilder private var coachWaiting: some View {
        if let why = model.setAsideNotDone {
            Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
        }
        if let clear = model.setAllAside() { SetAllAsideButton(model: model, clear: clear, done: setAsideDone) }
        ForEach(model.coachWaiting()) { waiting in
            CoachWaitingCard(model: model, waiting: waiting, mayUseCoach: mayUseCoach, open: openCoach, done: setAsideDone)
        }
    }

    private var nothing: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Board 6, nothing waiting (docs/window.md › Illustrations), above its words.
            Illustration.nothingWaiting.frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                Text(words("needs_you.nothing")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                Text(words("needs_you.empty_hint")).font(.system(size: 14)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        }
    }

    /// "Did this happen?", as the iPad's `DidThisHappenCard`: KIFF's words for the call (else its
    /// title and amount) and for why it asks. The answer is an approval: on a Mac with its security key, No and Yes
    /// (`NeedsYouModel.answerHappened`); elsewhere, for someone who answers held calls, it says to approve on another
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
            if model.offersHappened(answersHolds: answersHolds) {
                // The iPad's two answers, No then Yes, on the security key, with what No does under them.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Button(words("record.did_this_happen.no")) { Task { await model.answerHappened(call, happened: false) } }
                            .buttonStyle(OutlineButtonStyle())
                            .accessibilityIdentifier("happened.no")
                        Button(words("record.did_this_happen.yes")) { Task { await model.answerHappened(call, happened: true) } }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("happened.yes")
                        if model.answering == NeedsYouModel.happenedKey(call) { ProgressView().controlSize(.small) }
                    }
                    .disabled(model.answering != nil)
                    Text(words("record.did_this_happen.what_no_does")).font(.system(size: 12)).foregroundColor(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    if let line = model.notTaken[NeedsYouModel.happenedKey(call)] {
                        Text(verbatim: line).font(.system(size: 13)).foregroundColor(Theme.no)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if Self.saysCantApprove(answersHolds: answersHolds, route: model.route) {
                Text(words("approval.device_can_not_approve_approve")).font(.system(size: 13)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("happened.\(call.proposal)")
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
    /// approval key gets no line: its security key answers there (`offersHappened`).
    static func saysCantApprove(answersHolds: Bool, route: ApprovalRoute) -> Bool {
        answersHolds && route == .phoneOrPasskey
    }

    /// The tafs with knocks at their doors, as Home counts them (`NeedsYouView.knocks`).
    /// The tafs with knocks or replies waiting at their doors: each opens on its Activity, where they're answered.
    private var knocked: [Home.Taf] { tafs.filter { TafDoors.knocks($0.doors) > 0 || TafDoors.heldReplies($0.doors).count > 0 } }

    /// A taf's knocks, as the iPad's row: its avatar, its name and how many knocked, opening it
    /// where they're answered.
    private func knockRow(_ taf: Home.Taf) -> some View {
        Button { openKnocks(taf) } label: {
            HStack(spacing: 10) {
                TafAvatar(name: taf.name, color: taf.color, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: taf.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
                    // A held reply in its newest line, as its notification said it (tafs cloud's words), then the knocks.
                    if let line = TafDoors.heldReplies(taf.doors).line {
                        Text(verbatim: line).font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
                    }
                    if TafDoors.knocks(taf.doors) > 0 {
                        Text(words.count("needs_you.knocks", TafDoors.knocks(taf.doors)))
                            .font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
                    }
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

    /// The call's arguments, every one in full, one line each with nested values indented below their
    /// name (`HeldArguments.lines`, kiff/tafs `contracts/held-arguments.json`): never shortened to "…".
    private func details(_ call: HeldCall) -> some View {
        let open = !folded.contains(call.id)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                if open { folded.insert(call.id) } else { folded.remove(call.id) }
            } label: {
                Text(words(open ? "needs_you.details_open" : "needs_you.details_closed"))
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.soft)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("held-details")
            if open {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(call.argumentLines.enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.soft.opacity(0.08)))
                .accessibilityElement(children: .combine)
            }
        }
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
            if let purchase = call.purchase {
                purchaseBody(call, purchase)
            } else if call.purchaseUnreadable {
                // A purchase this app can't read: its name only, and nothing to sign here.
                Text(verbatim: call.summary).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                callBody(call)
            }
            answers(call)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).stroke(Theme.amber.opacity(0.4)))
        .accessibilityElement(children: .contain)
    }

    /// A held call's own lines: what it moves, what it is, why KIFF held it, the taf's words and the arguments.
    @ViewBuilder private func callBody(_ call: HeldCall) -> some View {
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
            if !call.argumentLines.isEmpty { details(call) }
    }

    /// A held purchase, as the approved design draws it (Thune): the shop, the total with what it includes, where it's
    /// delivered, the lines behind Show more (closed each time), the price rule and what the card allows beside the
    /// answers, and why the Card asks, every word KIFF's. Approving signs exactly these lines, open or closed.
    @ViewBuilder private func purchaseBody(_ call: HeldCall, _ p: Purchase) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: p.words.title).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = p.words.subtitle { Text(verbatim: subtitle).font(.system(size: 13)).foregroundColor(Theme.soft) }
        }
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: p.words.total).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundColor(Theme.ink)
                .accessibilityIdentifier("purchase.total")
            if let note = p.words.totalNote { Text(verbatim: note).font(.system(size: 12)).foregroundColor(Theme.dim) }
        }
        Text(verbatim: p.words.delivery).font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
        purchaseLines(call, p)
        VStack(alignment: .leading, spacing: 4) {
            ForEach([p.words.priceRule, p.words.grant, p.words.buysNow].compactMap { $0 }, id: \.self) { fact in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(Theme.dim.opacity(0.6)).frame(width: 5, height: 5).accessibilityHidden(true)
                    Text(verbatim: fact).font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if let reason = p.words.reason ?? call.reasonText {
            Text(verbatim: reason).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.amberText)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Theme.amber.opacity(0.14)))
        }
    }

    /// Show more and the lines it opens, each as the checkout lists it, then the charges, so the open list adds up to the total.
    @ViewBuilder private func purchaseLines(_ call: HeldCall, _ p: Purchase) -> some View {
        let open = purchaseOpen.contains(call.id) != linesOpenAtStart.contains(call.id)
        if !p.words.lines.isEmpty || !p.words.charges.isEmpty {
            Button {
                if open { purchaseOpen.remove(call.id) } else { purchaseOpen.insert(call.id) }
            } label: {
                HStack(spacing: 4) {
                    // KIFF's word for it; the chevron says whether it's open (no shared "Show less" word yet).
                    Text(verbatim: p.words.showMore ?? words("common.show_the_list"))
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
                }
                .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.amberText)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("purchase.show_more")
        }
        if open {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(p.words.lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: line.name).font(.system(size: 13, weight: .medium)).foregroundColor(Theme.ink)
                        Spacer(minLength: 8)
                        Text(verbatim: [line.quantity, line.amount].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 13)).foregroundColor(Theme.soft)
                    }
                }
                ForEach(Array(p.words.charges.enumerated()), id: \.offset) { _, charge in
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: charge.name).font(.system(size: 13, weight: .medium)).foregroundColor(Theme.ink)
                        Spacer(minLength: 8)
                        Text(verbatim: charge.amount).font(.system(size: 13)).foregroundColor(Theme.soft)
                    }
                }
            }
            .padding(.top, 4)
            .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .top)
        }
    }

    /// The card's answers, as the iPad's `answers(refuseOnly:)`: what's sent, Approve once on the key, the over-total
    /// line, the next steps, then Refuse, and why the last answer wasn't taken.
    @ViewBuilder private func answers(_ call: HeldCall) -> some View {
        Text(verbatim: call.purchase?.words.nothingUntil ?? words("needs_you.nothing_sent")).font(.system(size: 14)).foregroundColor(Theme.soft)
        if model.route == .phoneOrPasskey {
            Text(words("approval.device_can_not_approve_approve")).font(.system(size: 13)).foregroundColor(Theme.soft)
                .fixedSize(horizontal: false, vertical: true)
        } else if call.fillsInChrome || call.purchaseUnreadable {
            // A fill in Chrome opens only with the phone's release: Refuse stays here, and allowing is the phone's.
            Text(words("approval.security_key.on_phone")).font(.system(size: 13)).foregroundColor(Theme.soft)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("needs_you.fill_on_phone")
        }
        if model.offersApproveOnce(call) { approveOnceButton(call) }
        if !call.canApproveOnce, call.purchase == nil { overTotal }
        if model.offersExtraRoom(call, managesCards: managesCards) { extraRoomButton(call) }
        if call.purchase == nil, !call.purchaseUnreadable, let taf = tafs.first(where: { $0.kiffAgent == call.subject })?.tafID,
           model.offersAllow(call, taf: taf, managesCards: managesCards, allowIsLive: allowIsLive) {
            // The third answer, as the iPad's: a Card change, made on the tap, so calls like this go on their own.
            Button(words("needs_you.allow_from_now_on")) { model.openAllow(call, taf: taf) }
                .buttonStyle(OutlineButtonStyle())
                .disabled(model.answering != nil)
                .accessibilityIdentifier("needs_you.allow")
        }
        nextSteps(call)
        // Refuse, as the iPad's outlined button: the card's width, in red. Not for a purchase whose case can't be read:
        // there's nothing to sign it for.
        if !call.purchaseUnreadable || call.purchaseBinding != nil {
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
        }
        if let line = Self.notTakenLine(model, call) {
            Text(verbatim: line).font(.system(size: 13)).foregroundColor(Theme.no)
        }
    }

    /// Extra room, as the iPad's filled button under the over-total line, on the security key: KIFF's `change-card` for
    /// this one call, until that total resets. Its PIN sheet names the call.
    private func extraRoomButton(_ call: HeldCall) -> some View {
        Button { Task { await model.extraRoom(call) } } label: {
            HStack(spacing: 8) {
                Image(systemName: "key.fill").accessibilityHidden(true)
                Text(words("needs_you.extra_room"))
                if model.answering == call.id { ProgressView().controlSize(.small) }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(model.answering != nil)
        .accessibilityIdentifier("needs_you.extra_room")
    }

    /// Over a total the Card keeps across calls, as the iPad's: approving once can't pass it (kiff/tafs#138, item 49).
    /// Someone who manages the Cards can give it extra room; anyone else is told who can.
    private var overTotal: some View {
        Text(words(managesCards ? "needs_you.over_total_manager" : "needs_you.over_total")).font(.system(size: 13)).foregroundColor(Theme.soft)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The call's next steps, as the iPad's: each refuses the call with that step for the taf, in its own words, signed
    /// by the device key once the person confirms, as Refuse is.
    @ViewBuilder private func nextSteps(_ call: HeldCall) -> some View {
        if !call.nextSteps.isEmpty {
            HStack(spacing: 8) {
                ForEach(call.nextSteps, id: \.self) { step in
                    Button { Task { await model.refuse(call, nextStep: step) } } label: { Text(verbatim: step).lineLimit(2) }
                        .buttonStyle(OutlineButtonStyle())
                        .disabled(model.answering != nil)
                }
            }
            .accessibilityIdentifier("needs_you.next_steps")
        }
    }

    /// Approve once, as the iPad's filled button above Refuse, on the security key: its PIN sheet names the call.
    private func approveOnceButton(_ call: HeldCall) -> some View {
        Button { Task { await model.approveOnce(call) } } label: {
            HStack(spacing: 8) {
                Image(systemName: "key.fill").accessibilityHidden(true)
                Text(words("needs_you.approve_once"))
                if model.answering == call.id { ProgressView().controlSize(.small) }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(model.answering != nil)
        .accessibilityIdentifier("needs_you.approve_once")
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

/// Alerts offered on Needs you while they're off, as the iPad's `AlertsCard`: a call waiting for the person reaches this
/// Mac even with tafs closed. Only in a `PUSH=1` build (`AlertsModel.pushes`), for someone whose role may answer held
/// calls; gone once alerts are on.
struct AlertsCard: View {
    @Environment(\.words) private var words
    @ObservedObject var model: AlertsModel

    var body: some View {
        if !model.on, model.canAnswerHolds != false {
            VStack(alignment: .leading, spacing: 8) {
                Text(words("needs_you.know_moment_taf_needs_you")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                Text(words("needs_you.get_alert_when_call_waits")).font(.system(size: 14)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
                if let why = model.why {
                    Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
                }
                Button(words(model.turningOn ? "needs_you.turning_on" : "needs_you.turn_alerts")) { Task { await model.turnOn(words: words) } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.turningOn)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
            .accessibilityIdentifier("needs-you.alerts-card")
        }
    }
}


/// A saved sign-in that needs the owner (browser batch 2, frames 2a and 2b), every word tafs cloud's: soon, edged in amber,
/// with Later; or stopped, edged in red, its run waiting before it starts, with Skip this run. Sign in again opens planque's
/// live view; Why? says how tafs knows.
struct SignInNeedCard: View {
    @ObservedObject var model: NeedsYouModel
    let need: SignInNeed

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: need.words.title.uppercased()).font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundColor(need.stopped ? Theme.no : Theme.amberText)
            Text(verbatim: need.words.line).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: need.taf.name).font(.system(size: 13)).foregroundColor(Theme.soft)
            if let why = need.words.why {
                Text(verbatim: why).font(.system(size: 12.5)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                if model.siteSignIn != nil {
                    Button(need.words.signIn) { Task { await model.signIn(need) } }
                        .buttonStyle(PrimaryButtonStyle()).fixedSize()
                        .accessibilityIdentifier("needs-you.sign-in")
                }
                if let other = need.words.other {
                    Button { Task { await model.putOff(need) } } label: { Text(verbatim: other).padding(.horizontal, 16) }
                        .buttonStyle(OutlineButtonStyle()).fixedSize()
                        .accessibilityIdentifier(need.stopped ? "needs-you.sign-in.skip" : "needs-you.sign-in.later")
                }
            }
            if let problem = model.signInProblem[need.id] {
                Text(verbatim: problem).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous)
            .stroke(need.stopped ? Theme.no.opacity(0.35) : Theme.amber.opacity(0.55)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("needs-you.sign-in-need")
    }
}

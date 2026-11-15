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
    /// Opens a taf where its door knocks are answered: its Activity.
    var openKnocks: (Home.Taf) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(words("needs_you.title")).font(Theme.display(34)).foregroundColor(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                // A money call whose outcome KIFF can't prove: the owner says whether it happened.
                ForEach(model.unproven) { happened($0) }
                switch model.state {
                case .loading:
                    ProgressView().controlSize(.small)
                case .unread(let why):
                    Text(words("needs_you.request_not_read", ["why": why])).font(.system(size: 14)).foregroundColor(Theme.no)
                case .loaded(let calls) where calls.isEmpty && knocked.isEmpty:
                    if model.unproven.isEmpty { nothing }
                case .loaded(let calls):
                    ForEach(calls) { card($0) }
                    // A knock at a taf's door waits for the owner too, as on the iPad.
                    ForEach(knocked) { knockRow($0) }
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

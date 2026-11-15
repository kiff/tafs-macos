import SwiftUI

@MainActor
final class UsageModel: ObservableObject {
    enum Read<Value: Equatable>: Equatable {
        case loading
        case loaded(Value)
        case unread(why: String)
    }

    @Published private(set) var balance: Read<Usage.Balance> = .loading
    @Published private(set) var credits: Read<Usage.Credits> = .loading
    /// Whether the last period is shown, not this one.
    @Published private(set) var previous = false
    /// KIFF's side: the plan, its packs and members' requests, as the iPad's `usage`. A read
    /// that fails keeps what was read, and says why (`usageError`).
    @Published private(set) var usage: KIFFUsage?
    @Published private(set) var usageError: String?
    /// Why the last request wasn't sent, withdrawn or declined, as the iPad's `planMessage`.
    @Published private(set) var planMessage: String?

    private let cloud: CloudClient
    /// KIFF, for its usage and the requests; nil reads tafs cloud's halves alone.
    private let account: AccountClient?
    /// The person confirms before the device key signs a decline, as the iPad's
    /// `signer.sign(_:reason:)`: Touch ID, or the Mac's password. Throws when not confirmed.
    private let confirm: (String) async throws -> Void
    private var asked = 0
    /// The decline on its way: cancelled at sign-out, so none outlives its session.
    private var declining: Task<Void, Never>?

    init(cloud: CloudClient, account: AccountClient? = nil,
         confirm: @escaping (String) async throws -> Void = NeedsYouModel.confirmOwner) {
        self.cloud = cloud
        self.account = account
        self.confirm = confirm
    }

    /// Each half is read on its own: one that can't be read doesn't take the other away. Then
    /// KIFF's usage, as the iPad's `refreshUsage` (AppModel.swift:3344-3375).
    func load() async {
        do { balance = .loaded(try await cloud.balance()) } catch { balance = .unread(why: NeedsYouModel.why(error)) }
        await loadCredits()
        await loadUsage()
    }

    /// KIFF's usage: what's read replaces what was; a read that fails keeps it, and says why.
    private func loadUsage() async {
        guard let account else { return }
        do {
            usage = try await account.usage()
            usageError = nil
        } catch {
            usageError = Words.app("billing.plan_could_not_read_kiff", ["why": Self.plainWhy(error)])
        }
    }

    /// The packs a member may ask for, as the iPad's `offeredPacks` (AppModel.swift:3556-3558):
    /// the First month pack first, only while tafs cloud says it can be bought.
    var offeredPacks: [KIFFUsage.Store.Pack] {
        var firstMonth = false
        if case .loaded(let balance) = balance { firstMonth = balance.firstMonthReady }
        return usage?.store?.offered(firstMonth: firstMonth) ?? []
    }

    /// Asks the account's admins, with a reason: for a raise of the spend limit, or for a pack,
    /// as the iPad's `askAdmin(raise:pack:reason:)` (AppModel.swift:3581-3593).
    func askAdmin(raise: Bool, pack: KIFFUsage.Store.Pack? = nil, reason: String) async -> Bool {
        planMessage = nil
        guard let account else { return false }
        do {
            _ = try await account.askAdmin(raise: raise, pack: raise ? nil : pack?.id,
                                           reason: reason.trimmingCharacters(in: .whitespacesAndNewlines))
            await load()
            return true
        } catch {
            planMessage = Words.app("billing.request.not_sent", ["why": Self.plainWhy(error)])
            return false
        }
    }

    /// Takes back this person's request, as the iPad's `withdrawRequest` (AppModel.swift:3596-3605).
    func withdrawRequest(_ request: PackRequest) async {
        planMessage = nil
        guard let account else { return }
        do {
            _ = try await account.withdrawRequest(request.id)
        } catch {
            planMessage = Words.app("billing.request.not_withdrawn", ["why": Self.plainWhy(error)])
        }
        await load()
    }

    /// Starts a decline that sign-out can stop (`cancelAnswers`); `done` hears whether it went.
    func startDecline(_ request: PackRequest, note: String, done: @escaping (Bool) -> Void) {
        guard declining == nil else { return }
        declining = Task { [weak self] in
            let went = await self?.declineRequest(request, note: note) ?? false
            self?.declining = nil
            if !Task.isCancelled { done(went) }
        }
    }

    /// Stops the decline on its way: the session is ending, as the iPad's `accountGeneration`.
    func cancelAnswers() {
        declining?.cancel()
        declining = nil
    }

    /// Declines a member's request, with a note, as the iPad's `declineRequest`
    /// (AppModel.swift:3672-3696): the admin's answer, confirmed with Touch ID or the Mac's
    /// password, then signed by the device key. A prompt closed or failed sends nothing and says
    /// nothing, as the iPad's. A decline whose session ended while the prompt was up sends
    /// nothing, and one that ended while it went says nothing (`gen == accountGeneration`,
    /// :3681 and :3689).
    func declineRequest(_ request: PackRequest, note: String) async -> Bool {
        planMessage = nil
        guard let account else { return false }
        guard account.sign != nil else {
            planMessage = Words.app("sign_in.again_to_sign")
            return false
        }
        do { try await confirm(Words.app("billing.request.decline_prompt")) } catch { return false }
        guard !Task.isCancelled else { return false }
        do {
            _ = try await account.declineRequest(request.id, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            guard !Task.isCancelled else { return false }
            planMessage = Words.app("billing.request.not_declined", ["why": Self.plainWhy(error)])
            await load()
            return false
        }
        guard !Task.isCancelled else { return false }
        await load()
        return true
    }

    /// Why KIFF didn't take a request or a read, in the app's plain words, never KIFF's code, as
    /// the iPad's `KIFFError.errorDescription` (KIFFClient.swift:34-36) and `PlainError.words`:
    /// a 401 is signed out; any other refusal is its status's line (`StepRefusal.plainKey`).
    static func plainWhy(_ error: Error) -> String {
        switch error {
        case KIFFError.refused(401, _): return Words.app("error.signed_out")
        case KIFFError.refused(let status, _): return Words.app(StepRefusal.plainKey(status: status))
        case KIFFError.unreadable: return Words.app("error.ours")
        default: return error.localizedDescription
        }
    }

    func show(previous: Bool) async {
        guard previous != self.previous else { return }
        self.previous = previous
        credits = .loading
        await loadCredits()
    }

    private func loadCredits() async {
        asked += 1
        let mine = asked
        do {
            let read = try await cloud.credits(previous: previous)
            if mine == asked { credits = .loaded(read) }
        } catch {
            if mine == asked { credits = .unread(why: NeedsYouModel.why(error)) }
        }
    }
}

/// Plan & usage: the balance and the period's credits, in tafs cloud's words, then members'
/// requests to the account's admins, as the iPad's. Nothing is bought from this screen.
struct UsageView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: UsageModel
    /// Whether this person manages billing (KIFF's `billing.manage`): they answer members'
    /// requests; anyone else asks an admin.
    var managesBilling = true
    @State private var asking = false
    @State private var declining: PackRequest?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // The screen's name sits small and centred at the top, as on the iPad.
                Text(words("usage.title")).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.ink)
                    .frame(maxWidth: .infinity).padding(.top, 18).padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
                panel(stroke: balanceStroke) { balance }
                // Why the last request didn't go, as the iPad's `planMessage` panel.
                if let message = model.planMessage {
                    panel { Text(verbatim: message).font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true) }
                }
                if let u = model.usage {
                    askPanel(u)
                    requestsPanel(u)
                }
                panel {
                    Eyebrow(text: words("usage.credits"))
                    periods
                    creditsTotal
                }
                creditsRows
                // KIFF's read failed: requests wait on it, said once.
                if model.usage == nil, let why = model.usageError {
                    panel { Text(verbatim: why).font(.system(size: 14)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true) }
                }
            }
            .padding(.horizontal, Look.inset)
            .padding(.bottom, Look.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task { await model.load() }
        .sheet(isPresented: $asking) {
            AskAdminView(model: model, raise: model.usage.flatMap(Self.asks)).environment(\.words, words)
        }
        .sheet(item: $declining) { DeclineRequestView(model: model, request: $0).environment(\.words, words) }
    }

    /// For someone who doesn't manage billing, on a plan where they can ask, as the iPad's
    /// `askPanel` (UsageView.swift:57-80): their request waiting, with Withdraw; else the last
    /// answer, and Ask an admin.
    @ViewBuilder private func askPanel(_ u: KIFFUsage) -> some View {
        if !managesBilling {
            if let mine = Self.waiting(u, managesBilling: false) {
                panel {
                    Eyebrow(text: words("usage.requests.waiting"))
                    Text(words("usage.admin_answers", ["detail": Self.askedLine(mine, words: words)])).font(.system(size: 15)).foregroundColor(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(words("usage.requests.withdraw")) { Task { await model.withdrawRequest(mine) } }.buttonStyle(OutlineButtonStyle())
                }
            } else {
                if let answer = Self.lastAnswer(u, managesBilling: false, words: words) {
                    panel { Text(verbatim: answer).font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true) }
                }
                if Self.asks(u) != nil {
                    if balanceWaiting {
                        Button(words("usage.requests.ask_admin")) { asking = true }.buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button(words("usage.requests.ask_admin")) { asking = true }.buttonStyle(OutlineButtonStyle())
                    }
                }
            }
        }
    }

    /// Members' requests waiting for an answer, for someone who manages billing, as the iPad's
    /// `requestsPanel` (UsageView.swift:83-117): each one's line and reason, with Decline. A raise
    /// is answered on the iPad by raising the limit and a pack by buying it: both are signed with
    /// the approval key or bought in the App Store, so neither is on this Mac yet.
    @ViewBuilder private func requestsPanel(_ u: KIFFUsage) -> some View {
        let open = Self.openRequests(u, managesBilling: managesBilling)
        if !open.isEmpty {
            panel(stroke: Theme.amber.opacity(0.5)) {
                Eyebrow(text: words("usage.requests.title"), color: Theme.amber)
                ForEach(open) { r in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: Self.requestLine(r, in: u, words: words)).font(.system(size: 15)).foregroundColor(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if !r.reason.isEmpty {
                            Text(verbatim: r.reason).font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
                        }
                        Button(words("usage.requests.decline")) { declining = r }.buttonStyle(OutlineButtonStyle())
                    }
                }
            }
        }
    }

    private var balanceWaiting: Bool {
        if case .loaded(let balance) = model.balance { return balance.waiting }
        return false
    }

    /// A panel as the iPad's: radius 18, continuous.
    private func panel<Content: View>(stroke: Color = Theme.line, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).stroke(stroke))
    }

    /// The balance's edge, by its tone as on the iPad: red while the tafs wait, amber with a
    /// warning, else the plain line.
    private var balanceStroke: Color {
        guard case .loaded(let balance) = model.balance else { return Theme.line }
        if balance.waiting { return Theme.no.opacity(0.5) }
        if balance.warning != nil { return Theme.amber.opacity(0.5) }
        return Theme.line
    }

    @ViewBuilder private var balance: some View {
        switch model.balance {
        case .loading:
            reading
        case .unread(let why):
            Text(words("usage.balance_not_read", ["why": why])).font(.system(size: 14)).foregroundColor(Theme.no)
        case .loaded(let balance):
            Text(verbatim: balance.words).font(.system(size: 17, weight: .semibold)).foregroundColor(balance.waiting ? Theme.no : Theme.ink)
            if let meter = balance.meter {
                Meter(fraction: Double(meter) / 100, color: balance.state == "ok" ? Theme.ok : Theme.amber)
                    .accessibilityElement()
                    .accessibilityLabel(words("usage.label"))
                    .accessibilityValue(words.number(meter) + " %")
            }
            if let detail = balance.detail { Text(verbatim: detail).font(.system(size: 14)).foregroundColor(Theme.soft) }
            if let warning = balance.warning {
                // Its colour is its tone: red while the tafs wait, else amber.
                Text(verbatim: warning).font(.system(size: 14, weight: .semibold)).foregroundColor(balance.waiting ? Theme.no : Theme.amberText)
            }
            if let plan = balance.planLine { Text(verbatim: plan).font(.system(size: 13)).foregroundColor(Theme.soft) }
        }
    }

    /// Last period and This period, as the iPad's two-part switch.
    private var periods: some View {
        HStack(spacing: 0) {
            period(words("usage.last_period"), previous: true)
            period(words("usage.this_period"), previous: false)
        }
        .padding(2)
        .background(Capsule().fill(Theme.raised))
    }

    private func period(_ title: String, previous: Bool) -> some View {
        let selected = model.previous == previous
        return Button { Task { await model.show(previous: previous) } } label: {
            Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular)).foregroundColor(Theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(Capsule().fill(selected ? Theme.panel : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var creditsTotal: some View {
        switch model.credits {
        case .loading:
            reading
        case .unread(let why):
            Text(words("usage.credits_not_read", ["why": why])).font(.system(size: 14)).foregroundColor(Theme.no)
        case .loaded(let credits):
            Text(verbatim: credits.words).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.ink)
        }
    }

    /// Each taf's line as its own panel, then Coach's use past what's included in a panel of its
    /// own (it is counted), then what wasn't counted, then tafs cloud's note.
    @ViewBuilder private var creditsRows: some View {
        if case .loaded(let credits) = model.credits {
            ForEach(credits.rows) { row in
                panel {
                    Text(verbatim: row.words).font(.system(size: 15)).foregroundColor(Theme.ink)
                    if let pace = row.pace { Text(verbatim: pace).font(.system(size: 12)).foregroundColor(Theme.soft) }
                }
            }
            if let coach = credits.coach {
                panel { Text(verbatim: coach).font(.system(size: 15)).foregroundColor(Theme.ink) }
            }
            if credits.notCounted != nil || !credits.notCountedLines.isEmpty {
                panel {
                    if let not = credits.notCounted { Text(verbatim: not).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink) }
                    ForEach(Array(credits.notCountedLines.enumerated()), id: \.offset) { _, line in Text(verbatim: line).font(.system(size: 14)).foregroundColor(Theme.soft) }
                }
            }
            if let note = credits.note { Text(verbatim: note).font(.system(size: 13)).foregroundColor(Theme.soft).padding(.leading, 4) }
        }
    }

    private var reading: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(words("usage.reading")).font(.system(size: 14)).foregroundColor(Theme.soft)
        }
    }
}

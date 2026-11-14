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
        case KIFFError.refused(_, let code) where !code.isEmpty: return code
        case KIFFError.refused(let status, _): return String(status)
        case let error as KIFFError: return String(describing: error)
        default: return error.localizedDescription
        }
    }
}

/// Needs you: each held call in KIFF's words and the taf's, with its answers.
struct NeedsYouView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: NeedsYouModel
    var now = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(words("needs_you.title")).font(Theme.display(28)).foregroundColor(Theme.ink)
                switch model.state {
                case .loading:
                    ProgressView().controlSize(.small)
                case .unread(let why):
                    Text(words("needs_you.request_not_read", ["why": why])).font(.system(size: 14)).foregroundColor(Theme.no)
                case .loaded(let calls) where calls.isEmpty:
                    Text(words("needs_you.nothing")).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink)
                    Text(words("needs_you.empty_hint")).font(.system(size: 14)).foregroundColor(Theme.dim)
                case .loaded(let calls):
                    Text(words.count("needs_you.count", calls.count)).font(.system(size: 14)).foregroundColor(Theme.dim)
                    ForEach(calls) { card($0) }
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task { await model.load() }
    }

    private func card(_ call: HeldCall) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(call.title ?? call.action).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.ink)
                Spacer()
                if let left = timeLeft(call) { Text(left).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.amberText) }
            }
            if let reason = call.reasonText { Text(reason).font(.system(size: 14)).foregroundColor(Theme.soft) }
            if call.tafAbout != nil || call.tafReason != nil {
                // The taf's own words, drawn plain and apart from KIFF's.
                VStack(alignment: .leading, spacing: 3) {
                    Text(words("needs_you.taf_says")).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.dim)
                    if let about = call.tafAbout { Text(verbatim: about).font(.system(size: 14)).foregroundColor(Theme.ink) }
                    if let reason = call.tafReason { Text(verbatim: reason).font(.system(size: 14)).foregroundColor(Theme.ink) }
                }
            }
            Text(words("needs_you.nothing_sent")).font(.system(size: 13)).foregroundColor(Theme.dim)
            if model.route == .phoneOrPasskey {
                Text(words("approval.device_can_not_approve_approve")).font(.system(size: 13)).foregroundColor(Theme.soft)
            }
            HStack(spacing: 10) {
                Button(words("needs_you.refuse")) { Task { await model.refuse(call) } }
                    .buttonStyle(.plain).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.no)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .overlay(Capsule().stroke(Theme.no))
                    .disabled(model.answering != nil)
                if model.answering == call.id { ProgressView().controlSize(.small) }
            }
            if let why = model.notTaken[call.id] {
                Text(words("needs_you.refused.other", ["why": why])).font(.system(size: 13)).foregroundColor(Theme.no)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        .accessibilityElement(children: .contain)
    }

    /// "12 min left", in the app's language; "expired" once its time has passed.
    private func timeLeft(_ call: HeldCall) -> String? {
        guard let expires = call.expiresAt else { return nil }
        guard expires > now else { return words("needs_you.expired") }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = [.day, .hour, .minute]
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: words.language)
        formatter.calendar = calendar
        guard let time = formatter.string(from: max(60, expires.timeIntervalSince(now))) else { return nil }
        return words("needs_you.left", ["time": time])
    }
}

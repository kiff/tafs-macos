import SwiftUI

/// The window of a signed-in Mac: the sidebar, with each built screen in its place.
struct SignedInView: View {
    @Environment(\.words) private var words
    @StateObject private var needsYou: NeedsYouModel
    @StateObject private var devices: DevicesModel
    @StateObject private var accountModel: AccountModel
    @StateObject private var record: RecordModel
    @StateObject private var overview: OverviewModel
    @StateObject private var calendar: CalendarModel
    @StateObject private var usage: UsageModel
    @StateObject private var connect: ConnectAppsModel
    @StateObject private var coach: CoachModel
    @State private var selection: Screen = .overview
    @State private var announced = Announced()
    private let notifier = Notifier()
    private let account: AccountClient
    private let signedOut: () -> Void
    private let addThisMac: () -> Void
    private let route: ApprovalRoute
    /// How often the calls waiting are read again while the window is open.
    static let refreshEvery: TimeInterval = 30

    init(account: AccountClient, cloud: CloudClient, route: ApprovalRoute, streamer: LineStream? = nil, signedOut: @escaping () -> Void,
         addThisMac: @escaping () -> Void = {}) {
        self.account = account
        self.signedOut = signedOut
        self.addThisMac = addThisMac
        self.route = route
        _needsYou = StateObject(wrappedValue: NeedsYouModel(account: account, route: route))
        _devices = StateObject(wrappedValue: DevicesModel(account: account))
        _accountModel = StateObject(wrappedValue: AccountModel(account: account, cloud: cloud))
        _record = StateObject(wrappedValue: RecordModel(cloud: cloud))
        _overview = StateObject(wrappedValue: OverviewModel(cloud: cloud))
        _calendar = StateObject(wrappedValue: CalendarModel(cloud: cloud))
        _usage = StateObject(wrappedValue: UsageModel(cloud: cloud))
        _connect = StateObject(wrappedValue: ConnectAppsModel(cloud: cloud))
        _coach = StateObject(wrappedValue: CoachModel(cloud: cloud, streamer: streamer))
    }

    var body: some View {
        ShellView(selection: $selection, needsYou: needsYou.count, tafs: overview.tafs, noTafsLine: overview.hasNoTafs ? overview.noTafsLine : nil,
                  held: heldRows, accountLine: accountModel.me?.email ?? accountModel.me?.account) { screen in
            switch screen {
            case .needsYou: return AnyView(NeedsYouView(model: needsYou, tafs: overview.tafs))
            case .overview: return AnyView(OverviewView(model: overview))
            case .record: return AnyView(RecordView(model: record))
            case .calendar: return AnyView(CalendarView(model: calendar))
            case .usage: return AnyView(UsageView(model: usage))
            case .connectApps: return AnyView(ConnectAppsView(model: connect))
            case .coach: return AnyView(CoachView(model: coach, canApprove: false, openTaf: { _ in selection = .overview }))
            case .account: return AnyView(accountScreen)
            }
        }
        .onAppear { notifier.opened = { selection = .needsYou } }
        // Who is signed in is read once, whatever screen is open.
        .task { await accountModel.load() }
        .task {
            // KIFF's and tafs cloud's lists are read again while the window is open.
            while !Task.isCancelled {
                await needsYou.load()
                // The tafs, for the sidebar and the Overview: read once here, and again with each round,
                // so a taf made in Coach shows without opening the Overview.
                await overview.load()
                if case .loaded(let calls) = needsYou.state {
                    notifier.announce(announced.new(in: calls).map { Announcement($0, words: words) })
                }
                try? await Task.sleep(nanoseconds: UInt64(Self.refreshEvery * 1_000_000_000))
            }
        }
    }

    /// The calls held for the person, for the sidebar, each with its taf's name.
    private var heldRows: [HeldRow] {
        guard case .loaded(let calls) = needsYou.state else { return [] }
        return calls.map { HeldRow($0, tafs: overview.tafs) }
    }

    private var accountScreen: some View {
        AccountView(model: accountModel, devices: devices, open: { selection = $0 }, addThisMac: addThisMac, signOut: {
            Task {
                // Ended at KIFF first; this Mac forgets its session either way.
                try? await account.signOut()
                signedOut()
            }
        })
    }
}

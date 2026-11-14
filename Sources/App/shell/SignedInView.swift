import SwiftUI

/// The window of a signed-in Mac: the sidebar, with each built screen in its place.
struct SignedInView: View {
    @Environment(\.words) private var words
    @StateObject private var needsYou: NeedsYouModel
    @StateObject private var devices: DevicesModel
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
        _record = StateObject(wrappedValue: RecordModel(cloud: cloud))
        _overview = StateObject(wrappedValue: OverviewModel(cloud: cloud))
        _calendar = StateObject(wrappedValue: CalendarModel(cloud: cloud))
        _usage = StateObject(wrappedValue: UsageModel(cloud: cloud))
        _connect = StateObject(wrappedValue: ConnectAppsModel(cloud: cloud))
        _coach = StateObject(wrappedValue: CoachModel(cloud: cloud, streamer: streamer))
    }

    var body: some View {
        ShellView(selection: $selection, needsYou: needsYou.count) { screen in
            switch screen {
            case .needsYou: return AnyView(NeedsYouView(model: needsYou))
            case .overview: return AnyView(OverviewView(model: overview))
            case .record: return AnyView(RecordView(model: record))
            case .calendar: return AnyView(CalendarView(model: calendar))
            case .usage: return AnyView(UsageView(model: usage))
            case .connectApps: return AnyView(ConnectAppsView(model: connect))
            case .coach: return AnyView(CoachView(model: coach))
            case .account: return AnyView(accountScreen)
            }
        }
        .onAppear { notifier.opened = { selection = .needsYou } }
        .task {
            // KIFF's list is read again while the window is open, so a new call shows by itself.
            while !Task.isCancelled {
                await needsYou.load()
                if case .loaded(let calls) = needsYou.state {
                    notifier.announce(announced.new(in: calls).map { Announcement($0, words: words) })
                }
                try? await Task.sleep(nanoseconds: UInt64(Self.refreshEvery * 1_000_000_000))
            }
        }
    }

    private var accountScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            DevicesView(model: devices)
            if route == .phoneOrPasskey {
                // A Mac that can't approve: how to add it with a phone that can.
                VStack(alignment: .leading, spacing: 6) {
                    Text(words("pair.view_only.title")).font(.system(size: 12, weight: .bold)).foregroundColor(Theme.dim)
                    Text(words("pair.view_only.lead", ["device": words("device.mac")])).font(.system(size: 13)).foregroundColor(Theme.soft)
                    Button(words("pair.view_only.add", ["device": words("device.mac")])) { addThisMac() }
                        .buttonStyle(.plain).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.coach)
                }
                .padding(.horizontal, 28).padding(.bottom, 8)
                .frame(maxWidth: 720, alignment: .leading)
            }
            Button(words("settings.devices.sign_out")) {
                Task {
                    // Ended at KIFF first; this Mac forgets its session either way.
                    try? await account.signOut()
                    signedOut()
                }
            }
            .buttonStyle(.plain).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.no)
            .padding(28)
        }
        .background(Theme.background)
    }
}

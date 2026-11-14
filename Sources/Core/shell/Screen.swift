import Foundation

/// The app's screens, each an item of the sidebar, in the iPad app's order.
enum Screen: String, CaseIterable, Identifiable {
    case overview, needsYou, record, calendar, usage, connectApps, coach, account

    var id: String { rawValue }

    /// The shared key of the screen's name.
    var titleKey: String {
        switch self {
        case .overview: return "home.overview.title"
        case .needsYou: return "needs_you.title"
        case .record: return "record.title"
        case .calendar: return "calendar.heading"
        case .usage: return "usage.title"
        case .connectApps: return "connect.apps.title"
        case .coach: return "coach.title"
        case .account: return "settings.title"
        }
    }

    /// The system symbol beside its name, the iPad app's.
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .needsYou: return "bell"
        case .record: return "list.bullet"
        case .calendar: return "calendar"
        case .usage: return "chart.bar"
        case .connectApps: return "app.connected.to.app.below.fill"
        case .coach: return "bubble.left.and.bubble.right"
        case .account: return "person.crop.circle"
        }
    }

    /// The items under the app's name. The name itself opens the Overview.
    static let list: [Screen] = [.needsYou, .record, .calendar, .usage, .connectApps]
    /// The items at the sidebar's foot.
    static let foot: [Screen] = [.coach, .account]
}

import Foundation

/// Alerts on this Mac, as the iPad's Account › Alerts keeps them. Whether a call that needs
/// the person is announced is kept per account, as the iPad's `alertsEnabledKey`
/// (`alerts.enabled|{tenant}`): off until the person turns it on, and a different account never
/// inherits it. Sound is this Mac's, on until turned off, as the iPad's `alertSound`.
struct AlertPrefs: Equatable {
    static func onKey(_ account: String) -> String { "tafs.alerts.on|\(account)" }
    static let soundKey = "tafs.alerts.sound"

    var on: Bool
    var sound: Bool

    init(on: Bool = false, sound: Bool = true) {
        self.on = on
        self.sound = sound
    }

    init(defaults: UserDefaults, account: String) {
        on = defaults.object(forKey: Self.onKey(account)) as? Bool ?? false
        sound = defaults.object(forKey: Self.soundKey) as? Bool ?? true
    }

    func save(to defaults: UserDefaults, account: String) {
        defaults.set(on, forKey: Self.onKey(account))
        defaults.set(sound, forKey: Self.soundKey)
    }

    /// No alerts, no sound: off while alerts are off, its choice kept for when they're back.
    var plays: Bool { on && sound }
}

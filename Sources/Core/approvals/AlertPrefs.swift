import Foundation

/// Alerts on this Mac, as the iPad's Account › Alerts keeps them: whether a call that needs
/// the person is announced, and whether with sound. Both on until the person turns them off;
/// kept for the next launch.
struct AlertPrefs: Equatable {
    static let onKey = "tafs.alerts.on"
    static let soundKey = "tafs.alerts.sound"

    var on: Bool
    var sound: Bool

    init(on: Bool = true, sound: Bool = true) {
        self.on = on
        self.sound = sound
    }

    init(defaults: UserDefaults) {
        on = defaults.object(forKey: Self.onKey) as? Bool ?? true
        sound = defaults.object(forKey: Self.soundKey) as? Bool ?? true
    }

    func save(to defaults: UserDefaults) {
        defaults.set(on, forKey: Self.onKey)
        defaults.set(sound, forKey: Self.soundKey)
    }

    /// No alerts, no sound: off while alerts are off, its choice kept for when they're back.
    var plays: Bool { on && sound }
}

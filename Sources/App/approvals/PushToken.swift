import AppKit

/// This Mac's push token from Apple's push service, for alerts with tafs closed (`MacPush`). Only a build made with
/// `PUSH=1` asks for one (`built`): the signed app then carries `aps-environment` and its Developer ID profile. Any other
/// build never registers, and has no token.
@MainActor
final class PushToken {
    static let shared = PushToken()

    /// Whether this build asks for alerts with tafs closed (`scripts/build.sh`, `PUSH=1`). It holds no state, so it's
    /// read from anywhere: `Notifier` isn't on the main actor.
    nonisolated static var built: Bool {
        #if PUSH
        return true
        #else
        return false
        #endif
    }

    /// A held call changed elsewhere, as tafs cloud's silent push says: what needs the person is read again.
    var heldChanged: () -> Void = {}

    /// The token AppKit gave, kept while the app runs: AppKit gives the same one again on each registration.
    private(set) var bytes: Data?
    private var waiting: [CheckedContinuation<Data?, Never>] = []

    /// The token, asking AppKit for it the first time; nil when this build doesn't ask, or Apple's service refused.
    func token() async -> Data? {
        guard Self.built else { return nil }
        if let bytes { return bytes }
        return await withCheckedContinuation { done in
            waiting.append(done)
            #if PUSH
            if waiting.count == 1 { NSApplication.shared.registerForRemoteNotifications() }
            #endif
        }
    }

    /// AppKit's answer: the token, or nil when registering failed.
    func received(_ token: Data?) {
        if let token { bytes = token }
        let answered = waiting
        waiting = []
        for done in answered { done.resume(returning: token) }
    }
}

#if PUSH
/// AppKit's push registration answers, passed to `PushToken`. Only in a build made with `PUSH=1`.
final class PushAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushToken.shared.received(deviceToken) }
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushToken.shared.received(nil) }
    }

    /// tafs cloud's silent push, as the iPad's: a held call answered elsewhere takes its alerts away, and Needs you is
    /// read again.
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        if let hold = userInfo["hold_id"] as? String, userInfo["answered"] as? Bool == true { Notifier.removeAlerts(forHold: hold) }
        Task { @MainActor in PushToken.shared.heldChanged() }
    }
}
#endif

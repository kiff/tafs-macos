import AppKit
import UserNotifications

/// Posts a macOS notification for a call that needs the person, and opens Needs you when
/// one is clicked. Notifications come while the app is open; a push with the app closed
/// needs a signed build.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Called on the main thread when a notification is clicked.
    var opened: () -> Void = {}
    private var asked = false

    private var center: UNUserNotificationCenter? {
        // The notification centre needs an app bundle: a bare binary has none.
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    /// Where the person's Alerts choices are kept (Account › Alerts).
    var defaults = UserDefaults.standard

    func announce(_ announcements: [Announcement]) {
        // Alerts off on this Mac: nothing is announced.
        let prefs = AlertPrefs(defaults: defaults)
        guard prefs.on, !announcements.isEmpty, let center else { return }
        center.delegate = self
        let post = {
            for announcement in announcements {
                let content = UNMutableNotificationContent()
                content.title = announcement.title
                content.body = announcement.body
                content.sound = prefs.plays ? .default : nil
                center.add(UNNotificationRequest(identifier: announcement.id, content: content, trigger: nil))
            }
        }
        guard !asked else { return post() }
        asked = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in post() }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.opened()
            done()
        }
    }

    /// Shown even with the window in front: the call may be on another screen.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done(AlertPrefs(defaults: defaults).plays ? [.banner, .sound] : [.banner])
    }
}

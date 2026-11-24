import AppKit
import UserNotifications

/// Posts a macOS notification for a call that needs the person, and opens Needs you when
/// one is clicked. Notifications come while the app is open; a push with the app closed
/// needs a signed build.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Called on the main thread when a notification is clicked.
    var opened: () -> Void = {}
    /// Called on the main thread when tafs cloud's push shows with tafs open (`PUSH=1` builds): a brief's alert or an
    /// urgent one reads the brief again (`true`), any other what needs the person.
    var pushed: (_ brief: Bool) -> Void = { _ in }

    private var center: UNUserNotificationCenter? {
        // The notification centre needs an app bundle: a bare binary has none.
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    /// Where the person's Alerts choices are kept (Account › Alerts), and whose they are.
    var defaults = UserDefaults.standard
    var account = ""

    /// Announces calls only once the person turned alerts on for this account, as the iPad
    /// alerts only after they agreed; macOS's own permission was asked then. With Sound off an
    /// alert still arrives, quietly: no sound and no banner, only Notification Center, as tafs
    /// cloud sends the iPad's (`interruption-level: passive`).
    func announce(_ announcements: [Announcement]) {
        let prefs = AlertPrefs(defaults: defaults, account: account)
        guard prefs.on, !announcements.isEmpty, let center else { return }
        center.delegate = self
        for announcement in announcements {
            let content = UNMutableNotificationContent()
            content.title = announcement.title
            content.body = announcement.body
            content.sound = prefs.plays ? .default : nil
            content.interruptionLevel = Self.interruption(plays: prefs.plays)
            center.add(UNNotificationRequest(identifier: announcement.id, content: content, trigger: nil))
        }
    }

    /// How an alert interrupts: as usual with Sound on, quietly with it off.
    static func interruption(plays: Bool) -> UNNotificationInterruptionLevel { plays ? .active : .passive }

    /// How an alert shows with the window in front: a banner with sound, or only in the list.
    static func presentation(plays: Bool) -> UNNotificationPresentationOptions { plays ? [.banner, .sound] : [.list] }

    /// Clicked: tafs comes to the front on Needs you. A push from tafs cloud opens where it says, as the iPad's
    /// `PushDelegate` (`MacPush.destination`): a hold, a brief's alert (`brief_kind`) and a step a taf handed over are
    /// all in Needs you here, the brief in its place; anything else only brings tafs to the front.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let request = response.notification.request
        let opensNeedsYou = Self.opensNeedsYou(remote: request.trigger is UNPushNotificationTrigger, info: request.content.userInfo)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if opensNeedsYou { self.opened() }
            done()
        }
    }

    /// Takes away the alerts shown for a held call that was answered elsewhere, as the iPad's `removeAlerts(forHold:)`.
    static func removeAlerts(forHold hold: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            let ids = delivered.filter { $0.request.content.userInfo["hold_id"] as? String == hold }.map(\.request.identifier)
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    /// Hears clicks from the start, in a `PUSH=1` build: a push clicked with tafs closed launches it and arrives here.
    func listen() {
        guard PushToken.built else { return }
        center?.delegate = self
    }

    /// Whether a clicked alert opens Needs you: this app's own always; tafs cloud's when it points there.
    static func opensNeedsYou(remote: Bool, info: [AnyHashable: Any]) -> Bool {
        guard remote else { return true }
        switch MacPush.destination(info) {
        case .needsYou?, .step?: return true
        case .other?, nil: return false
        }
    }

    /// Shown even with the window in front: the call may be on another screen.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done(Self.presentation(plays: AlertPrefs(defaults: defaults, account: account).plays))
        let request = notification.request
        guard request.trigger is UNPushNotificationTrigger else { return }
        let brief = MacPush.isBrief(request.content.userInfo)
        DispatchQueue.main.async { self.pushed(brief) }
    }
}

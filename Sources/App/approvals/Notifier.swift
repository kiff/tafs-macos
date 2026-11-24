import AppKit
import UserNotifications

/// Posts a macOS notification for a call that needs the person, and opens Needs you when
/// one is clicked. Notifications come while the app is open; a push with the app closed
/// needs a signed build.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Called on the main thread when a notification is clicked.
    var opened: () -> Void = {}

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
        for announcement in announcements { center.add(Self.request(announcement, plays: prefs.plays)) }
    }

    /// Whether this window shows the sample: its alerts play and show their banner as the iPad's sample's do.
    var sample = false

    /// macOS's answer for the sample's alerts, this run: nil until it's asked, then the alerts that came while it asked wait
    /// in `waiting` and go together with its yes.
    private var sampleAllowed: Bool?
    private var askingForSample = false
    private var waiting: [UNNotificationRequest] = []

    /// The sample's held calls, as the iPad's sample alerts for them (`LockScreen.notifyNew`): not behind Account ›
    /// Alerts, whose Turn on takes KIFF, which the sample has none of. macOS is asked once, at the sample's first alert, as
    /// the iPad asks at its first, and its answer decides. Each plays, as the iPad's sample's do (`content.sound = .default`):
    /// Account › Alerts' Sound can't be set without alerts on, which the sample never is.
    func announceSample(_ announcements: [Announcement]) {
        guard !announcements.isEmpty, let center else { return }
        center.delegate = self
        let requests = announcements.map { Self.request($0, plays: true) }
        if let allowed = sampleAllowed {
            if allowed { requests.forEach { center.add($0) } }
            return
        }
        // While macOS asks, a second play's alerts wait for the same answer rather than being lost.
        waiting += requests
        guard !askingForSample else { return }
        askingForSample = true
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                self.sampleAllowed = granted
                self.askingForSample = false
                if granted { self.waiting.forEach { center.add($0) } }
                self.waiting = []
            }
        }
    }

    /// One call's alert: its words, with a sound and as an interruption only with Sound on.
    static func request(_ announcement: Announcement, plays: Bool) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = announcement.title
        content.body = announcement.body
        content.sound = plays ? .default : nil
        content.interruptionLevel = interruption(plays: plays)
        return UNNotificationRequest(identifier: announcement.id, content: content, trigger: nil)
    }

    /// How an alert interrupts: as usual with Sound on, quietly with it off.
    static func interruption(plays: Bool) -> UNNotificationInterruptionLevel { plays ? .active : .passive }

    /// How an alert shows with the window in front: a banner with sound, or only in the list.
    static func presentation(plays: Bool) -> UNNotificationPresentationOptions { plays ? [.banner, .sound] : [.list] }

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
        done(presentationNow())
    }

    /// How an alert shows with the window in front now. The sample's always show their banner, with sound, as the iPad's
    /// sample's do: Play the next sample actions is a click in tafs, so tafs is in front each time one comes.
    func presentationNow() -> UNNotificationPresentationOptions {
        Self.presentation(plays: sample || AlertPrefs(defaults: defaults, account: account).plays)
    }
}

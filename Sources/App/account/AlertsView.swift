import SwiftUI
import UserNotifications

/// Whether macOS lets tafs alert, and asking it: the system's own question, as the iPad's
/// `askNotificationPermission`. Tests answer with their own.
protocol AlertPermission {
    func allowed() async -> Bool
    func ask() async -> Bool
}

/// macOS's notification permission. A bare binary has no bundle, so it has no notifications.
struct SystemAlertPermission: AlertPermission {
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func allowed() async -> Bool {
        guard let center else { return false }
        return await withCheckedContinuation { done in
            center.getNotificationSettings { settings in
                done.resume(returning: settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            }
        }
    }

    func ask() async -> Bool {
        guard let center else { return false }
        return await withCheckedContinuation { done in
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in done.resume(returning: granted) }
        }
    }
}

/// Alerts with tafs closed (`MacPush`): this Mac's token, and tafs cloud's routes for it. Only a build made with
/// `PUSH=1` has one (`mac`); otherwise it's nil and nothing is sent.
struct PushSync {
    let token: () async -> String?
    let register: (String, Bool) async throws -> Void
    let unregister: (String) async throws -> Void

    /// The Mac's own, with the signed-in account's tafs cloud; nil in a build that doesn't ask for push.
    @MainActor static func mac(cloud: CloudClient) -> PushSync? {
        guard PushToken.built else { return nil }
        return PushSync(token: { await PushToken.shared.token().map(MacPush.token) },
                        register: { token, sound in _ = try await cloud.registerPush(token: token, sound: sound) },
                        unregister: { try await cloud.unregisterPush(token: $0) })
    }
}

/// Alerts on this Mac, for the signed-in account, as the iPad's `turnOnAlerts`/`turnOffAlerts`
/// and `alertSound` keep them: on only once the person turned them on and macOS allowed it.
@MainActor
final class AlertsModel: ObservableObject {
    @Published private(set) var prefs: AlertPrefs
    /// Whether macOS lets tafs alert; nil until it's been asked.
    @Published private(set) var allowed: Bool?
    @Published private(set) var turningOn = false
    /// Why alerts didn't turn on, in the shared words.
    @Published private(set) var why: String?

    private let defaults: UserDefaults
    private let account: String
    private let permission: AlertPermission

    /// The sample is open: alerts stay off, macOS isn't asked, and nothing is kept (`Sample`).
    private let inSample: Bool
    /// Alerts with tafs closed, in a build made with `PUSH=1`: nil otherwise, and in the sample.
    private let push: PushSync?

    init(account: String, defaults: UserDefaults = .standard, permission: AlertPermission = SystemAlertPermission(), inSample: Bool = false,
         push: PushSync? = nil) {
        self.account = account
        self.defaults = defaults
        self.permission = permission
        self.inSample = inSample
        self.push = inSample ? nil : push
        prefs = inSample ? AlertPrefs() : AlertPrefs(defaults: defaults, account: account)
    }

    /// "Alerts on this Mac": the person's choice, and macOS letting tafs alert.
    var on: Bool { prefs.on && allowed == true }

    /// Reads whether macOS still lets tafs alert: turned off in System Preferences, it reads off.
    func refresh() async { allowed = await permission.allowed() }

    /// Asks macOS first, as the iPad asks iOS; refused, it says to allow notifications and
    /// stays off (`AppModel.swift:1648-1651`).
    func turnOn(words: Words) async {
        // In the sample nothing alerts and nothing is kept: macOS isn't asked, and the line says it takes KIFF.
        guard !inSample else {
            why = Sample.notInSample(words)
            return
        }
        guard !turningOn else { return }
        turningOn = true
        defer { turningOn = false }
        guard await permission.ask() else {
            allowed = false
            why = words("alert.allow_notifications")
            return
        }
        allowed = true
        why = nil
        prefs.on = true
        if !inSample { prefs.save(to: defaults, account: account) }
        await syncPush()
    }

    func turnOff() {
        prefs.on = false
        if !inSample { prefs.save(to: defaults, account: account) }
        Task { await syncPush() }
    }

    func setSound(_ sound: Bool) {
        prefs.sound = sound
        if !inSample { prefs.save(to: defaults, account: account) }
        Task { await syncPush() }
    }

    /// Gives tafs cloud this Mac's token while alerts are on, with their sound, and takes it back when they're off
    /// (`MacPush.step`). `signingOut`: taken back whatever the switch says. Only in a build made with `PUSH=1`; a send
    /// that fails is tried again at the next change or launch.
    func syncPush(signingOut: Bool = false) async {
        guard let push else { return }
        if !signingOut { allowed = await permission.allowed() }
        let held = MacPush.Registered.load(from: defaults, account: account)
        let wanted = on && !signingOut
        let token = wanted ? await push.token() : nil
        switch MacPush.step(wanted: wanted, token: token, sound: prefs.sound, held: held) {
        case .none:
            return
        case .register(let token, let sound):
            guard (try? await push.register(token, sound)) != nil else { return }
            MacPush.Registered.save(MacPush.Registered(token: token, sound: sound), to: defaults, account: account)
        case .unregister(let token):
            guard (try? await push.unregister(token)) != nil else { return }
            MacPush.Registered.save(nil, to: defaults, account: account)
        }
    }
}

/// Account › Alerts, ported from the iPad's `NotificationSettingsView`: what an alert looks
/// like, then alerts on this Mac and their sound. On the Mac an alert comes while tafs is open
/// (`Notifier`): a push with the app closed needs a signed build, so nothing here says it does.
/// What alerts the account's phones is kept per phone by tafs cloud, so it isn't listed here.
/// It's drawn only inside a signed-in account's Account screen, as the iPad's `mode == .kiff`.
struct AlertsView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: AlertsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(words("settings.alerts")).font(.system(size: 34, weight: .bold)).foregroundColor(Theme.ink)
                // What an alert looks like: a loud one and a silent one, in the shared words.
                VStack(spacing: 10) {
                    sample(words("settings.chargebacks_needs_you"), words("settings.dispute_over_limit"), loud: true)
                    sample(words("settings.refunds_answered_maria"), words("alert.by_email"), loud: false)
                }
                // Each switch at its row's end, as the iPad's list toggles.
                VStack(alignment: .leading, spacing: 0) {
                    EndSwitch(isOn: Binding(
                        get: { model.on },
                        set: { enabled in if enabled { Task { await model.turnOn(words: words) } } else { model.turnOff() } })) {
                        Text(words("alert.on_this_device", ["device": words("device.mac")])).font(.system(size: 17))
                    }
                    .disabled(model.turningOn)
                    .padding(.vertical, 12)
                    if let why = model.why {
                        Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no).padding(.bottom, 10)
                    }
                    Rectangle().fill(Theme.line).frame(height: 1)
                    // No alerts, no sound: off and greyed while alerts are off, its choice kept.
                    EndSwitch(isOn: Binding(get: { model.on && model.prefs.sound }, set: { model.setSound($0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(words("alert.sound")).font(.system(size: 17))
                            Text(words("alert.sound_words")).font(.system(size: 13)).foregroundColor(Theme.dim)
                        }
                    }
                    .disabled(!model.on)
                    .padding(.vertical, 12)
                }
                .foregroundColor(Theme.ink)
                .padding(.horizontal, 18)
                .background(RoundedRectangle(cornerRadius: Look.panelRadius).fill(Theme.panel))
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task { await model.refresh() }
    }

    /// An alert as the screen shows it: the app's mark, its title and line; a loud one with
    /// sound, a silent one without, as the iPad's `LockScreenAlert`.
    private func sample(_ title: String, _ line: String, loud: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Mascot(size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink).lineLimit(1)
                    Spacer()
                    Image(systemName: loud ? "speaker.wave.2.fill" : "bell.slash").font(.system(size: 12)).foregroundColor(Theme.dim)
                }
                Text(line).font(.system(size: 13)).foregroundColor(Theme.soft).lineLimit(2)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.raised))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(words(loud ? "alert.with_sound" : "alert.silent")): \(title). \(line)")
    }
}

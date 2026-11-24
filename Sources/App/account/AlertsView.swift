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

/// Alerts with tafs closed (`MacPush`): this Mac's token, KIFF's alert target, and tafs cloud's routes for them. Only a
/// build made with `PUSH=1` has one (`mac`); otherwise it's nil and nothing is sent.
struct PushSync {
    let token: () async -> String?
    let register: (_ token: String, _ sound: Bool, _ target: MacPush.AlertTarget?, _ kinds: [String: Bool]?) async throws -> MacPush.Status
    let unregister: (String) async throws -> Void
    let alerts: (String) async throws -> MacPush.DeviceAlerts
    /// Points KIFF's held-call alerts at tafs cloud (`AccountClient.registerAlertTarget`).
    let alertTarget: () async throws -> MacPush.AlertTarget

    /// The Mac's own, with the signed-in account's clients; nil in a build that doesn't ask for push.
    @MainActor static func mac(cloud: CloudClient, account: AccountClient) -> PushSync? {
        guard PushToken.built else { return nil }
        return PushSync(token: { await PushToken.shared.token().map(MacPush.token) },
                        register: { try await cloud.registerPush(token: $0, sound: $1, target: $2, kinds: $3) },
                        unregister: { try await cloud.unregisterPush(token: $0) },
                        alerts: { try await cloud.deviceAlerts(token: $0) },
                        alertTarget: { try await account.registerAlertTarget() })
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
    /// What alerts this Mac, as tafs cloud keeps it for its token, as the iPad's `phoneAlerts` (`PUSH=1` builds only).
    @Published private(set) var deviceAlerts: MacPush.DeviceAlerts?
    /// Why that couldn't be read or changed.
    @Published private(set) var deviceAlertsError: String?
    /// A change to it on its way.
    @Published private(set) var pushBusy = false
    /// Whether this person's role may answer held calls, as tafs cloud said at registration; nil until then.
    @Published private(set) var canAnswerHolds: Bool?

    private let defaults: UserDefaults
    private let account: String
    private let permission: AlertPermission

    /// The sample is open: alerts stay off, macOS isn't asked, and nothing is kept (`Sample`).
    private let inSample: Bool
    /// Alerts with tafs closed, in a build made with `PUSH=1`: nil otherwise, and in the sample.
    private let push: PushSync?
    /// KIFF's alert target registered but not yet taken by tafs cloud, as the iPad's `pendingHandoff`: handed over again
    /// at the next try, without registering another. Kept in memory only.
    private var pendingTarget: MacPush.AlertTarget?

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

    /// Alerts come with tafs closed: a build made with `PUSH=1`, outside the sample.
    var pushes: Bool { push != nil }

    /// Reads whether macOS still lets tafs alert: turned off in System Preferences, it reads off.
    func refresh() async { allowed = await permission.allowed() }

    /// Asks macOS first, as the iPad asks iOS; refused, it says to allow notifications and
    /// stays off (`AppModel.swift:1648-1651`). In a `PUSH=1` build it then turns on alerts with tafs closed, as the
    /// iPad's `turnOnAlerts`: this Mac's token, KIFF's alert target pointed at tafs cloud, and both handed to tafs cloud.
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
        if let push {
            guard let failed = await turnOnPush(push, words: words) else { return keepOn() }
            why = failed
            return
        }
        keepOn()
    }

    private func keepOn() {
        prefs.on = true
        if !inSample { prefs.save(to: defaults, account: account) }
    }

    /// The token, KIFF's target and tafs cloud's registration; why not, in the iPad's words, when one fails.
    private func turnOnPush(_ push: PushSync, words: Words) async -> String? {
        guard let token = await push.token() else { return words("alert.no_push_token_device", ["device": words("device.mac")]) }
        if pendingTarget == nil {
            do {
                pendingTarget = try await push.alertTarget()
            } catch KIFFError.refused(403, let code) {
                return code.contains("phone_alert_url_forbidden") ? words("alert.kiff_doesnt_send") : words("alert.role_cant")
            } catch {
                return words("alert.not_on", ["why": NeedsYouModel.why(error)])
            }
        }
        do {
            let status = try await push.register(token, prefs.sound, pendingTarget, savedKinds)
            pendingTarget = nil
            canAnswerHolds = status.answers
            MacPush.Registered.save(MacPush.Registered(token: token, sound: prefs.sound), to: defaults, account: account)
        } catch {
            return words("alert.alerts_almost_tafs_cloud_did", ["why": NeedsYouModel.why(error)])
        }
        await loadDeviceAlerts()
        return nil
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

    /// The kinds chosen on this Mac, sent with each registration.
    private var savedKinds: [String: Bool]? { defaults.dictionary(forKey: MacPush.kindsKey(account)) as? [String: Bool] }

    /// One kind of alert on or off for this Mac, as the iPad's `setAlertKind`: registered again with the kinds.
    func setKind(_ id: String, enabled: Bool) async {
        guard let push, !pushBusy, let alerts = deviceAlerts, alerts.enabled, alerts.kinds.contains(where: { $0.id == id }),
              let token = await push.token() else { return }
        pushBusy = true
        defer { pushBusy = false }
        let kinds = alerts.kinds(setting: id, to: enabled)
        do {
            _ = try await push.register(token, prefs.sound, nil, kinds)
            defaults.set(kinds, forKey: MacPush.kindsKey(account))
            await loadDeviceAlerts()
        } catch {
            deviceAlertsError = NeedsYouModel.why(error)
        }
    }

    /// What alerts this Mac, read from tafs cloud for its token, as the iPad's `loadPhoneAlerts`.
    func loadDeviceAlerts() async {
        guard let push, let token = MacPush.Registered.load(from: defaults, account: account)?.token else {
            deviceAlerts = nil
            return
        }
        do {
            deviceAlerts = try await push.alerts(token)
            deviceAlertsError = nil
        } catch {
            deviceAlertsError = NeedsYouModel.why(error)
        }
    }

    /// Gives tafs cloud this Mac's token while alerts are on, with their sound and kinds, and takes it back when they're
    /// off (`MacPush.step`). `signingOut`: taken back whatever the switch says. Only in a build made with `PUSH=1`; a
    /// send that fails is tried again at the next change or launch.
    func syncPush(signingOut: Bool = false) async {
        guard let push else { return }
        if !signingOut { allowed = await permission.allowed() }
        let held = MacPush.Registered.load(from: defaults, account: account)
        let wanted = on && !signingOut
        let token = wanted ? await push.token() : nil
        switch MacPush.step(wanted: wanted, token: token, sound: prefs.sound, held: held) {
        case .none:
            break
        case .register(let token, let sound):
            guard let status = try? await push.register(token, sound, nil, savedKinds) else { return }
            canAnswerHolds = status.answers
            MacPush.Registered.save(MacPush.Registered(token: token, sound: sound), to: defaults, account: account)
        case .unregister(let token):
            guard (try? await push.unregister(token)) != nil else { return }
            MacPush.Registered.save(nil, to: defaults, account: account)
        }
        if !signingOut { await loadDeviceAlerts() }
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
                if model.pushes {
                    // With tafs closed too (`PUSH=1`), as the iPad's footer: who alerts go to, else what this Mac does.
                    Text(model.canAnswerHolds == false ? words("alert.foot.cant_answer_holds")
                         : words("alert.foot.tells_you_device", ["device": words("device.mac")]))
                        .font(.system(size: 13)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                    DeviceAlertsSection(model: model)
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task {
            await model.refresh()
            await model.loadDeviceAlerts()
        }
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

/// What alerts this Mac, as tafs cloud keeps it for its token, as the iPad's "What alerts you": each kind with its words
/// and switch, and the tafs whose answers alert the account's devices (`AlertingTafs`). Drawn only with something in it.
struct DeviceAlertsSection: View {
    @Environment(\.words) private var words
    @ObservedObject var model: AlertsModel

    var body: some View {
        let alerts = model.deviceAlerts
        if !(alerts?.kinds ?? []).isEmpty || alerts?.answering != nil || model.deviceAlertsError != nil {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(text: words("alert.what_alerts")).padding(.vertical, 12)
                ForEach(alerts?.kinds ?? []) { choice in
                    EndSwitch(isOn: Binding(get: { choice.enabled }, set: { on in Task { await model.setKind(choice.id, enabled: on) } })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: choice.title).font(.system(size: 17))
                            Text(verbatim: choice.words).font(.system(size: 13)).foregroundColor(Theme.dim)
                        }
                    }
                    .disabled(model.pushBusy || alerts?.enabled != true)
                    .padding(.vertical, 12)
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
                if let answering = alerts?.answering { AlertingTafs(answering: answering) }
                if let error = model.deviceAlertsError {
                    Text(verbatim: error).font(.system(size: 13)).foregroundColor(Theme.no).padding(.vertical, 10)
                }
            }
            .foregroundColor(Theme.ink)
            .padding(.horizontal, 18)
            .background(RoundedRectangle(cornerRadius: Look.panelRadius).fill(Theme.panel))
            .accessibilityIdentifier("alerts.what-alerts")
        }
    }
}

/// The tafs whose answers alert the account's devices, as the iPad's `AlertingTafsView`: who was answered and through
/// which door, never its words. Opened under its title; each taf's own Results go to changes it.
struct AlertingTafs: View {
    @Environment(\.words) private var words
    let answering: MacPush.DeviceAlerts.Answering
    @State private var open = false

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(answering.tafs) { taf in Text(verbatim: taf.name).font(.system(size: 15)).foregroundColor(Theme.ink) }
                if answering.tafs.isEmpty {
                    Text(words("settings.no_taf_alerts_phones_when")).font(.system(size: 15)).foregroundColor(Theme.dim)
                }
                Text(words("settings.each_sends_who_answered_through")).font(.system(size: 13)).foregroundColor(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } label: {
            Text(verbatim: answering.title).font(.system(size: 17))
        }
        .padding(.vertical, 12)
        .accessibilityIdentifier("alerts.alerting-tafs")
    }
}

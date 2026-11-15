import SwiftUI

/// Account › Alerts, ported from the iPad's `NotificationSettingsView`: what an alert looks
/// like, then alerts on this Mac and their sound. On the Mac an alert comes while tafs is open
/// (`Notifier`): a push with the app closed needs a signed build, so nothing here says it does.
/// What alerts the account's phones is kept per phone by tafs cloud, so it isn't listed here.
struct AlertsView: View {
    @Environment(\.words) private var words
    let defaults: UserDefaults
    @State private var prefs: AlertPrefs

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        _prefs = State(initialValue: AlertPrefs(defaults: defaults))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(words("settings.alerts")).font(.system(size: 34, weight: .bold)).foregroundColor(Theme.ink)
                // What an alert looks like: a loud one and a silent one, in the shared words.
                VStack(spacing: 10) {
                    sample(words("settings.chargebacks_needs_you"), words("settings.dispute_over_limit"), loud: true)
                    sample(words("settings.refunds_answered_maria"), words("alert.by_email"), loud: false)
                }
                VStack(spacing: 0) {
                    Toggle(words("alert.on_this_device", ["device": words("device.mac")]), isOn: Binding(get: { prefs.on }, set: { prefs.on = $0; prefs.save(to: defaults) }))
                        .font(.system(size: 17)).padding(.vertical, 12)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    // No alerts, no sound: off and greyed while alerts are off, its choice kept.
                    Toggle(isOn: Binding(get: { prefs.plays }, set: { prefs.sound = $0; prefs.save(to: defaults) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(words("alert.sound")).font(.system(size: 17))
                            Text(words("alert.sound_words")).font(.system(size: 13)).foregroundColor(Theme.dim)
                        }
                    }
                    .disabled(!prefs.on)
                    .padding(.vertical, 12)
                }
                .toggleStyle(.switch)
                .foregroundColor(Theme.ink)
                .padding(.horizontal, 18)
                .background(RoundedRectangle(cornerRadius: Look.panelRadius).fill(Theme.panel))
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
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

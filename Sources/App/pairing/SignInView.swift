import SwiftUI

/// Signing in, and adding this Mac with a phone: the first screen of a Mac with no session.
struct SignInView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: SignInModel

    private var device: String { words("device.mac") }

    var body: some View {
        VStack(spacing: 18) {
            switch model.step {
            case .welcome: welcome
            case .browser(let start): browser(start)
            case .pairing(let code): pairing(code)
            case .codeExpired:
                note(words("pair.code_expired"))
                primary(words("pair.new_code")) { await model.pair() }
                back
            case .failed(let why, let pairing):
                note(pairing ? words("pair.failed", ["device": device, "why": why]) : words("sign_in.could_not_start", ["why": why]), color: Theme.no)
                primary(words("common.try_again")) { pairing ? await model.pair() : await model.signIn() }
                back
            }
        }
        .frame(maxWidth: 440)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    @ViewBuilder private var welcome: some View {
        Mascot(size: 96)
        Text(words("sign_in.welcome.title")).font(Theme.display(40)).foregroundColor(Theme.ink)
        note(words("sign_in.welcome.lead"), color: Theme.ink, size: 17)
        note(words("sign_in.lead", ["device": device]))
        primary(words("sign_in.with_kiff")) { await model.signIn() }
        Button(words("pair.from_sign_in", ["device": device])) { Task { await model.pair() } }
            .buttonStyle(.plain).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.coach)
    }

    @ViewBuilder private func browser(_ start: DeviceStart) -> some View {
        Mascot(size: 64)
        note(words("sign_in.your_code"))
        code(start.userCode)
        note(words("sign_in.check_code"))
        waiting(words("sign_in.waiting"))
        back
    }

    @ViewBuilder private func pairing(_ shown: SignInModel.Code) -> some View {
        Text(words("pair.title", ["device": device])).font(Theme.display(24)).foregroundColor(Theme.ink)
            .multilineTextAlignment(.center)
        if let image = QRCode.image(shown.text, side: 220) {
            Image(nsImage: image).interpolation(.none).resizable().frame(width: 220, height: 220)
                .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                .accessibilityLabel(words("pair.title", ["device": device]))
        }
        note(words("pair.steps", ["account": words("settings.title"), "devices": words("settings.devices.title"), "pair": words("settings.devices.pair")]))
        note(words("pair.check_code_lead", ["device": device]), color: Theme.ink)
        code(shown.check)
        waiting(words("pair.waiting"))
        back
    }

    private func code(_ text: String) -> some View {
        Text(text).font(Theme.mono(30, weight: .bold)).foregroundColor(Theme.ink).tracking(3)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
            .textSelection(.enabled)
    }

    private func note(_ text: String, color: Color = Theme.dim, size: CGFloat = 14) -> some View {
        Text(text).font(.system(size: size)).foregroundColor(color).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func waiting(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.system(size: 14)).foregroundColor(Theme.soft)
        }
    }

    private func primary(_ title: String, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                .padding(.horizontal, 26).padding(.vertical, 12)
                .background(Capsule().fill(Theme.brand))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
    }

    private var back: some View {
        Button(words("common.cancel")) { model.cancel() }
            .buttonStyle(.plain).font(.system(size: 14)).foregroundColor(Theme.soft)
    }
}

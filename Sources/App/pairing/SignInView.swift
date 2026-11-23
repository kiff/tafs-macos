import SwiftUI

/// Signing in: the first window of a Mac with no session, in two halves of the whole window, as
/// the iPad's regular width (`SignInPlan`). On the left, **Sign in with KIFF**; on the right,
/// **Sign in with your phone**, whose QR is shown as the window opens and renewed silently when it
/// runs out. A view-only Mac adding itself sees the phone's half alone, with Cancel.
struct SignInView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: SignInModel

    private var device: String { words("device.mac") }
    private var halves: SignInPlan.Halves { SignInPlan.halves(model.phase, signedIn: model.session != nil, asksKey: model.asksKey) }

    var body: some View {
        HStack(spacing: 0) {
            if let kiff = halves.kiff {
                half { kiffHalf(kiff) }
                Divider()
            }
            half { phoneHalf(halves.phone) }.background(Theme.raised)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        // The phone's code as the window opens, and a new one each time it runs out.
        .onAppear { Task { await model.readTerms(); await model.showPhoneCode() } }
        .onChange(of: model.step) { _ in Task { await model.showPhoneCode() } }
        // A pairing asks this Mac's security key for its credential through its PIN sheet.
        .sheet(item: $model.pinSheet) { sheet in PINSheet(model: sheet).environment(\.words, words) }
    }

    /// One half: its content centred, scrolling when the window is too short for it.
    private func half<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let inner = VStack(spacing: 18) { content() }.frame(maxWidth: 400).padding(40)
        return GeometryReader { geometry in
            ScrollView {
                inner.frame(width: geometry.size.width).frame(minHeight: geometry.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Sign in with KIFF

    @ViewBuilder private func kiffHalf(_ shown: SignInPlan.KIFFHalf) -> some View {
        switch (shown, model.step) {
        case (.code, .browser(let start)):
            title(words("sign_in.with_kiff"), size: 24)
            note(words("sign_in.lead", ["device": device]))
            codePanel([.eyebrow(words("sign_in.your_code")), .code(start.userCode)])
            note(words("sign_in.check_code"), color: Theme.ink)
            waiting(words("sign_in.waiting"))
            agreement
            back
        case (.failed, .failed(let why, _)):
            firstRun
            note(words("sign_in.could_not_start", ["why": why]), color: Theme.no)
            primary(words("common.try_again")) { await model.signIn() }
        default:
            firstRun
            title(words("sign_in.with_kiff"))
            if model.onboarding {
                OnboardingConsent(model: model, region: region, ages: ages)
                if let problem = model.problem { note(problem, color: Theme.no) }
                if model.signingInApp {
                    waiting(words("sign_in.waiting"))
                } else {
                    primary(words("common.continue"), enabled: model.tick.canContinue) { await model.signInInApp(language: words.language) }
                }
            } else {
                primary(words("common.continue")) { await model.signIn() }
                if let raised = Onboarding.raisedAgeLine(region: region, ages: ages, words: words) { note(raised, size: 12) }
            }
        }
    }

    /// This Mac's region, for the age line: the country whose law sets the age.
    private var region: String? { Locale.current.regionCode }

    /// The minimum ages by country (`strings/ages.json` in the app); the standard alone when it can't be read.
    private var ages: MinimumAge {
        (Words.bundleFolder.flatMap { try? MinimumAge(folder: $0) })
            ?? (try? MinimumAge(json: Data(#"{"default":16}"#.utf8)))!
    }

    /// Board 1, first run (docs/window.md › Illustrations): a card opening, where the iPad's welcome
    /// draws it, before Sign in with KIFF.
    private var firstRun: some View { Illustration.firstRun.frame(maxWidth: .infinity) }

    /// "By signing in, you agree to KIFF's Terms … and its Privacy policy", each a link to its page
    /// in the app's language where kiff.dev has it.
    private var agreement: some View {
        func link(_ key: String, _ url: String) -> String {
            let label = words(key)
            return "[\(LegalPages.saysEnglish(words.language) ? words("settings.legal_in_english", ["label": label]) : label)](\(url))"
        }
        let line = words("sign_in.agree", ["terms": link("settings.terms", LegalPages.terms(words.language)),
                                           "privacy": link("settings.privacy_policy", LegalPages.privacy(words.language))])
        return Text((try? AttributedString(markdown: line)) ?? AttributedString(line))
            .font(.system(size: 12)).foregroundColor(Theme.dim).multilineTextAlignment(.center)
            .tint(Theme.amberText)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Sign in with your phone

    /// Whether the phone's way waits for the welcome's tick: the new onboarding, on a Mac with no session yet.
    private var waitsOnTick: Bool { model.onboarding && model.session == nil && !model.tick.canContinue }

    /// The phone's title: a view-only Mac adding itself says so.
    private var phoneTitle: String {
        model.session == nil ? words("sign_in.with_phone") : words("pair.title", ["device": device])
    }

    @ViewBuilder private func phoneHalf(_ shown: SignInPlan.PhoneHalf) -> some View {
        switch (shown, model.step) {
        case (.code, .pairing(let code)):
            pairing(code)
        case (.failed, .failed(let why, _)):
            SignInArt.phone()
            note(words("pair.failed", ["device": device, "why": why]), color: Theme.no)
            primary(words("common.try_again"), isDefault: halves.kiff == nil) { await model.pair() }
        case (.offer, _):
            SignInArt.phone()
            title(phoneTitle)
            primary(words("common.continue"), isDefault: halves.kiff == nil, enabled: waitsOnTick == false) { await model.pair() }
        case (.starting, _) where waitsOnTick:
            // The new welcome: the phone's code waits on the tick, as the iPad's "Sign in with your phone".
            SignInArt.phone()
            title(phoneTitle)
            primary(words("common.continue"), isDefault: false, enabled: false) {}
        default:
            SignInArt.phone()
            title(phoneTitle)
            ProgressView().controlSize(.small).accessibilityLabel(words("sign_in.pair_waiting"))
        }
        if model.session != nil { back }
    }

    @ViewBuilder private func pairing(_ code: SignInModel.Code) -> some View {
        HStack(spacing: 12) {
            SignInArt.phone(size: 64)
            Text(phoneTitle).font(Theme.display(24)).foregroundColor(Theme.ink).accessibilityAddTraits(.isHeader)
        }
        if let image = QRCode.image(code.text, side: 220) {
            Image(nsImage: image).interpolation(.none)
                .padding(10).background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .accessibilityLabel(phoneTitle)
        }
        Label(words("sign_in.scan_with_tafs"), systemImage: "viewfinder").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
        note(words("sign_in.pair_how", ["account": words("settings.title"), "devices": words("settings.devices.title"), "add": words("settings.devices.pair")]))
        codePanel(SignInPlan.codeLines(eyebrow: words("sign_in.your_code"), check: code.check, name: model.deviceName,
                                       waiting: words("sign_in.pair_waiting")))
    }

    // MARK: Pieces

    /// A code's panel, its lines in the order given: for a pairing, the check code first, then the
    /// name this Mac gives itself, as its own claim.
    private func codePanel(_ lines: [SignInPlan.CodeLine]) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                switch line {
                case .eyebrow(let text): Eyebrow(text: text)
                case .code(let text):
                    Text(text).font(Theme.mono(30, weight: .bold)).foregroundColor(Theme.ink).tracking(3).textSelection(.enabled)
                case .name(let name):
                    Label(name, systemImage: "laptopcomputer").font(.system(size: 13)).foregroundColor(Theme.soft)
                case .waiting(let text): waiting(text)
                }
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .frame(maxWidth: 360)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Look.panelRadius).stroke(Theme.line))
    }

    private func title(_ text: String, size: CGFloat = 28) -> some View {
        Text(text).font(Theme.display(size)).foregroundColor(Theme.ink).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
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

    /// The half's one button, filled with the brand. The KIFF half's is the window's default (Return).
    @ViewBuilder private func primary(_ title: String, isDefault: Bool = true, enabled: Bool = true,
                                      _ action: @escaping () async -> Void) -> some View {
        let button = Button { Task { await action() } } label: {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                .padding(.horizontal, 26).padding(.vertical, 12)
                .background(Capsule().fill(Theme.brand))
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        if isDefault { button.keyboardShortcut(.defaultAction) } else { button }
    }

    private var back: some View {
        Button(words("common.cancel")) { model.cancel() }
            .buttonStyle(.plain).font(.system(size: 14)).foregroundColor(Theme.soft)
            .keyboardShortcut(.cancelAction)
    }
}

import SwiftUI

/// A row whose switch is at its end, as the iPad's list toggles draw it: the label, room, then
/// the switch. macOS draws a switch's own label beside it, so the label is drawn here and the
/// switch keeps it only for VoiceOver.
struct EndSwitch<Label: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var isOn: Bool
    let label: Label

    init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {
        _isOn = isOn
        self.label = label()
    }

    var body: some View {
        HStack(spacing: 12) {
            label.opacity(isEnabled ? 1 : 0.5).accessibilityHidden(true)
            Spacer(minLength: 8)
            Toggle(isOn: $isOn) { label }
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

/// Account's Coach panel, as the iPad's (SignInView.swift:330-344): Show suggestions with tafs
/// cloud's words for what it does now, for the people who manage the account's tafs.
struct SuggestionsRow: View {
    @Environment(\.words) private var words
    @ObservedObject var model: AccountModel
    let shown: Suggestions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EndSwitch(isOn: Binding(get: { shown.show }, set: { on in Task { await model.setSuggestions(on, words: words) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(words("settings.show_suggestions")).font(.system(size: 17)).foregroundColor(Theme.ink)
                    if !shown.words.isEmpty {
                        Text(verbatim: shown.words).font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .disabled(!(model.me?.managesCards ?? true) || model.suggestionsBusy)
            .padding(.vertical, 12)
            if let why = model.suggestionsError {
                Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no).padding(.bottom, 10)
            }
        }
    }
}

/// Account's row for the AI-data consent, as the iPad's `AIConsentRow` (AIConsentView.swift:52-74):
/// tafs cloud's words for it once given, with Withdraw; not given, its title, which opens its
/// screen. Every word is tafs cloud's.
struct AIConsentRow: View {
    @Environment(\.words) private var words
    @ObservedObject var model: AccountModel
    let consent: TafsCloud.AIConsent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if consent.given {
                Text(verbatim: consent.words.given).font(.system(size: 17)).foregroundColor(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                if !consent.words.withdraw.trimmingCharacters(in: .whitespaces).isEmpty {
                    Rectangle().fill(Theme.line).frame(height: 1)
                    button(consent.words.withdraw, color: Theme.no) { Task { await model.withdrawAI(words: words) } }
                        .disabled(model.consentBusy)
                }
            } else {
                button(consent.words.title, color: Theme.amberText) { model.askConsent() }
            }
            if let why = model.consentError, model.consentAsked == nil {
                Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no).padding(.bottom, 10)
            }
        }
    }

    private func button(_ title: String, color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title).font(.system(size: 17)).foregroundColor(color)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The AI-data consent's screen, from Account's AI use row, as the iPad's `AIConsentView`
/// (AIConsentView.swift:7-49): tafs cloud's words, as sent, then Allow and Not now. Nothing is
/// sent before Allow.
struct AIConsentSheet: View {
    @Environment(\.words) private var words
    @ObservedObject var model: AccountModel
    let consent: TafsCloud.AIConsent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "sparkles").font(.system(size: 26, weight: .semibold)).foregroundColor(Theme.amberText)
                .accessibilityHidden(true)
            Text(verbatim: consent.words.title).font(Theme.display(22)).foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(consent.words.lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line).font(.system(size: 14)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
            if let why = model.consentError {
                Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(consent.words.notNow) { model.notNowAI() }
                Spacer()
                // No key allows: consent is a deliberate click.
                Button(consent.words.allow) { Task { await model.allowAI(words: words) } }
            }
            .disabled(model.consentBusy)
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: 460, alignment: .leading)
        .background(Theme.background)
    }
}

/// One of Account's grouped panels, as the iPad's list sections: a title in 17 semibold soft,
/// then its rows on a panel.
struct AccountGroup<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.soft).padding(.leading, 18).padding(.top, 14)
            } else {
                Color.clear.frame(height: 14)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Look.panelRadius).fill(Theme.panel))
        }
    }
}

/// Account's rows, as the iPad's `LabeledContent`, `NavigationLink` and buttons draw them.
enum AccountRow {
    static var divider: some View { Rectangle().fill(Theme.line).frame(height: 1) }
    static var chevron: some View { Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.soft) }

    /// A title and its value, the value soft at the end.
    static func value(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 17)).foregroundColor(Theme.ink)
            Spacer()
            Text(verbatim: value).font(.system(size: 17)).foregroundColor(Theme.soft).lineLimit(1).textSelection(.enabled)
        }
        .padding(.vertical, 12)
    }

    /// A row that opens a page: its title, its value when it has one, and the chevron.
    static func link(_ title: String, value: String? = nil, color: Color = Theme.ink, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 17)).foregroundColor(color)
                Spacer()
                if let value { Text(verbatim: value).font(.system(size: 17)).foregroundColor(Theme.soft).lineLimit(1) }
                chevron
            }
            .padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A row that acts, in its colour.
    static func action(_ title: String, color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 17)).foregroundColor(color)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A panel's footer, under it, as the iPad's section footers.
    static func footer(_ words: String) -> some View {
        Text(words).font(.system(size: 13)).foregroundColor(Theme.dim)
            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 18)
    }
}

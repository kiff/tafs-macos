import SwiftUI

/// "Allow this from now on", as the iPad's `AllowSheetView` (kiff/tafs `docs/allow-from-now-on.md`): tafs cloud's
/// change, before and after, in its words; KIFF's own lines for each Card that changes, under them; what it would have
/// done; the held call's switch; and one approval on this Mac's security key, only when KIFF's draft is what was
/// offered. A `none` says tafs cloud's words, with nothing to sign.
struct AllowSheetView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: NeedsYouModel

    var body: some View {
        if let open = model.allow {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Text(words("needs_you.allow_title")).font(Theme.display(22)).foregroundColor(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(words("common.cancel")) { model.allow = nil }.keyboardShortcut(.cancelAction)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let answer = open.read?.answer {
                            if let offer = answer.offer {
                                offered(open, offer)
                            } else {
                                // No offer, whatever its reason, one this app knows or not: tafs cloud's words, nothing to sign.
                                Text(verbatim: CallNames.visible(answer.words ?? "")).font(.system(size: 15)).foregroundColor(Theme.soft)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("allow.none")
                            }
                        } else if open.busy {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                        if let error = open.error {
                            Text(verbatim: error).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if open.matches, open.read?.answer.offer != nil {
                    Button(open.busy ? words("approval.approving") : words("approval.security_key.title")) {
                        Task { await model.confirmAllow() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(open.busy)
                    .accessibilityIdentifier("allow.confirm")
                }
            }
            .padding(20)
            .frame(width: 520, height: 560)
            .background(Theme.background)
        }
    }

    @ViewBuilder private func offered(_ open: AllowSheet, _ offer: CloudClient.AllowOffer) -> some View {
        ForEach(Array(offer.changes.enumerated()), id: \.offset) { _, change in
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: CallNames.visible(change.wordsBefore ?? "")).font(.system(size: 14)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: "→ " + CallNames.visible(change.wordsAfter ?? "")).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
        // KIFF's own lines for each Card that changes, as it keeps them: what's signed.
        if let draft = open.read?.draft {
            ForEach(Array(Self.changedLines(draft, words).enumerated()), id: \.offset) { _, line in
                Text(verbatim: line).font(.system(size: 13)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
        }
        if let would = offer.would?.words, !would.isEmpty {
            Text(verbatim: CallNames.visible(would)).font(.system(size: 14)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
        if !open.matches {
            // A draft that couldn't be read says so in the error line alone: it isn't one that differs from the offer.
            if open.read?.draft != nil || (!open.busy && open.error == nil) {
                Text(words("needs_you.allow_not_offered")).font(.system(size: 14)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("allow.not-offered")
            }
        } else {
            Toggle(isOn: Binding(get: { model.allow?.sendHeld ?? true }, set: { model.allow?.sendHeld = $0 })) {
                Text(words("needs_you.allow_send_this_too")).font(.system(size: 15)).foregroundColor(Theme.ink)
            }
            .toggleStyle(.switch)
            .disabled(open.busy)
            .accessibilityIdentifier("allow.send-held")
            if !open.sendHeld {
                Text(words("needs_you.allow_switch_off")).font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            }
            if !open.rounded, let figure = offer.round?.words, !figure.isEmpty {
                Button(words("needs_you.allow_round_up", ["amount": CallNames.visible(figure)])) { model.roundAllow() }
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(open.busy)
                    .accessibilityIdentifier("allow.round")
            }
        }
    }

    /// KIFF's lines for each Card the draft changes, not those it keeps as they are: as the iPad's
    /// `zip(draft.cards, draft.cardLines).filter { !$0.0.isUnchanged }`.
    static func changedLines(_ draft: AccountClient.Draft, _ words: Words) -> [String] {
        let cards = draft.cards ?? []
        let alike = AccountClient.Draft.alike(cards.flatMap { $0.grants ?? [] })
        return cards.filter { !$0.isUnchanged }.flatMap { AccountClient.Draft.lines(of: $0, alike: alike, words) }
    }
}

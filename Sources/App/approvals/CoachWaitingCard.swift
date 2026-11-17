import SwiftUI

/// A Coach chat waiting on its person, as the iPad's `CoachWaitingCard` (NeedsYouView.swift:484-578):
/// tafs cloud's line, its way in, which opens Coach on that chat, and Set aside where tafs cloud
/// sent its words. The iPad's swipe has a button with the same words, so a swipe isn't the only
/// way: this Mac has the button. One call per click: the row asks once, and the model sends
/// nothing for a chat already being set aside.
struct CoachWaitingCard: View {
    @ObservedObject var model: NeedsYouModel
    let waiting: CoachWaiting
    /// Its way in only for someone who may use Coach: else the line alone, never a button that
    /// does nothing.
    var mayUseCoach = false
    var open: (CoachWaiting) -> Void = { _ in }
    /// What follows a chat set aside: Coach leaves it, and the lists are read again.
    var done: (Set<String>) async -> Void = { _ in }
    /// This row asked to be set aside, and tafs cloud hasn't answered yet.
    @State private var asked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            line
            if mayUseCoach {
                Button { open(waiting) } label: { Text(verbatim: waiting.words.open) }
                    .buttonStyle(PrimaryButtonStyle())
            }
            // Set aside's words as a button, only when tafs cloud sent them.
            if waiting.canSetAside {
                Button { setAside() } label: { Text(verbatim: waiting.words.setAside) }
                    .buttonStyle(OutlineButtonStyle(color: Theme.soft))
                    .disabled(asked || model.settingAside.contains(waiting.session))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).stroke(Theme.amber.opacity(0.4)))
        .accessibilityElement(children: .contain)
    }

    /// tafs cloud's line, after Coach's sparkle in amber.
    private var line: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "sparkle").foregroundColor(Theme.amberText).accessibilityHidden(true)
            Text(verbatim: waiting.words.line).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Asks once: a click while it's on its way sends nothing more.
    @MainActor private func setAside() {
        guard !asked, !model.settingAside.contains(waiting.session) else { return }
        asked = true
        let session = waiting.session, done = self.done
        Task {
            await model.setAside(session, done: done)
            asked = false
        }
    }
}

/// "Set all aside" (`coach_waiting_clear`), above two or more waiting Coach chats, as the iPad's
/// `SetAllAsideButton` (NeedsYouView.swift:580-600): it asks once, in tafs cloud's words (the
/// title names the count it ends), then sets every one aside in one call.
struct SetAllAsideButton: View {
    @Environment(\.words) private var words
    @ObservedObject var model: NeedsYouModel
    let clear: CoachWaitingClear
    var done: (Set<String>) async -> Void = { _ in }
    @State private var confirming = false

    var body: some View {
        Button { confirming = true } label: { Text(verbatim: clear.words.button) }
            .buttonStyle(OutlineButtonStyle(color: Theme.amberText))
            .disabled(!model.settingAside.isEmpty)
            .confirmationDialog(clear.words.title, isPresented: $confirming, titleVisibility: .visible) {
                Button(clear.words.yes, role: .destructive) { setAllAside() }
                Button(clear.words.no.isEmpty ? words("common.cancel") : clear.words.no, role: .cancel) {}
            } message: {
                if !clear.words.text.isEmpty { Text(verbatim: clear.words.text) }
            }
    }

    @MainActor private func setAllAside() {
        let done = self.done
        Task { await model.setAside(nil, done: done) }
    }
}

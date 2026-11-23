import SwiftUI

/// Before a trial starts, as the iPad's `TrialStartSheet` (kiff/tafs#173): what the version changes, the Card it runs
/// under (read by this Mac from KIFF, before anything is signed), and what trying it means for the live taf. One approval
/// on the security key starts it; changed since it was read, it's read again.
struct TrialStartSheet: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafPagesModel
    let version: TafVersions.Version
    let close: () -> Void
    @State private var draft: AccountClient.Draft?
    @State private var unread: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(words("version.try_it")).font(Theme.display(22)).foregroundColor(Theme.ink)
                Spacer()
                Button(words("common.cancel"), action: close).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(verbatim: version.note.map { words("version.try_number_note", ["version": String(version.n), "note": $0]) }
                         ?? words("version.try_number", ["version": String(version.n)]))
                        .font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    whileTrying
                    if let draft, draft.cards != nil {
                        Eyebrow(text: words("card.its_card"))
                        ForEach(Array(draft.lines(words).enumerated()), id: \.offset) { _, line in
                            Text(verbatim: line).font(.system(size: 14)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        }
                    } else if let unread {
                        Text(verbatim: unread).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    if let error = model.trialError {
                        Text(verbatim: error).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Button(model.trialBusy ? words("common.starting") : words("version.start_trying")) {
                guard let shown = draft?.version else { return }
                Task {
                    if await model.startTrial(version: version.n, shownDraft: shown) { close() } else if model.trialError == words("version.trial.changed") {
                        // What KIFF holds changed: read again, so the person reads what they'd approve.
                        await read()
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(draft == nil || model.trialBusy)
        }
        .padding(20)
        .frame(width: 520, height: 560)
        .background(Theme.background)
        .task { await read() }
    }

    private var whileTrying: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: words("version.while_trying"))
            ForEach(["version.while_you_try.chat", "version.while_you_try.live_keeps_working", "version.while_you_try.counts_from_zero",
                     "version.while_you_try.ends"], id: \.self) { key in
                Text(words(key, ["n": String(version.n)])).font(.system(size: 14)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
    }

    private func read() async {
        unread = nil
        do {
            draft = try await model.trialDraft(version: version.n)
        } catch {
            draft = nil
            unread = words("version.trial.card_not_read", ["n": String(version.n), "why": NeedsYouModel.why(error)])
        }
    }
}

/// An open trial's bar over its chat, as the iPad's `TrialScreen.bar`: "Trying version n", not live, and Go back and
/// Install, each asked first. Then tafs cloud's guide for it.
struct TrialBar: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafPagesModel
    let trial: Trials.Open
    let name: String
    @State private var confirmBack = false
    @State private var confirmInstall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(words("version.trial.trying", ["n": String(trial.n)])).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                Text(words("version.not_live_tag")).font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Theme.amber))
                Spacer()
                Button(words("version.go_back")) { confirmBack = true }
                    .buttonStyle(OutlineButtonStyle(color: Theme.no)).fixedSize().disabled(model.trialBusy)
                if model.startsTrials {
                    Button(model.trialBusy ? words("version.working") : words("version.install")) { confirmInstall = true }
                        .buttonStyle(OutlineButtonStyle()).fixedSize().disabled(model.trialBusy)
                }
            }
            guide
            if let error = model.trialError {
                Text(verbatim: error).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        .alert(words("version.go_back_title"), isPresented: $confirmBack) {
            Button(words("version.go_back"), role: .destructive) { Task { _ = await model.goBackFromTrial() } }
            Button(words("common.cancel"), role: .cancel) {}
        } message: {
            Text(words("version.go_back_body", ["version": String(trial.n), "taf": name]))
        }
        .alert(words("version.install_title", ["version": String(trial.n)]), isPresented: $confirmInstall) {
            Button(words("version.install")) { Task { _ = await model.installTrial() } }
            Button(words("common.cancel"), role: .cancel) {}
        } message: {
            Text(words("version.install_body", ["version": String(trial.n)]))
        }
    }

    /// tafs cloud's guide, as the iPad's `TrialScreen.guide`: what's new, the task to try, and when it ends unused.
    @ViewBuilder private var guide: some View {
        if let changed = trial.changed, !changed.isEmpty {
            Text(words("version.guide.whats_new", ["changed": changed])).font(.system(size: 13)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
        if let tryWith = trial.tryWith, !tryWith.isEmpty {
            Text(words("version.guide.try_with", ["try_with": tryWith])).font(.system(size: 13)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
        Text(verbatim: [words("version.guide.keeps_working", ["name": name]),
                        trial.ends.map { words("version.guide.trial_ends", ["date": AppDates.formatter(words, date: .medium).string(from: $0)]) },
                        words("version.guide.install_or_back")].compactMap { $0 }.joined(separator: " "))
            .font(.system(size: 12)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
    }
}

import SwiftUI

/// An improvement's result, as the iPad's `improvement(_:)` (SetupChatView.swift:1380-1420): the
/// taf's next version, which tafs cloud makes and answers the card with, to try and switch to from
/// its Versions. Nothing goes live. The card is whole from the start: its button is there while the
/// version is made, and says what it opens, the version, never the taf.
struct ImprovementCard: View {
    @Environment(\.words) private var words
    let card: Thread.Card
    /// The taf it is the next version of, when it's listed (`Thread.Card.improvedTaf`).
    let taf: Home.Taf?
    /// Opens that taf's Versions; nil where none can be opened.
    let openVersions: ((Home.Taf) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: words("coach.result.new_version", ["taf": card.tafName ?? ""]), color: Theme.ok)
            Text(verbatim: card.text ?? "").font(.system(size: 15)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
            // What changed, in tafs cloud's words.
            if let note = card.tafNote {
                Text(verbatim: note).font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            }
            outcome
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).stroke(Theme.ok))
    }

    /// The name the taf goes by, listed, else the result's own.
    private var name: String { taf?.name ?? card.tafName ?? "" }

    @ViewBuilder private var outcome: some View {
        switch card.improvement {
        case .made(let n):
            if let taf, let openVersions {
                Button { openVersions(taf) } label: {
                    Text(words("coach.result.see_version", ["version": String(n)])).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Text(words("coach.result.version_made", ["version": String(n)])).font(.system(size: 13)).foregroundColor(Theme.dim)
            }
        case .failed(let why):
            // tafs cloud told Coach, which hands it over again: no Try again here.
            Text(words("coach.not_improved", ["owner": name, "why": Thread.Card.notImprovedWhy(why)]))
                .font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
            Text(words("coach.coach_knows")).font(.system(size: 13)).foregroundColor(Theme.dim)
        case .preparing:
            Button {} label: {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(words("coach.result.preparing"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(true)
        }
    }
}

/// A taf's Versions, opened from Coach on a new version's card.
struct CoachVersions: Identifiable {
    let id = UUID()
    let model: TafPagesModel
}

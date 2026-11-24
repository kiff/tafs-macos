import SwiftUI

/// Coach asks to drive the app (tafs docs/drive.md), as the iPad's `DriveCard`. A drive runs on the
/// phone's own screen and is approved there with the phone's approval key, so this Mac shows the request
/// and says to approve on the phone: no Approve, and no Not now, which would answer the phone's request
/// from here. Once answered, the iPad's line: Coach drove the app, or Not now.
struct DriveAsk: View {
    @Environment(\.words) private var words
    let card: Thread.Card
    let state: Thread.Page.DriveCard

    var body: some View {
        let task = card.text ?? card.title ?? words("drive.drive_app")
        switch state {
        case .declined:
            line("minus.circle.fill", Theme.dim, words("drive.declined_line"))
        case .drove:
            line("checkmark.circle.fill", Theme.ok, words("drive.coach_drove_app", ["task": task]))
        case .asking:
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: words("drive.needs_you_let_coach_drive"), color: Theme.amberText)
                Text(verbatim: task).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(words("approval.security_key.on_phone")).font(.system(size: 13)).foregroundColor(Theme.soft)
                    .accessibilityIdentifier("coach.drive.on_phone")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).stroke(Theme.amber))
        }
    }

    private func line(_ symbol: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundColor(color).accessibilityHidden(true)
            Text(verbatim: text).font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.raised.opacity(0.6)))
    }
}

/// "What I did": a drive's end in Coach's thread, as the iPad's `DriveRecapCard`: the request, each
/// step from tafs cloud's record, and why it ended.
struct DriveRecap: View {
    @Environment(\.words) private var words
    let drive: Thread.Drive

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: words("drive.what_i_did"), color: Theme.amberText)
            Text(verbatim: drive.task).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if drive.steps.isEmpty {
                Text(words("drive.no_step_done")).font(.system(size: 14)).foregroundColor(Theme.soft)
            }
            ForEach(Array(drive.steps.enumerated()), id: \.offset) { _, step in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "circle.fill").font(.system(size: 5)).foregroundColor(Theme.dim).accessibilityHidden(true)
                    Text(verbatim: step.shown).font(.system(size: 14)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(verbatim: drive.ended(words)).font(.system(size: 13)).foregroundColor(Theme.soft)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        .textSelection(.enabled)
    }
}

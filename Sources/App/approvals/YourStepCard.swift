import SwiftUI

/// A step a taf handed its owner, as the iPad's `YourStepCard`: tafs cloud's title, the taf, what
/// to do and why, the vendor's page only as tafs cloud vouched for it, and Done or Skip when this
/// Mac can answer (`NeedsYouModel.startAnswer`: confirmed, then signed by the device key). Drawn in
/// Needs you, and in place of a request's line in a taf's work (`TafWorkPanel`), as on the iPad.
struct YourStepCard: View {
    @ObservedObject var model: NeedsYouModel
    let step: YourStep
    /// Whether this person answers the account's held calls (KIFF's `holds.answer`).
    var answersHolds = true
    /// The lists read again after an answer.
    var answered: () async -> Void = {}
    /// Why the last answer wasn't taken, under the card: where Needs you's title isn't above it.
    var saysWhy = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !step.words.title.isEmpty { Eyebrow(text: step.words.title) }
            if let name = step.taf?.name, !name.isEmpty {
                Text(verbatim: name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
            }
            Text(verbatim: step.what).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !step.why.isEmpty {
                Text(verbatim: step.why).font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            }
            if let link = step.openLink {
                VStack(alignment: .leading, spacing: 4) {
                    Button { openURL(link.url) } label: {
                        Label(link.words, systemImage: "arrow.up.right.square").padding(.horizontal, 16)
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .fixedSize()
                    // Where it really goes, as tafs cloud read the link.
                    Text(verbatim: link.host).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.dim)
                }
            }
            if model.canAnswerSteps(answersHolds: answersHolds) {
                HStack(spacing: 8) {
                    Button { model.startAnswer(step, done: true, answersHolds: answersHolds, answered: answered) } label: {
                        Text(verbatim: step.words.done).padding(.horizontal, 16)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button { model.startAnswer(step, done: false, answersHolds: answersHolds, answered: answered) } label: {
                        Text(verbatim: step.words.skip).padding(.horizontal, 16)
                    }
                    .buttonStyle(OutlineButtonStyle())
                }
                .fixedSize()
                .disabled(model.answeringSteps.contains(step.handoff))
            }
            if saysWhy, let why = model.stepNotAnswered {
                Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).stroke(Theme.amber.opacity(0.4)))
        .accessibilityElement(children: .contain)
    }
}

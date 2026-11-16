import SwiftUI

/// One decision, as the iPad's `DecisionCard` (BriefView.swift:171-259): its taf, the question,
/// Coach's recommendation with its why, what happens meanwhile, why it can't wait when it can't,
/// and its answers. The recommended answer is filled; the others outlined, a decline in red, and
/// Later beside them. An answer opens Needs you, where the call or step is answered with nothing
/// chosen ahead: nothing is decided or signed here.
struct DecisionCard: View {
    let decision: Brief.Decision
    let words: Brief.Words
    var taf: Home.Taf?
    /// Opens Needs you, where it's answered.
    let answer: () -> Void
    let later: () -> Void

    var body: some View {
        BriefPanel(stroke: decision.urgent ? Theme.no.opacity(0.5) : Theme.line) {
            head
            Text(verbatim: decision.question).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
            if let pick = decision.recommended, let why = decision.why { recommendation(pick, why: why) }
            if !decision.meanwhile.isEmpty {
                (Text(verbatim: words.meanwhile + " ").bold() + Text(verbatim: decision.meanwhile))
                    .font(.system(size: 14)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
            if let why = decision.cantWait {
                Label(why, systemImage: "clock").font(.system(size: 13)).foregroundColor(Theme.no)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.no.opacity(0.08)))
            }
            answers
            if let note = decision.note {
                Text(verbatim: note).font(.system(size: 12)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var head: some View {
        HStack(spacing: 8) {
            if let taf {
                TafAvatar(name: taf.name, color: taf.color, size: 26)
                Text(verbatim: taf.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
            }
            Spacer()
            if decision.urgent {
                // tafs cloud's word for it ("Urgent"); the bolt alone where it sent none.
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill").font(.system(size: 10)).accessibilityHidden(true)
                    if !words.urgent.isEmpty { Text(verbatim: words.urgent).font(.system(size: 11, weight: .semibold)) }
                }
                .foregroundColor(Theme.onFill)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(Capsule().fill(Theme.no))
            } else if let deadline = decision.deadline {
                Text(verbatim: deadline).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.amberText)
            }
        }
    }

    private func recommendation(_ pick: Brief.Answer, why: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label { Text(verbatim: "\(words.recommends): \(pick.words)") } icon: { Image(systemName: "sparkle") }
                .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.coach)
            Text(verbatim: why).font(.system(size: 14)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.coachWash))
    }

    @ViewBuilder private var answers: some View {
        let pick = decision.recommended
        let others = decision.answers.filter { $0 != pick }
        if let pick {
            Button(action: answer) { Label(pick.words, systemImage: "sparkle") }.buttonStyle(PrimaryButtonStyle())
        }
        // An urgent decision can't be put off: no Later, whatever was sent.
        let laterWords = decision.offersLater
        if !others.isEmpty || laterWords != nil {
            HStack(spacing: 10) {
                ForEach(others) { a in
                    Button(a.words, action: answer).buttonStyle(OutlineButtonStyle(color: a.decline ? Theme.no : Theme.ink))
                }
                if let laterWords { Button(laterWords, action: later).buttonStyle(OutlineButtonStyle()) }
            }
        }
    }
}

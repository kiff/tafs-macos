import SwiftUI

/// An answer to report, from the chat it's in.
struct ReportedAnswer: Identifiable {
    let message: Thread.Message
    var id: String { message.id ?? "" }
}

/// Reports an answer Coach or a taf wrote, as the iPad's `ReportAnswerSheet`: a reason, an
/// optional note, and Send. Sent, it says a person at KIFF will read it; not sent, it says why
/// and stays open to send again.
struct ReportAnswerSheet: View {
    @Environment(\.words) private var words
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: CoachModel
    let answer: ReportedAnswer
    @State private var reason: AnswerReport.Reason?
    @State private var note = ""
    @State private var sending = false
    @State private var failed: String?
    @State private var done: CoachModel.ReportOutcome?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(words("report.menu")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .accessibilityAddTraits(.isHeader)
            if let done { thanks(done) } else { form }
        }
        .frame(width: 440)
        .background(Theme.background)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(words("report.what_wrong")).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.dim)
            VStack(spacing: 0) {
                ForEach(AnswerReport.Reason.allCases) { r in
                    Button { reason = r } label: {
                        HStack {
                            Text(words(r.key)).foregroundColor(Theme.ink)
                            Spacer()
                            if reason == r { Image(systemName: "checkmark").foregroundColor(Theme.amberText) }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(reason == r ? .isSelected : [])
                }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.panel))
            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text(words("report.note_hint")).foregroundColor(Theme.dim).padding(.horizontal, 5).padding(.vertical, 8)
                }
                TextEditor(text: $note).frame(height: 80)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.panel))
            if note.count > AnswerReport.noteLimit {
                Text(words("report.note_most_characters")).font(.system(size: 13)).foregroundColor(Theme.no)
            }
            Text(words("report.person_kiff_reads_your_report")).font(.system(size: 12)).foregroundColor(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            if let failed {
                Text(words("report.not_sent_why", ["failed": failed])).font(.system(size: 14)).foregroundColor(Theme.no)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(words("common.cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(words("common.send")) { send() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(reason == nil || sending || note.count > AnswerReport.noteLimit)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 20)
    }

    private func thanks(_ outcome: CoachModel.ReportOutcome) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle").font(.system(size: 40)).foregroundColor(Theme.amberText)
            Text(words(outcome == .already ? "report.already" : "report.thanks"))
                .font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.ink)
                .multilineTextAlignment(.center)
            Button(words("common.done")) { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private func send() {
        guard let reason, !sending else { return }
        sending = true
        failed = nil
        Task {
            let outcome = await model.report(answer.message, reason: reason, note: note)
            sending = false
            if case .failed(let why) = outcome { failed = why } else { done = outcome }
        }
    }
}

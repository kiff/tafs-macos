import AppKit
import SwiftUI

/// One Record line's KIFF receipt, checked on this Mac, as the iPad's `ReceiptView`: the line, what
/// happened (only once the receipt checks out as KIFF's and matches the line), and the check itself.
/// Nothing opens outside the app.
struct ReceiptSheet: View {
    @Environment(\.words) private var words
    @ObservedObject var model: RecordModel
    let entry: Record.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: [entry.title, entry.amountText].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.display(24)).foregroundColor(Theme.ink)
                Spacer()
                Button(words("common.done")) { model.closeReceipt() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    facts
                    whatHappened
                    checkPanel
                    reportPanel
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 600, height: 640)
        .background(Theme.background)
    }

    private var steps: ReceiptSteps { ReceiptSteps(model.receiptRaw ?? Data()) }

    /// The line's amount or answer isn't the one KIFF signed.
    private var amountMismatch: Bool { steps.amountMismatch(entry.amount) }
    private var answerMismatch: Bool { steps.answerMismatch(entry.answer) }

    /// The line as tafs cloud words it: its taf, when, and how it went.
    private var facts: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "\(entry.taf.name) · \(entry.time)").font(.system(size: 13, design: .monospaced)).foregroundColor(Theme.dim)
            Text(verbatim: [entry.about, entry.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What KIFF signed for this line: drawn only once this Mac checked the receipt as KIFF's and it
    /// matches the line.
    @ViewBuilder private var whatHappened: some View {
        if !steps.steps.isEmpty, ReceiptCheck.showsWhatHappened(model.receiptCheck, mismatch: amountMismatch || answerMismatch) {
            Eyebrow(text: words("receipt.what_happened"))
            ForEach(Array(steps.steps.enumerated()), id: \.offset) { _, step in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: step.words.prefix(1).uppercased() + step.words.dropFirst()).font(.system(size: 14)).foregroundColor(Theme.ink)
                    if let at = step.at { Text(verbatim: time(at)).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.dim) }
                }
            }
        }
    }

    /// "Report this payment", as the iPad's `ReportPaymentSheet`, at the receipt's foot where tafs cloud offers it: a
    /// payment the person didn't expect. One click reports it and halts its taf; resuming stays behind an approval. The words
    /// are the app's (`record.report.*`), with the line's own taf, amount and date.
    @ViewBuilder private var reportPanel: some View {
        let phase = model.reportPhase[entry.id] ?? .asking
        if phase == .done {
            Text(words("record.report.done", ["taf": entry.taf.name])).font(.system(size: 15)).foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("record.report.done")
        } else if entry.offersReport() {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: words("record.report.title"))
                Text(words("record.report.intro", ["taf": entry.taf.name, "amount": entry.amountText ?? "", "date": reportDate]))
                    .font(.system(size: 14)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
                if phase == .failed {
                    Text(words("record.report.failed")).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.no)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button { Task { await model.report(entry) } } label: {
                    HStack(spacing: 8) {
                        Text(words("record.report.submit", ["taf": entry.taf.name]))
                        if phase == .sending { ProgressView().controlSize(.small) }
                    }
                }
                .buttonStyle(OutlineButtonStyle(color: Theme.no))
                .disabled(phase == .sending)
                .accessibilityIdentifier("record.report")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        }
    }

    /// When the payment was made, long, in the person's language: tafs cloud's time for it, else the line's.
    private var reportDate: String {
        AppDates.formatter(words, date: .long).string(from: entry.report?.at ?? entry.at)
    }

    @ViewBuilder private var checkPanel: some View {
        switch model.receiptCheck {
        case .verified? where amountMismatch:
            failed(words("receipt.check.amount_mismatch"))
        case .verified? where answerMismatch:
            failed(words("receipt.check.answer_mismatch"))
        case .verified(let signer)?:
            verified(signer)
        case .notSignedYet?:
            notSignedYet
        case .failed(let why)?:
            failed(words("receipt.changed"), why: words(why.key))
        case nil:
            loading
        }
    }

    private func verified(_ signer: String) -> some View {
        panel(stroke: Theme.ok) {
            Label(words("receipt.checked_on_device", ["device": words("device.mac")]), systemImage: "checkmark.seal.fill")
                .font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ok)
            Text(words("receipt.checked_why")).font(.system(size: 13)).foregroundColor(Theme.soft)
            issued
            fullReceipt(signer: signer)
            copyButton
        }
    }

    private var notSignedYet: some View {
        panel(stroke: Theme.line) {
            Text(words("receipt.not_signed_yet")).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
            Text(words("receipt.signs_within")).font(.system(size: 13)).foregroundColor(Theme.soft)
            if Date().timeIntervalSince(entry.at) > 10 * 60 {
                Text(words("receipt.if_it_stays")).font(.system(size: 13)).foregroundColor(Theme.soft)
                Text(verbatim: entry.receipt?.traceID ?? "").font(.system(size: 11.5, design: .monospaced)).foregroundColor(Theme.dim).textSelection(.enabled)
            }
        }
    }

    private func failed(_ what: String, why: String? = nil) -> some View {
        panel(stroke: Theme.no) {
            Label(words("record.kiff_receipt_does_not_check"), systemImage: "xmark.seal.fill")
                .font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.no)
            Text(what).font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            if let why { Text(why).font(.system(size: 13)).foregroundColor(Theme.soft) }
            fullReceipt(signer: nil)
            copyButton
        }
    }

    private var loading: some View {
        panel(stroke: Theme.line) {
            if let why = model.receiptError {
                Text(words("receipt.not_loaded", ["why": why])).font(.system(size: 13)).foregroundColor(Theme.no)
                Button(words("common.try_again")) { Task { await model.loadReceipt() } }.buttonStyle(OutlineButtonStyle())
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(words("receipt.checking_on_device", ["device": words("device.mac")])).font(.system(size: 13)).foregroundColor(Theme.soft)
                }
            }
        }
    }

    /// When KIFF issued it; the receipt's id and signer are under "Show the full receipt".
    @ViewBuilder private var issued: some View {
        if let at = steps.issuedAt {
            Text(words("receipt.issued", ["at": dateTime(at)])).font(.system(size: 11.5, design: .monospaced)).foregroundColor(Theme.dim)
        }
    }

    /// Every step KIFF signed, with its hash, and the signature, as the iPad's.
    @ViewBuilder private func fullReceipt(signer: String?) -> some View {
        if !steps.steps.isEmpty {
            DisclosureGroup {
                Text(verbatim: fullLines(signer: signer)).font(.system(size: 11.5, design: .monospaced)).foregroundColor(Theme.dim)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            } label: {
                Text(words("receipt.show_full")).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.sky)
            }
        }
    }

    private func fullLines(signer: String?) -> String {
        let trace = entry.receipt?.traceID ?? ""
        var lines = [["receipt \(trace)", signer.map { "signer \($0.prefix(6))…\($0.suffix(4))" }].compactMap { $0 }.joined(separator: " · ")]
        for (i, step) in steps.steps.enumerated() {
            // KIFF's signed message, as it signed it: the full receipt is the receipt, not its words (tafs#1709).
            lines.append("\(i + 1)  \(step.message) · \(step.at.map(time) ?? "")\n   hash \(step.hash)")
        }
        if let sig = steps.signature {
            lines.append("✎  trace \(trace) · secp256k1 + keccak256\n   sig 0x\(sig.prefix(4))…\(sig.suffix(4))")
        }
        return lines.joined(separator: "\n")
    }

    @ViewBuilder private var copyButton: some View {
        if let raw = model.receiptRaw, let text = String(data: raw, encoding: .utf8) {
            Button(words("receipt.copy")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            .buttonStyle(OutlineButtonStyle())
        }
    }

    private func panel<Content: View>(stroke: Color, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(stroke.opacity(0.5)))
    }

    private func time(_ date: Date) -> String { AppDates.formatter(words, time: .medium).string(from: date) }
    private func dateTime(_ date: Date) -> String { AppDates.formatter(words, date: .medium, time: .medium).string(from: date) }
}

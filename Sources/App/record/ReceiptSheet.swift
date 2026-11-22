import AppKit
import SwiftUI

/// One Record line's KIFF receipt, checked on this Mac, as the iPad's `ReceiptView`: the line, what
/// happened (only once the receipt checks out as KIFF's and matches the line), and the check itself.
/// Nothing opens outside the app.
struct ReceiptSheet: View {
    @Environment(\.words) private var words
    @Environment(\.openTaf) private var openTaf
    @ObservedObject var model: RecordModel
    let entry: Record.Entry
    /// The person's tafs: the line's own, when listed, opens on its chat.
    var tafs: [Home.Taf] = []
    /// The account's time zone, for When.
    var timeZone: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    facts
                    whatHappened
                    checkPanel
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 600, height: 640)
        .background(Theme.background)
    }

    /// How it went, by its kind's colour, then the line, as the iPad's (RecordView.swift:385-391); Done.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(kindColor).frame(width: 10, height: 10).accessibilityHidden(true)
                Text(verbatim: entry.receiptLabel(words)).font(.system(size: 14, weight: .semibold)).foregroundColor(kindColor)
                Spacer()
                Button(words("common.done")) { model.closeReceipt() }.keyboardShortcut(.cancelAction)
            }
            Text(verbatim: [entry.title, entry.amountText].compactMap { $0 }.joined(separator: " · "))
                .font(Theme.display(24)).foregroundColor(Theme.ink)
        }
    }

    private var kindColor: Color {
        switch TafActivity.Entry.tone(of: entry.kind) {
        case .ok: return Theme.ok
        case .amber: return Theme.amber
        case .no: return Theme.no
        }
    }

    private var steps: ReceiptSteps { ReceiptSteps(model.receiptRaw ?? Data()) }

    /// The first way the line isn't what KIFF signed (its payment, amount or answer), as a shared key;
    /// nil when it matches. The payment is compared only on a named line (`entry.onValue`).
    private var mismatch: String? {
        steps.mismatchKey(onValue: entry.onValue, amount: entry.amount, answer: entry.answer, sha256: PasskeyCrypto.sha256)
    }

    /// The listed taf the line is from, to open on its chat.
    private var taf: Home.Taf? { tafs.first { $0.tafID == entry.taf.id } }

    /// The line's facts, as the iPad's (RecordView.swift:392-402): its taf, when, what it acted on,
    /// the outcome, KIFF's why and who decided; then Open in the taf's chat.
    @ViewBuilder private var facts: some View {
        VStack(alignment: .leading, spacing: 12) {
            fact(words("receipt.fact.taf"), entry.taf.name.isEmpty ? "–" : entry.taf.name)
            fact(words("receipt.fact.at"), AccountTime(timeZone).zonedShown(entry.at, date: .abbreviated, time: .standard, words: words))
            if let on = entry.receiptOn { fact(words("receipt.fact.on"), on) }
            fact(words("receipt.fact.outcome"), entry.receiptOutcome(words), bold: true)
            if let reason = entry.reason { fact(words("receipt.fact.why"), reason) }
            fact(words("receipt.fact.decided_by"), entry.receiptDecidedBy(words))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
        // The iPad's last button; here under the facts, as this sheet's foot holds the receipt's own.
        if let open = openTaf, let taf {
            Button {
                model.closeReceipt()
                model.closeCase()
                open(taf)
            } label: {
                Text(words("record.open_taf_chat")).frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func fact(_ name: String, _ value: String, bold: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).font(.system(size: 13)).foregroundColor(Theme.dim).frame(width: 90, alignment: .leading)
            Text(verbatim: value).font(.system(size: 14, weight: bold ? .semibold : .regular)).foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// What KIFF signed for this line: drawn only once this Mac checked the receipt as KIFF's and it
    /// matches the line.
    @ViewBuilder private var whatHappened: some View {
        if !steps.steps.isEmpty, ReceiptCheck.showsWhatHappened(model.receiptCheck, mismatch: mismatch != nil) {
            Eyebrow(text: words("receipt.what_happened"))
            ForEach(Array(steps.steps.enumerated()), id: \.offset) { _, step in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: step.words.prefix(1).uppercased() + step.words.dropFirst()).font(.system(size: 14)).foregroundColor(Theme.ink)
                    if let at = step.at { Text(verbatim: time(at)).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.dim) }
                }
            }
        }
    }

    @ViewBuilder private var checkPanel: some View {
        switch model.receiptCheck {
        case .verified? where mismatch != nil:
            // The payment first, then the amount, then the answer, as the iPad's order.
            failed(words(mismatch ?? ""))
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

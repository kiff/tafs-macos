import SwiftUI

/// One call found in the Record, or one step of a case, as the iPad's `RecordHitRow`
/// (RecordSearchViews.swift:65-95): its taf's name, then the call as its taf's Activity draws it
/// (`SourceActivityRow`, TafPresentationViews.swift:326-361), opening its receipt, with its own next
/// step under it; a taf the person doesn't list (one they only oversee) shows the call as tafs cloud
/// words it, boxed, without its next step. In a search, what it's about opens its case.
struct RecordStepRow: View {
    @Environment(\.words) private var words
    @ObservedObject var model: RecordModel
    let entry: Record.Entry
    /// The call's taf is one of the person's listed tafs (the iPad's `tafID(cloudID:)`).
    let listed: Bool
    /// Off in a case, where every step is about the same thing.
    var opensCase = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: entry.taf.name).font(.system(size: 11, weight: .medium, design: .monospaced)).textCase(.uppercase).foregroundColor(Theme.dim)
            if listed {
                activity
            } else {
                overseen
            }
            if opensCase, let about = entry.about {
                Button { Task { await model.open(case: about) } } label: {
                    Text(verbatim: "\(about) ›").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.amberText)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The iPad's `SourceActivityRow`: a plain row, not boxed, that opens the call's sheet whenever KIFF's
    /// call names its taf (the iPad's `evidence`), receipt or not, then its next step. The next step is
    /// tafs cloud's words, as the iPad shows anyone it gives no button: its buttons (connect again, Ask
    /// Coach) are `NextStepRow`'s, not on this Mac yet.
    private var activity: some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.hasActor {
                Button { Task { await model.openReceipt(entry) } } label: { face }
                    .buttonStyle(.plain)
                    .help(words("record.shows_receipt"))
            } else {
                face
            }
            if let next = entry.next {
                Text(verbatim: next.words).font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Title over detail; its time over its amount at the right.
    private var face: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: entry.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                Text(verbatim: entry.detail).font(.system(size: 13)).foregroundColor(Theme.soft)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(verbatim: entry.time).font(.system(size: 12)).foregroundColor(Theme.dim)
                if let amount = entry.amountText { Text(verbatim: amount).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.ink) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// A taf the person only oversees: the call as tafs cloud words it, in a panel, with no next step.
    private var overseen: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: entry.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
            Text(verbatim: entry.detail).font(.system(size: 13)).foregroundColor(Theme.soft)
            if let amount = entry.amountText { Text(verbatim: amount).font(.system(size: 14, weight: .medium)).foregroundColor(Theme.ink) }
            Text(verbatim: entry.time).font(.system(size: 12)).foregroundColor(Theme.dim)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
    }
}

extension Theme {
    /// A Record line's colour by its kind, as the iPad's `RecordEntry.Kind.color` (`Record.tone`).
    static func recordColor(_ kind: String) -> Color {
        switch Record.tone(of: kind) {
        case .ok: return Theme.ok
        case .amber: return Theme.amber
        case .no: return Theme.no
        case .dim: return Theme.dim
        }
    }
}

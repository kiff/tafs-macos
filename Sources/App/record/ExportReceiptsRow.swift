import AppKit
import SwiftUI

/// Export receipts, as the iPad's `ExportReceiptsRow` (RecordSearchViews.swift:128-191): a range of
/// days inside tafs cloud's 92, then its export as two files, KIFF's receipts as tafs cloud passed
/// them and its CSV. The iPad hands them to its share sheet; this Mac saves them where the person
/// chooses, in a save panel. It only reads: nothing is signed or sent.
@MainActor
final class ReceiptsExportModel: ObservableObject {
    /// The ranges are shown.
    @Published var open = false
    @Published private(set) var preparing = false
    /// Why the last export didn't happen, in the shared words; nil after one that did.
    @Published private(set) var why: String?
    /// Calls the last export listed without their receipt.
    @Published private(set) var missing = 0
    /// Where the last export's files were saved.
    @Published private(set) var saved: [URL]?

    private let cloud: CloudClient
    /// Today, for the range; a test sets its own.
    var today: () -> Date = Date.init
    /// Where the two files go, by their name: a folder the person chooses in a save panel, or nil
    /// when they cancel. A test answers its own.
    var choose: @MainActor (String) -> URL? = { name in ReceiptsExportModel.askWhere(name) }

    init(cloud: CloudClient) {
        self.cloud = cloud
    }

    /// Reads the last `count` days' receipts in the account's calendar, then saves them where the
    /// person chooses, as the iPad's `export`.
    func export(_ count: Int, calendar: Calendar, words: Words) async {
        guard !preparing else { return }
        let range = Record.exportRange(count, today: today(), calendar: calendar)
        preparing = true
        why = nil
        missing = 0
        let read: Record.ReceiptsExport
        do {
            read = try await cloud.exportReceipts(from: range.from, to: range.to)
        } catch {
            preparing = false
            why = words("record.export_not_exported", ["why": NeedsYouModel.why(error)])
            return
        }
        preparing = false
        missing = read.missing
        open = false
        // Cancelled, nothing is saved.
        guard let folder = choose(read.stem) else { return }
        do {
            saved = try Record.write(read, to: folder)
        } catch {
            why = words("record.export_not_exported", ["why": error.localizedDescription])
        }
    }

    /// The save panel: a folder named as the files, where both are written.
    static func askWhere(_ name: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// The orange "Export receipts" under the search box: it opens the ranges, Last 7, 30 and 90 days;
/// "Preparing receipts…" while tafs cloud makes them; then how many calls have no receipt yet, or
/// why they couldn't be exported.
struct ExportReceiptsRow: View {
    @Environment(\.words) private var words
    @ObservedObject var model: ReceiptsExportModel
    /// The account's time zone, as KIFF says it: the days are the account's.
    var timeZone: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { model.open.toggle() } label: { label }
                .buttonStyle(.plain)
                .disabled(model.preparing)
            if model.open && !model.preparing { ranges }
            if model.missing > 0 {
                Text(verbatim: words.count("record.export_missing", model.missing)).font(.system(size: 13)).foregroundColor(Theme.soft)
            }
            if let why = model.why { Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no) }
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            if model.preparing { ProgressView().controlSize(.small) }
            Text(model.preparing ? words("record.export_preparing") : words("record.export_receipts"))
                .font(.system(size: 15, weight: .semibold)).foregroundColor(model.preparing ? Theme.dim : Theme.amberText)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
    }

    private var ranges: some View {
        HStack(spacing: 8) {
            ForEach(Record.exportDays, id: \.self) { count in
                Button(words.count("record.export_last_days", count)) {
                    let calendar = AccountTime(timeZone).calendar
                    let say = words
                    Task { await model.export(count, calendar: calendar, words: say) }
                }
                .buttonStyle(OutlineButtonStyle())
            }
        }
    }
}

import SwiftUI

/// A call's sheet opened from a taf's Activity row, as the iPad's `SourceActivityRow` opens its
/// `ReceiptView`: the Record's own sheet (`ReceiptSheet`), on the Record's model, so the receipt is
/// read and checked on this Mac exactly as from the Record. Attached behind the Activity, as the
/// Record attaches its own, so it never shares a level with the page's other sheets.
struct ActivityReceiptHost: View {
    @ObservedObject var model: RecordModel
    let tafs: [Home.Taf]
    let timeZone: String?

    var body: some View {
        EmptyView().sheet(isPresented: shown) {
            if let entry = model.receiptEntry { ReceiptSheet(model: model, entry: entry, tafs: tafs, timeZone: timeZone) }
        }
    }

    /// Up while a line is open outside a case (the Record's cases are the Record's own), and
    /// closing it closes the line.
    private var shown: Binding<Bool> {
        Binding(get: { model.receiptEntry != nil && model.caseAbout == nil }, set: { if !$0 { model.closeReceipt() } })
    }
}

import Foundation

/// Export receipts, as the iPad's `ExportReceiptsRow` and `TafsCloud.exportReceipts`
/// (RecordSearchViews.swift:128-191, TafsCloud+Record.swift:99-130): a range of days inside tafs
/// cloud's 92, for someone who sees every taf's Record, as two files: tafs cloud's answer byte
/// for byte (KIFF's receipts exactly as issued, never re-encoded) and its CSV.
extension Record {
    struct ReceiptsExport: Equatable {
        let from: String
        let to: String
        /// tafs cloud's answer as it came.
        let json: Data
        let csv: String
        /// Calls whose receipt KIFF couldn't give just now, listed without it.
        let missing: Int

        /// The two files' name, as the iPad's: "receipts-2026-11-11-to-2026-11-17".
        var stem: String { "receipts-\(from)-to-\(to)" }
    }

    /// The day ranges offered, as the iPad's.
    static let exportDays = [7, 30, 90]

    /// The last `count` days, today among them, as the account's calendar days (YYYY-MM-DD).
    static func exportRange(_ count: Int, today: Date, calendar: Calendar) -> (from: String, to: String) {
        let from = calendar.date(byAdding: .day, value: -(count - 1), to: today) ?? today
        func day(_ date: Date) -> String {
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
        return (day(from), day(today))
    }

    /// Writes the two files into `folder`, made if it isn't there: `<stem>.json` and `<stem>.csv`.
    /// Nothing else in the folder is touched.
    static func write(_ export: ReceiptsExport, to folder: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = folder.appendingPathComponent("\(export.stem).json"), csv = folder.appendingPathComponent("\(export.stem).csv")
        try export.json.write(to: json)
        try Data(export.csv.utf8).write(to: csv)
        return [json, csv]
    }
}

extension CloudClient {
    /// The receipts of `from` to `to` (YYYY-MM-DD, at most 92 days): `GET /v1/record/receipts`, the
    /// days written as the iPad sends them; anything but digits and dashes is escaped. A refusal (403
    /// for someone who doesn't see every taf's Record) throws tafs cloud's words.
    func exportReceipts(from: String, to: String) async throws -> Record.ReceiptsExport {
        func day(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "0123456789-")) ?? s }
        let raw = try await read("/v1/record/receipts?from=\(day(from))&to=\(day(to))", saying: true)
        guard let body = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else { throw KIFFError.unreadable }
        return Record.ReceiptsExport(from: body["from"] as? String ?? from, to: body["to"] as? String ?? to, json: raw,
                                     csv: body["csv"] as? String ?? "", missing: (body["missing"] as? NSNumber)?.intValue ?? 0)
    }
}

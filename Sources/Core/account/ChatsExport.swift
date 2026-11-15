import Foundation

/// Export my chats (kiff/tafs#424), as the iPad's: the person's own chats, trials and notes,
/// for their rights of access and portability, as two files, `tafs-chats.json` and
/// `tafs-chats.txt`.
enum ChatsExport {
    /// Splits tafs cloud's export into its two files, as the iPad's `splitExport`: its
    /// `readable` text, and the rest as JSON. An answer that isn't an object isn't an export.
    static func split(_ data: Data) throws -> (json: Data, text: String) {
        guard var body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw KIFFError.unreadable }
        let text = body.removeValue(forKey: "readable") as? String ?? ""
        let json = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return (json, text)
    }

    /// Where the two files are written: removed at sign-out, so a person's chats never stay
    /// on the Mac after them, and replaced at each export.
    static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("export", isDirectory: true)

    /// Writes the two files, replacing the last export's.
    static func write(_ export: (json: Data, text: String), in folder: URL = folder) throws -> [URL] {
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = folder.appendingPathComponent("tafs-chats.json"), text = folder.appendingPathComponent("tafs-chats.txt")
        try export.json.write(to: json)
        try Data(export.text.utf8).write(to: text)
        return [json, text]
    }

    static func removeFiles(in folder: URL = folder) {
        try? FileManager.default.removeItem(at: folder)
    }
}

extension CloudClient {
    /// The person's own chats, as tafs cloud exports them (`GET /v1/me/chats/export`).
    func exportChats() async throws -> (json: Data, text: String) {
        let request = HTTPRequest(method: "GET", path: "/v1/me/chats/export", headers: [
            "Authorization": "Bearer \(session.accessToken)", "Accept": "application/json",
            "Accept-Language": language, "User-Agent": "tafs-macos",
        ])
        let (status, body) = try await transport.send(request)
        guard (200..<300).contains(status) else { throw KIFFError(status: status, body: body) }
        return try ChatsExport.split(body)
    }
}

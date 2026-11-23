import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

private func fileJSON(_ id: String, name: String, media: String = "text/csv", run: String = "r1", created: String = "2026-11-20T09:00:00Z",
                      taf: String = "taf_1", tafName: String? = "Refunds") -> String {
    let named = tafName.map { #","taf_name":"\#($0)""# } ?? ""
    return #"{"id":"\#(id)","taf":"\#(taf)","run":"\#(run)","name":"\#(name)","media_type":"\#(media)","size":14000,"created":"\#(created)","expires":"2026-12-20T09:00:00Z"\#(named)}"#
}

let accountFilesTests: [Test] = [
    Test("a file reads as the iPad's DeliveredFile: its name is one name, its type its extension, else its media type's") {
        let decoder = AccountClient.decoder
        let f1 = try decoder.decode(DeliveredFile.self, from: Data(fileJSON("f1", name: "../../etc/Tickets.csv").utf8))
        try expectEqual(f1.name, "Tickets.csv")
        try expectEqual(f1.type, "CSV")
        let f2 = try decoder.decode(DeliveredFile.self, from: Data(fileJSON("f2", name: "report", media: "application/pdf", tafName: nil).utf8))
        try expectEqual(f2.type, "PDF")
        try expectEqual(f2.tafName, "")
    },
    Test("a name keeps no path, control or direction character, and nothing, . or .. is the file's id") {
        try expectEqual(FileText.name("a\\b/c\u{202E}fdp.exe", fallback: "f1"), "cfdp.exe")
        try expectEqual(FileText.name("..", fallback: "f1"), "f1")
        try expectEqual(FileText.name("dir/", fallback: "f1"), "dir")
        try expectEqual(FileText.name("\u{0007}\u{200F}", fallback: "f1"), "f1")
        try expectEqual(FileText.preview("a\r\nb\u{202A}\tc\u{0000}"), "a\nb\tc")
    },
    Test("the files group by day in the account's zone, by taf and by run, newest first; the days left never go below none") {
        let decoder = AccountClient.decoder
        let files = try [fileJSON("a", name: "a.csv", run: "r1", created: "2026-11-20T23:30:00Z"),
                         fileJSON("b", name: "b.csv", run: "r2", created: "2026-11-21T08:00:00Z", taf: "taf_2", tafName: "Leads"),
                         fileJSON("c", name: "c.csv", run: "r1", created: "2026-11-20T23:30:00Z")]
            .map { try decoder.decode(DeliveredFile.self, from: Data($0.utf8)) }
        // 23:30 UTC on the 20th is the 21st in Paris.
        try expectEqual(FilesGrouping.byDay(files, zone: TimeZone(identifier: "Europe/Paris")!).map(\.id), ["2026-11-21"])
        try expectEqual(FilesGrouping.byDay(files, zone: TimeZone(identifier: "UTC")!).map(\.id), ["2026-11-21", "2026-11-20"])
        try expectEqual(FilesGrouping.byTaf(files).map(\.id), ["taf_2", "taf_1"])
        try expectEqual(FilesGrouping.byRun(files).map { $0.files.map(\.id) }, [["b"], ["a", "c"]])
        let now = ISO8601DateFormatter().date(from: "2026-12-25T00:00:00Z")!
        try expectEqual(FilesGrouping.daysLeft(files[0], now: now), 0)
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        try expectEqual(FilesGrouping.goes(0, words: words), "goes today")
        try expectEqual(FilesGrouping.goes(5, words: words), "goes in 5 days")
    },
    Test("a download URL is https only, with no user or password in it") {
        try expect(FileDownload.url("https://storage.test/x?sig=1") != nil, "https")
        try expectEqual(FileDownload.url("http://storage.test/x"), nil)
        try expectEqual(FileDownload.url("https://a:b@storage.test/x"), nil)
        try expectEqual(FileDownload.url("https://a@storage.test/x"), nil)
        try expectEqual(FileDownload.url("file:///etc/passwd"), nil)
        try expectEqual(FileDownload.url("https:///x"), nil)
    },
    Test("the files are read page by page, a 404 is none; a preview is cleaned again; a download that isn't https is refused; Delete now is one DELETE", awaiting: {
        let first = #"{"files":[\#(fileJSON("f1", name: "a.csv")),{"id":"bad"}],"next":"c 2"}"#
        let second = #"{"files":[\#(fileJSON("f2", name: "b.csv"))]}"#
        let transport = CannedTransport([(200, first), (200, second), (404, #"{"error":"not_found"}"#),
                                         (200, #"{"preview":"a‮b\r\nc","preview_truncated":true}"#),
                                         (200, #"{"url":"http://storage.test/x"}"#), (200, #"{"deleted":"f1"}"#)])
        let cloud = CloudClient(transport: transport, session: session)
        let all = try await cloud.allFiles()
        try expectEqual(all.map(\.id), ["f1", "f2"])
        try expectEqual(transport.sent.map(\.path), ["/v1/files", "/v1/files?after=c%202"])
        let off = try await cloud.allFiles(taf: "taf_1")
        try expectEqual(off.count, 0)
        try expectEqual(transport.sent[2].path, "/v1/files?taf=taf%5F1")
        let preview = try await cloud.filePreview("f/1")
        try expectEqual(preview, FilePreviewText(text: "ab\nc", truncated: true))
        try expectEqual(transport.sent[3].path, "/v1/files/f%2F1")
        do { _ = try await cloud.fileDownload("f1"); throw Failure(description: "taken") } catch KIFFError.unreadable {}
        try await cloud.deleteFile("f1")
        try expectEqual(transport.sent[5].method + " " + transport.sent[5].path, "DELETE /v1/files/f1")
    }),
]

import Foundation

/// A server's id or file name, kept as one component under the app's own folder (kiff/work#20: agentgabo's Windows
/// catch, dev-android's Android one).
let shellLocalNameTests: [Test] = [
    Test("a name from the server stays one component inside its folder, whatever it holds") {
        let folder = URL(fileURLWithPath: "/tmp/tafs-test/attachments", isDirectory: true)
        for (name, want) in [("report.pdf", "report.pdf"), ("../x", ".._x"), ("/etc/passwd", "_etc_passwd"), ("..", "file"),
                             ("...", "file"), ("", "file"), ("a:b", "a_b"), ("C:evil.exe", "C_evil.exe"), ("x\u{0}y", "xy"),
                             ("  ", "file"), ("فاتورة.pdf", "فاتورة.pdf"), ("a\\b", "a_b")] {
            try expectEqual(LocalName.component(name), want)
            guard let url = LocalName.file(name, in: folder) else { throw Failure(description: "\(name) refused") }
            try expectEqual(url.deletingLastPathComponent().standardizedFileURL.path, folder.standardizedFileURL.path)
        }
        try expectEqual(LocalName.component("..", fallback: "attachment"), "attachment")
    },
    Test("an attachment whose id is . or .. is never asked for: it would fold into the path above", awaiting: {
        let transport = CannedTransport([(200, #"{"url":"https://example.com/x"}"#)])
        let cloud = CloudClient(transport: transport, session: Session(accessToken: "t", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil))
        for (taf, file) in [("taf-1", ".."), ("..", "f1"), ("taf-1", ".")] {
            do { _ = try await cloud.attachmentURL(taf, file: file); throw Failure(description: "\(taf)/\(file) was asked for") } catch KIFFError.unreadable {}
        }
        try expectEqual(transport.sent.count, 0)
        _ = try await cloud.attachmentURL("taf-1", file: "f/1")
        try expectEqual(transport.sent[0].path, "/v1/tafs/taf-1/attachments/f%2F1")
    }),
]

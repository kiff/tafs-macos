import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let words = (try? Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))) ?? Words(language: "en", lines: [:])

private func cloud(_ answers: [(Int, String)]) -> (CloudClient, CannedTransport) {
    let transport = CannedTransport(answers)
    return (CloudClient(transport: transport, session: session), transport)
}

/// What tafs cloud answers a declared file, as `POST /v1/tafs/{id}/attachments` does.
let attachAnswer = #"{"attachment":{"id":"att_1","kind":"pdf","media_type":"application/pdf","name":"Invoice.pdf","size":1200},"upload":{"url":"https://storage.example/put/att_1","method":"PUT","headers":{"Content-Type":"application/pdf"}}}"#
let attachedRef = AttachmentRef(id: "att_1", kind: "pdf", mediaType: "application/pdf", name: "Invoice.pdf", size: 1200)

private func json(_ data: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:] }

let coachFileTests: [Test] = [
    Test("a file over its kind's limit is refused, saying which, and a kind tafs doesn't take can't be attached, as the iPad's FilePrep") {
        try FilePrep.check(name: "a.pdf", size: 25 << 20, mediaType: "application/pdf", say: words)
        do {
            try FilePrep.check(name: "notes.txt", size: (2 << 20) + 1, mediaType: "text/plain", say: words)
            throw Failure(description: "taken")
        } catch let problem as FileProblem {
            try expectEqual(problem.message, "notes.txt is 2.0 MB; the most is 2.0 MB.")
        }
        do {
            try FilePrep.check(name: "song.mp3", size: 10, mediaType: "audio/mpeg", say: words)
            throw Failure(description: "taken")
        } catch let problem as FileProblem {
            try expectEqual(problem.message, "song.mp3 can't be attached.")
        }
        try expectEqual(FilePrep.limits["image/jpeg"], 10 << 20)
        try expectEqual(FilePrep.limits["application/pdf"], 25 << 20)
        try expectEqual(FilePrep.perMessage, 5)
        try expectEqual(FilePrep.megabytes(1_572_864), "1.5 MB")
    },
    Test("a photo is named after its file as a JPEG, else Photo; each kind has the iPad's symbol") {
        try expectEqual(FilePrep.photoName("Receipt.HEIC", photo: "Photo"), "Receipt.jpg")
        try expectEqual(FilePrep.photoName("", photo: "Photo"), "Photo.jpg")
        try expectEqual(FilePrep.symbol("image/png"), "photo")
        try expectEqual(FilePrep.symbol("application/pdf"), "doc.richtext")
        try expectEqual(FilePrep.symbol("text/csv"), "tablecells")
        try expectEqual(FilePrep.symbol("text/plain"), "doc.text")
    },
    Test("declaring a file posts its type, name, size and hash to the taf's attachments, and reads where to upload it", awaiting: {
        let (client, transport) = cloud([(201, attachAnswer)])
        let (ref, upload) = try await client.attach("taf 1", mediaType: "application/pdf", name: "Invoice.pdf", size: 1200, sha256: "abc")
        try expectEqual(ref, attachedRef)
        try expectEqual(upload, AttachmentUpload(url: URL(string: "https://storage.example/put/att_1")!, method: "PUT", headers: ["Content-Type": "application/pdf"]))
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "POST /v1/tafs/taf%201/attachments")
        let body = json(transport.sent[0].body)
        try expectEqual(body["media_type"] as? String, "application/pdf")
        try expectEqual(body["name"] as? String, "Invoice.pdf")
        try expectEqual(body["size"] as? Int, 1200)
        try expectEqual(body["sha256"] as? String, "abc")
        try expectEqual(transport.sent[0].headers["Authorization"], "Bearer tok")
    }),
    Test("a file tafs cloud refuses says its words, and an answer that doesn't read is unreadable", awaiting: {
        let (client, _) = cloud([(413, #"{"error":"Invoice.pdf is 30.0 MB; the most is 25.0 MB."}"#), (201, #"{"attachment":{}}"#)])
        do {
            _ = try await client.attach("t", mediaType: "application/pdf", name: "Invoice.pdf", size: 31_457_280, sha256: "abc")
            throw Failure(description: "taken")
        } catch let refusal as CloudRefusal {
            try expectEqual(refusal.status, 413)
            try expectEqual(refusal.why(words), "Invoice.pdf is 30.0 MB; the most is 25.0 MB.")
        }
        do {
            _ = try await client.attach("t", mediaType: "application/pdf", name: "a.pdf", size: 1, sha256: "abc")
            throw Failure(description: "read")
        } catch let error as KIFFError {
            try expectEqual(error, .unreadable)
        }
    }),
    Test("a file is opened from where tafs cloud says, by its id, escaped", awaiting: {
        let (client, transport) = cloud([(200, #"{"url":"https://storage.example/get/att_1"}"#)])
        let url = try await client.attachmentURL("taf-1", file: "att/1")
        try expectEqual(url, URL(string: "https://storage.example/get/att_1"))
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "GET /v1/tafs/taf-1/attachments/att%2F1")
    }),
    Test("a message carries its files by id, and with files it may have no words; without files, none is left out", awaiting: {
        let (client, transport) = cloud([(200, sentAnswer), (200, sentAnswer)])
        _ = try await client.send("  ", to: "taf-coach", files: [attachedRef])
        let body = json(transport.sent[0].body)
        try expectEqual(body["text"] as? String, "")
        try expectEqual(body["attachments"] as? [String], ["att_1"])
        _ = try await client.send("Hi", to: "taf-coach")
        try expectEqual(json(transport.sent[1].body)["attachments"] == nil, true)
        try expectEqual(Outgoing.text(" ", files: [attachedRef]), "")
        try expectEqual(Outgoing.text(" ", files: []), nil)
        try expectEqual(Outgoing.text(String(repeating: "a", count: 2001), files: [attachedRef]), nil)
        let stream = client.streamRequest("", to: "taf-coach", files: [attachedRef])
        try expectEqual(stream.map { json($0.body)["attachments"] as? [String] } ?? nil, ["att_1"])
    }),
    Test("a message's files are read whole from the thread, as the iPad's: one that doesn't read leaves none") {
        let page = #"""
        {"items":[
         {"type":"message","message":{"id":"m1","from":"owner","text":"","attachments":[{"id":"att_1","kind":"pdf","media_type":"application/pdf","name":"Invoice.pdf","size":1200}]}},
         {"type":"message","message":{"id":"m2","from":"owner","text":"Hi","attachments":[{"id":"att_2"}]}},
         {"type":"message","message":{"id":"m3","from":"taf","text":"Read."}}
        ]}
        """#
        let read = try JSONDecoder().decode(Thread.Page.self, from: Data(page.utf8))
        let messages = read.items.compactMap { item -> Thread.Message? in if case .message(let m, _) = item { return m } else { return nil } }
        try expectEqual(messages.map(\.attachments), [[attachedRef], [], []])
    },
    Test("the files for the next message: only ready ones go, failed ones stay, and a message that didn't go puts them back first") {
        var files = ChatFiles()
        let a = PendingFile(id: UUID(), name: "a.pdf", mediaType: "application/pdf", thumbnail: nil, state: .ready(attachedRef))
        let b = PendingFile(id: UUID(), name: "b.pdf", mediaType: "application/pdf", thumbnail: nil, state: .failed("No."))
        let c = PendingFile(id: UUID(), name: "c.pdf", mediaType: "application/pdf", thumbnail: nil, state: .uploading)
        files.add(a)
        files.add(b)
        files.add(c)
        // A file still going up holds Send; ready files hold it while the chat works.
        try expectEqual(files.holdsSend(working: false), true)
        files.set(c.id, .failed("Gone."))
        try expectEqual(files.holdsSend(working: false), false)
        try expectEqual(files.holdsSend(working: true), true)
        let taken = files.take()
        try expectEqual(taken.map(\.name), ["a.pdf"])
        try expectEqual(files.files.map(\.name), ["b.pdf", "c.pdf"])
        files.putBack(taken)
        try expectEqual(files.files.map(\.name), ["a.pdf", "b.pdf", "c.pdf"])
        files.remove(b.id)
        try expectEqual(files.count, 2)
    },
]

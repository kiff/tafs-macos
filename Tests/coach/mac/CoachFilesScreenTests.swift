import AppKit
import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let before = #"{"working":false,"items":[{"type":"message","message":{"id":"m1","from":"taf","text":"What should your taf do?"}}]}"#

/// Storage, stood in: what was put, and a failure when asked for one.
private final class Storage: FileStore, @unchecked Sendable {
    var kept: [(Data, AttachmentUpload)] = []
    var fails = false
    var whilePutting: () async -> Void = {}
    func put(_ data: Data, to upload: AttachmentUpload) async throws {
        await whilePutting()
        if fails { throw FileProblem(message: Words.app("error.file_not_uploaded")) }
        kept.append((data, upload))
    }
    func get(_ url: URL) async throws -> Data { Data("%PDF".utf8) }
}

@MainActor
private func coach(_ answers: [(Int, String)], storage: Storage = Storage()) async -> (CoachModel, CannedTransport, Storage) {
    let transport = CannedTransport([(200, setupAnswer), (200, noChats), (200, before)] + answers)
    let chat = CoachModel(cloud: CloudClient(transport: transport, session: session), sleep: { _ in }, store: storage)
    await chat.load()
    return (chat, transport, storage)
}

private let pdf = PreparedFile(name: "Invoice.pdf", mediaType: "application/pdf", data: Data("%PDF-1.4".utf8), thumbnail: nil)
private let declared = #"{"attachment":{"id":"att_1","kind":"pdf","media_type":"application/pdf","name":"Invoice.pdf","size":8},"upload":{"url":"https://storage.example/put/att_1","method":"PUT","headers":{"Content-Type":"application/pdf"}}}"#

let coachFilesMacTests: [Test] = [
    Test("a file picked is declared to Coach's taf with its hash, its bytes go to storage, and it's ready, as the iPad's attach", awaiting: { @MainActor in
        let (chat, transport, storage) = await coach([(201, declared)])
        try expectEqual(chat.filesTarget, "taf-coach")
        await chat.attach(pdf)
        try expectEqual(transport.sent.last?.path, "/v1/tafs/taf-coach/attachments")
        let body = (try JSONSerialization.jsonObject(with: transport.sent.last!.body) as? [String: Any]) ?? [:]
        try expectEqual(body["sha256"] as? String, FilePrep.sha256(pdf.data))
        try expectEqual(storage.kept.map { $0.0 }, [pdf.data])
        try expectEqual(storage.kept.first?.1.url.absoluteString, "https://storage.example/put/att_1")
        try expectEqual(chat.files.files.map(\.ref?.id), ["att_1"])
        try expectEqual(chat.canSend, true)
    }),
    Test("a file that didn't upload says why on its chip and isn't sent; a sixth file says a message carries five", awaiting: { @MainActor in
        let storage = Storage()
        storage.fails = true
        let (chat, _, _) = await coach([(201, declared)], storage: storage)
        await chat.attach(pdf)
        try expectEqual(chat.files.files.map(\.state), [.failed("The file didn't upload. Try attaching it again.")])
        try expectEqual(chat.canSend, false)
        storage.fails = false
        let (full, _, _) = await coach(Array(repeating: (201, declared), count: 5))
        for _ in 0..<5 { await full.attach(pdf) }
        await full.attach(pdf)
        try expectEqual(full.files.count, 5)
        try expectEqual(full.fileNotice, "A message carries at most 5 files.")
    }),
    Test("Send takes the ready files with the words, as a message of its own; one that didn't go puts them back with why", awaiting: { @MainActor in
        let (chat, transport, _) = await coach([(201, declared), (200, sentAnswer), (200, before)])
        await chat.attach(pdf)
        chat.draft = "Here it is"
        await chat.send()
        let sent = transport.sent.first { $0.path == "/v1/tafs/taf-coach/messages" }
        let body = sent.flatMap { try? JSONSerialization.jsonObject(with: $0.body) as? [String: Any] } ?? [:]
        try expectEqual(body["attachments"] as? [String], ["att_1"])
        try expectEqual(body["text"] as? String, "Here it is")
        try expectEqual(chat.files.isEmpty, true)
        // Refused: the words and the files go back to the composer, and the tray says why.
        let (failing, _, _) = await coach([(201, declared), (500, #"{"error":"Coach couldn't take it."}"#)])
        await failing.attach(pdf)
        failing.draft = "Here it is"
        await failing.send()
        try expectEqual(failing.draft, "Here it is")
        try expectEqual(failing.files.files.map(\.ref?.id), ["att_1"])
        try expectEqual(failing.fileNotice, "Coach couldn't take it.")
        try expectEqual(failing.pending, nil)
    }),
    Test("a file going up when the session ends is dropped, and the files go with the session", awaiting: { @MainActor in
        let storage = Storage()
        let (chat, _, _) = await coach([(201, declared)], storage: storage)
        storage.whilePutting = { await chat.signedOut() }
        await chat.attach(pdf)
        try expectEqual(chat.files.isEmpty, true)
        try expectEqual(FileManager.default.fileExists(atPath: CoachModel.openedFiles.path), false)
    }),
    Test("a file in the thread opens from a copy under its own name, which sign-out removes", awaiting: { @MainActor in
        let (chat, transport, _) = await coach([(200, #"{"url":"https://storage.example/get/att_1"}"#)])
        let ref = AttachmentRef(id: "att_1", kind: "pdf", mediaType: "application/pdf", name: "Invoice.pdf", size: 4)
        let url = await chat.openFile(ref)
        try expectEqual(transport.sent.last?.path, "/v1/tafs/taf-coach/attachments/att_1")
        try expectEqual(url?.lastPathComponent, "Invoice.pdf")
        try expectEqual(url.flatMap { try? Data(contentsOf: $0) }, Data("%PDF".utf8))
        chat.signedOut()
        try expectEqual(url.map { FileManager.default.fileExists(atPath: $0.path) }, false)
    }),
    Test("a new conversation that improves a taf takes no files, as the iPad's filesTarget", awaiting: { @MainActor in
        let (chat, transport, _) = await coach([])
        chat.improve(CoachModel.Improving(id: "taf-9", name: "Refunds"))
        try expectEqual(chat.filesTarget, nil)
        let sent = transport.sent.count
        await chat.attach(pdf)
        try expectEqual(transport.sent.count, sent)
        try expectEqual(chat.files.isEmpty, true)
    }),
    Test("the screenshot: the paperclip, and a tray with a file ready and one that didn't upload", awaiting: { @MainActor in
        let storage = Storage()
        let (chat, _, _) = await coach([(201, declared), (201, declared)], storage: storage)
        await chat.attach(pdf)
        storage.fails = true
        await chat.attach(PreparedFile(name: "Receipt.jpg", mediaType: "image/jpeg", data: Data([1, 2, 3]), thumbnail: nil))
        let view = CoachView(model: chat).environment(\.words, Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"]))
        guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 600)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: "build/screenshots"), withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: "build/screenshots/coach-attach-en.png"))
    }),
]

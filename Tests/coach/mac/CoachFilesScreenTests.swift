import AppKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

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

/// tafs cloud, as canned, which does something once a request's answer is in: the person
/// signing out while it was on its way.
private final class Hooked: Transport, @unchecked Sendable {
    let canned: CannedTransport
    var after: (String) async -> Void = { _ in }
    init(_ canned: CannedTransport) { self.canned = canned }
    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        let answer = try await canned.send(request)
        await after(request.path)
        return answer
    }
}

@MainActor
private func coach(_ answers: [(Int, String)], storage: Storage = Storage(), hooked: Hooked? = nil) async -> (CoachModel, CannedTransport, Storage) {
    let transport = CannedTransport([(200, setupAnswer), (200, noChats), (200, before)] + answers)
    let sending: Transport = hooked.map { _ in Hooked(transport) } ?? transport
    let chat = CoachModel(cloud: CloudClient(transport: sending, session: session), sleep: { _ in }, store: storage)
    if let hooked, let made = sending as? Hooked { made.after = { path in await hooked.after(path) } }
    await chat.load()
    return (chat, transport, storage)
}

/// A JPEG `width` × `height` as stored, with its EXIF orientation: 6 is turned a quarter right.
private func orientedJPEG(width: Int, height: Int, orientation: Int) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
    CGImageDestinationFinalize(destination)
    return data as Data
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
    Test("a version's trial chat takes no files, as the iPad's filesTarget (trialChats), and its paperclip isn't offered", awaiting: { @MainActor in
        let (chat, transport, _) = await coach([])
        try expectEqual(chat.filesTarget, "taf-coach")
        chat.trial = true
        try expectEqual(chat.filesTarget, nil)
        let sent = transport.sent.count
        await chat.attach(pdf)
        try expectEqual(transport.sent.count, sent)
        try expectEqual(chat.files.isEmpty, true)
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
    Test("a photo turned by its EXIF orientation goes up turned, as the iPad's UIImage draws it, and no larger than its long edge") {
        let say = Words.app
        let stored = orientedJPEG(width: 400, height: 200, orientation: 6)
        let prepared = try FilePrep.photo(stored, name: "Portrait.jpg", say: say)
        guard let source = CGImageSourceCreateWithData(prepared.data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure(description: "no JPEG") }
        try expectEqual([image.width, image.height], [200, 400])
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        try expectEqual((properties?[kCGImagePropertyOrientation] as? Int) ?? 1, 1)
        let huge = try FilePrep.photo(orientedJPEG(width: 3000, height: 1000, orientation: 1), name: "Wide.jpg", say: say)
        let read = CGImageSourceCreateWithData(huge.data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        try expectEqual(read.map { max($0.width, $0.height) }, FilePrep.longEdge)
    },
    Test("files never go into an improvement's first message: its words go alone, the files wait in the tray, and the box says so", awaiting: { @MainActor in
        // tafs cloud's improve route answers no message id: the sent message is found by its words.
        let improved = #"{"setup":"taf-coach","session":"s1","new_session":true}"#
        let arrived = #"{"working":false,"items":[{"type":"message","message":{"id":"s1.in","at":"2026-11-14T18:00:02Z","from":"owner","text":"Make it faster"}}]}"#
        let (chat, transport, _) = await coach([(201, declared), (200, improved), (200, arrived)])
        await chat.attach(pdf)
        chat.improve(CoachModel.Improving(id: "taf-9", name: "Refunds"))
        chat.draft = "Make it faster"
        try expectEqual(chat.improvementHoldsFiles, true)
        try expectEqual(chat.canSend, true)
        await chat.send()
        let sent = transport.sent.first { $0.path == "/v1/tafs/taf-9/improve" }
        try expectEqual(sent.flatMap { try? JSONDecoder().decode([String: String].self, from: $0.body) }, ["text": "Make it faster"])
        try expectEqual(chat.files.files.map(\.ref?.id), ["att_1"])
        try expectEqual(chat.improvementHoldsFiles, false)
    }),
    Test("Allow after a refusal for the consent, with files: it allows, closes, and the words and files wait to send again", awaiting: { @MainActor in
        let (chat, transport, _) = await coach([(201, declared), (403, consentRefusal), (204, "")])
        await chat.attach(pdf)
        chat.draft = "Here it is"
        await chat.send()
        try expectEqual(chat.consent?.version, "3")
        await chat.allowAI()
        try expectEqual(transport.sent.last?.path, "/v1/me/ai-consent")
        try expectEqual(chat.consent, nil)
        try expectEqual(chat.draft, "Here it is")
        try expectEqual(chat.files.files.map(\.ref?.id), ["att_1"])
        try expectEqual(chat.canSend, true)
    }),
    Test("a session that ends while a file is declared puts no bytes up, and one that ends while a file is read opens nothing", awaiting: { @MainActor in
        let hooked = Hooked(CannedTransport([]))
        let storage = Storage()
        let (chat, _, _) = await coach([(201, declared)], storage: storage, hooked: hooked)
        hooked.after = { path in if path.hasSuffix("/attachments") { await chat.signedOut() } }
        await chat.attach(pdf)
        try expectEqual(storage.kept.count, 0)
        try expectEqual(chat.files.isEmpty, true)
        let reading = Hooked(CannedTransport([]))
        let (opener, _, _) = await coach([(200, #"{"url":"https://storage.example/get/att_1"}"#)], hooked: reading)
        reading.after = { path in if path.contains("/attachments/") { await opener.signedOut() } }
        let ref = AttachmentRef(id: "att_1", kind: "pdf", mediaType: "application/pdf", name: "Invoice.pdf", size: 4)
        let url = await opener.openFile(ref)
        try expectEqual(url, nil)
        try expectEqual(FileManager.default.fileExists(atPath: CoachModel.openedFiles.appendingPathComponent("att_1").path), false)
        try expectEqual(opener.fileNotice, nil)
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

import Foundation

/// A file the person attached to a message, as the thread names it: never its bytes. As the
/// iPad's `TafsCloud.AttachmentRef` (TafsCloud.swift:1059-1067).
struct AttachmentRef: Codable, Equatable, Hashable, Identifiable {
    let id: String
    /// How the model reads it: "image", "pdf", "text", "word" or "excel".
    let kind: String
    let mediaType: String
    let name: String
    let size: Int
    enum CodingKeys: String, CodingKey { case id, kind, name, size, mediaType = "media_type" }
}

/// Where a file's bytes go: a request to `url` with `headers`, sent as given, straight to
/// storage, never through tafs cloud. It works for a few minutes. As the iPad's `Upload`.
struct AttachmentUpload: Decodable, Equatable {
    let url: URL
    let method: String
    let headers: [String: String]
}

/// A file the person picked for their next message, while it goes up, as the iPad's
/// `PendingFile` (Attachments.swift:8-25). It's sent with the message once it's `ready`; a file
/// that failed says why.
struct PendingFile: Identifiable, Equatable {
    enum State: Equatable {
        case uploading
        case ready(AttachmentRef)
        case failed(String)
    }
    let id: UUID
    let name: String
    let mediaType: String
    /// A small JPEG for the tray: a photo's, else nil.
    let thumbnail: Data?
    var state: State

    var ref: AttachmentRef? {
        if case .ready(let ref) = state { return ref }
        return nil
    }
}

/// A file made ready to attach: its bytes as tafs sends them, its media type and its name.
struct PreparedFile: Equatable {
    let name: String
    let mediaType: String
    let data: Data
    let thumbnail: Data?
}

/// A file that can't be attached, in words the person reads.
struct FileProblem: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

/// What a person may attach, as the iPad's `FilePrep` (Attachments.swift:43-115): the same
/// types and limits kiff/agents keeps, checked here first so a file over its limit is refused
/// before upload. Reading a file's type and making a photo a JPEG are the Mac's own
/// (`FilePrep+Mac`), since they need AppKit.
enum FilePrep {
    static let perMessage = 5
    /// A photo's long edge, at most: the most the model reads.
    static let longEdge = 2576

    private static let mb = 1 << 20
    /// The media types tafs takes, with the most each may weigh.
    static let limits: [String: Int] = [
        "image/jpeg": 10 * mb, "image/png": 10 * mb, "image/gif": 10 * mb, "image/webp": 10 * mb,
        "application/pdf": 25 * mb,
        "text/plain": 2 * mb, "text/csv": 2 * mb, "text/markdown": 2 * mb,
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document": 2 * mb,
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": 2 * mb,
    ]
    /// The most any file weighs: over it, a file that isn't a photo is refused before it's read.
    static let largest = 25 * mb

    /// Refuses a file over its type's limit, saying which, as the iPad's `check`.
    static func check(name: String, size: Int, mediaType: String, say: Words) throws {
        guard let limit = limits[mediaType] else {
            throw FileProblem(message: say("attachment.cant_attach", ["name": name]))
        }
        if size > limit {
            throw FileProblem(message: say("attachment.too_large", ["name": name, "size": megabytes(size), "limit": megabytes(limit)]))
        }
    }

    static func megabytes(_ n: Int) -> String {
        String(format: "%.1f MB", Double(n) / Double(1 << 20))
    }

    /// A file's name for its photo: the name without its extension, else `photo`, then `.jpg`.
    static func photoName(_ name: String, photo: String) -> String {
        let base = (name as NSString).deletingPathExtension
        return (base.isEmpty ? photo : base) + ".jpg"
    }

    /// Where a file's picture is: a photo's thumbnail, else a symbol for its kind, as the iPad's
    /// `FileIcon.symbol`.
    static func symbol(_ mediaType: String) -> String {
        switch mediaType {
        case _ where mediaType.hasPrefix("image/"): return "photo"
        case "application/pdf": return "doc.richtext"
        case "text/csv", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": return "tablecells"
        default: return "doc.text"
        }
    }
}

/// The chat's files for its next message, as the iPad's `chatFiles` and its helpers
/// (AppModel.swift:4742-4805): the ones going up, ready or failed, in the order picked.
struct ChatFiles: Equatable {
    private(set) var files: [PendingFile] = []

    var isEmpty: Bool { files.isEmpty }
    var count: Int { files.count }
    /// Whether any is still going up: a message waits for the ones still going.
    var uploading: Bool { files.contains { $0.state == .uploading } }
    var hasReady: Bool { files.contains { $0.ref != nil } }

    mutating func add(_ file: PendingFile) { files.append(file) }

    mutating func set(_ id: UUID, _ state: PendingFile.State) {
        guard let i = files.firstIndex(where: { $0.id == id }) else { return }
        files[i].state = state
    }

    mutating func remove(_ id: UUID) { files.removeAll { $0.id == id } }

    /// Whether Send waits, as the iPad's `holdsSend`: while any file is still going up, words or
    /// not, so a message never goes without a file just attached; and while files are ready but
    /// the chat is at work, since files go with a message of their own, never into a run.
    func holdsSend(working: Bool) -> Bool { uploading || (working && hasReady) }

    /// Whether an improvement holds these files back, as the iPad's `improvementHoldsFiles`: its
    /// first message carries none, so the words go alone and the files wait for the next one.
    func heldBy(improving: Bool) -> Bool { improving && !isEmpty }

    /// Send's words for VoiceOver, as the iPad's composer (SetupChatView.swift:781): once the files
    /// are up while one still goes up and holds it; when the answer is done while the chat works;
    /// else Send. Files an improvement holds back hold nothing.
    func sendKey(working: Bool, improving: Bool) -> String {
        let held = !heldBy(improving: improving) && holdsSend(working: working)
        if held && uploading { return "chat.send_once_files_up" }
        return working ? "coach.send_when_answer_done" : "common.send"
    }

    /// The ready files, taken for the message being sent. Ones that failed stay.
    mutating func take() -> [PendingFile] {
        let ready = files.filter { $0.ref != nil }
        files = files.filter { $0.ref == nil }
        return ready
    }

    /// Puts back files a message didn't take, ahead of any picked since.
    mutating func putBack(_ taken: [PendingFile]) {
        guard !taken.isEmpty else { return }
        files = taken + files
    }
}

extension CloudClient {
    /// Declares a file the person will attach to a message in their chat with the taf (or
    /// Coach), as the iPad's `attach`: tafs cloud answers where to upload it. A file over its
    /// limit is refused here, before any upload, and the refusal says which limit.
    func attach(_ id: String, mediaType: String, name: String, size: Int, sha256: String) async throws -> (AttachmentRef, AttachmentUpload) {
        struct Body: Encodable {
            let mediaType: String, name: String, size: Int, sha256: String
            enum CodingKeys: String, CodingKey { case name, size, sha256, mediaType = "media_type" }
        }
        struct Answer: Decodable { let attachment: AttachmentRef; let upload: AttachmentUpload }
        let body = try await post("/v1/tafs/\(Self.escaped(id))/attachments", body: Body(mediaType: mediaType, name: name, size: size, sha256: sha256))
        guard let answer = try? JSONDecoder().decode(Answer.self, from: body) else { throw KIFFError.unreadable }
        return (answer.attachment, answer.upload)
    }

    /// Where a file the person attached can be read, as the iPad's `attachment`: only their own;
    /// another's is a 404.
    func attachmentURL(_ id: String, file: String) async throws -> URL {
        struct Answer: Decodable { let url: URL }
        // An id of "." or ".." would fold into the path above it once the address is resolved: never sent.
        guard ![".", ".."].contains(id), ![".", ".."].contains(file) else { throw KIFFError.unreadable }
        let answer: Answer = try await get("/v1/tafs/\(Self.escaped(id))/attachments/\(Self.escaped(file))", saying: true)
        return answer.url
    }
}

/// Where a file's bytes go and come from: storage, with no session, as the iPad's `upload` and
/// the second half of `attachment`. The Mac's is `URLSession`'s; tests stand one in.
protocol FileStore {
    func put(_ data: Data, to upload: AttachmentUpload) async throws
    func get(_ url: URL) async throws -> Data
}

import AppKit
import SwiftUI

/// The account's files on screen, as the iPad's `FilesModel`: read, opened, saved and deleted. Nothing of a file is kept
/// on this Mac: its start is read when it opens, and its bytes only when Download asks, straight to where the person
/// picks, with no copy left anywhere else.
@MainActor
final class FilesModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded([DeliveredFile])
        case failed
    }

    /// What an open file draws above its buttons.
    enum PreviewRead: Equatable {
        /// tafs cloud's cleaned start, drawn as plain text.
        case text(FilePreviewText)
        /// No text start: a type tafs cloud gives none for, or one it answered without. Its details, Download and Delete
        /// stay. The Mac draws no system preview of the bytes, so no bytes are read to draw.
        case noPreview
        /// tafs cloud couldn't be reached for a type that has a text start: the "couldn't reach" line.
        case unreachable
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var previews: [String: PreviewRead] = [:]
    /// What the last Download or Delete now said, by the file it was for.
    @Published private(set) var notes: [String: String] = [:]
    @Published private(set) var deleting: Set<String> = []

    private let readAll: () async throws -> [DeliveredFile]
    private let readPreview: (String) async throws -> FilePreviewText?
    private let readDownload: (String) async throws -> URL
    private let deleteOne: (String) async throws -> Void
    /// Reads a download URL's bytes, with no token and no redirect (`FileBytes`).
    private let fetch: (URL) async throws -> Data

    init(readAll: @escaping () async throws -> [DeliveredFile], readPreview: @escaping (String) async throws -> FilePreviewText?,
         readDownload: @escaping (String) async throws -> URL, delete: @escaping (String) async throws -> Void,
         fetch: @escaping (URL) async throws -> Data = FileBytes.fetch) {
        self.readAll = readAll
        self.readPreview = readPreview
        self.readDownload = readDownload
        self.deleteOne = delete
        self.fetch = fetch
    }

    convenience init(cloud: CloudClient) {
        self.init(readAll: { try await cloud.allFiles() }, readPreview: { try await cloud.filePreview($0) },
                  readDownload: { try await cloud.fileDownload($0) }, delete: { try await cloud.deleteFile($0) })
    }

    /// The files, newest first; a failed read says so, and keeps nothing it had.
    func load() async {
        do {
            state = .loaded(FilesGrouping.newestFirst(try await readAll()))
        } catch {
            state = .failed
        }
    }

    /// The files of one taf, from what was read.
    func files(taf: String? = nil) -> [DeliveredFile] {
        guard case .loaded(let all) = state else { return [] }
        return all.filter { taf == nil || $0.tafID == taf }
    }

    /// A file's start, once per opening: tafs cloud's when it gives one. A text type it couldn't reach says so; any other
    /// type with no start draws none.
    func preview(_ file: DeliveredFile) async {
        guard previews[file.id] == nil else { return }
        let text = FileText.textTypes.contains(file.type.uppercased())
        do {
            previews[file.id] = try await readPreview(file.id).map(PreviewRead.text) ?? .noPreview
        } catch {
            previews[file.id] = text ? .unreachable : .noPreview
        }
    }

    /// The file left the screen: its start isn't kept.
    func close(_ file: DeliveredFile) {
        previews[file.id] = nil
        notes[file.id] = nil
    }

    /// Download: the file's own bytes, read only now, written straight to where the person picked. Nothing else is
    /// written anywhere.
    func download(_ file: DeliveredFile, to destination: URL) async {
        notes[file.id] = nil
        do {
            let data = try await fetch(try await readDownload(file.id))
            try data.write(to: destination, options: .atomic)
            notes[file.id] = Words.app("files.saved")
        } catch {
            notes[file.id] = NeedsYouModel.why(error)
        }
    }

    /// Delete now, for everyone: gone from the list only once tafs cloud has deleted it.
    func delete(_ file: DeliveredFile) async -> Bool {
        guard deleting.insert(file.id).inserted else { return false }
        defer { deleting.remove(file.id) }
        do {
            try await deleteOne(file.id)
        } catch {
            notes[file.id] = NeedsYouModel.why(error)
            return false
        }
        if case .loaded(let all) = state { state = .loaded(all.filter { $0.id != file.id }) }
        previews[file.id] = nil
        notes[file.id] = nil
        return true
    }
}

/// A download URL's bytes, read with no token, no cookie, no cache and no redirect: the URL alone, as tafs cloud gave it
/// for a minute (`FileDownload.url` checked it is https with no user in it).
enum FileBytes {
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }()

    static func fetch(_ url: URL) async throws -> Data {
        guard FileDownload.url(url.absoluteString) != nil else { throw KIFFError.unreadable }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw KIFFError.refused(status: (response as? HTTPURLResponse)?.statusCode ?? 0, code: "")
        }
        return data
    }
}

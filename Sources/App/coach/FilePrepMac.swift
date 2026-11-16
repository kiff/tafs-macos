import AppKit
import CryptoKit
import ImageIO
import Foundation
import UniformTypeIdentifiers

/// The Mac's half of `FilePrep`, as the iPad's `FilePrep` (Attachments.swift:58-140): a file's
/// kind, a photo made a JPEG, and a file's SHA-256. AppKit's image drawing in place of UIKit's.
extension FilePrep {
    /// The kinds of file the open panels offer.
    static var pickable: [UTType] {
        var types: [UTType] = [.pdf, .plainText, .commaSeparatedText, .image]
        for id in ["net.daringfireball.markdown", "org.openxmlformats.wordprocessingml.document", "org.openxmlformats.spreadsheetml.sheet"] {
            if let t = UTType(id) { types.append(t) }
        }
        return types
    }

    /// The media type tafs sends a file of `type` as; nil when it can't be attached.
    static func mediaType(_ type: UTType) -> String? {
        if type.conforms(to: .pdf) { return "application/pdf" }
        if type.conforms(to: .commaSeparatedText) { return "text/csv" }
        if let md = UTType("net.daringfireball.markdown"), type.conforms(to: md) { return "text/markdown" }
        if type.conforms(to: .plainText) { return "text/plain" }
        if let word = UTType("org.openxmlformats.wordprocessingml.document"), type.conforms(to: word) {
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        }
        if let excel = UTType("org.openxmlformats.spreadsheetml.sheet"), type.conforms(to: excel) {
            return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        }
        if type.conforms(to: .jpeg) { return "image/jpeg" }
        if type.conforms(to: .png) { return "image/png" }
        if type.conforms(to: .gif) { return "image/gif" }
        if type.conforms(to: .webP) { return "image/webp" }
        return nil
    }

    /// A file as it is: refused when it can't be attached or is over its limit. Every image is
    /// made a JPEG as a photo is, so it carries no location or other metadata, whatever its format.
    static func file(name: String, data: Data, type: UTType, say: Words) throws -> PreparedFile {
        if type.conforms(to: .image) {
            return try photo(data, name: name, say: say)
        }
        guard let mt = mediaType(type) else {
            throw FileProblem(message: say("attachment.wrong_kind", ["name": name]))
        }
        try check(name: name, size: data.count, mediaType: mt, say: say)
        return PreparedFile(name: name, mediaType: mt, data: data, thumbnail: nil)
    }

    /// A file from disk, as the iPad's `AttachButton.read`: one over every limit that isn't a
    /// photo is refused before it's read into memory.
    static func read(_ url: URL, say: Words) throws -> PreparedFile {
        // Read while its security scope is open, as the iPad's: free while the app isn't
        // sandboxed, and right if it ever is.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
        let size = values?.fileSize ?? 0
        let name = url.lastPathComponent
        if size > largest, !type.conforms(to: .image) {
            throw FileProblem(message: say("attachment.too_large", ["name": name, "size": megabytes(size), "limit": megabytes(largest)]))
        }
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw FileProblem(message: say("chat.file.unreadable")) }
        return try file(name: name, data: data, type: type, say: say)
    }

    /// A photo, any format this Mac reads: as a JPEG, its long edge at most 2576 px, with a small
    /// thumbnail for the tray.
    static func photo(_ data: Data, name: String, say: Words) throws -> PreparedFile {
        // Read with its orientation applied, as the iPad's `UIImage(data:)` draws it, and at most
        // the long edge's size, so a huge photo is never decoded whole.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longEdge,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw FileProblem(message: say("chat.attach.not_a_photo", ["name": name])) }
        guard let jpeg = Self.jpeg(scaled(image, to: longEdge), quality: 0.85) else {
            throw FileProblem(message: say("chat.attach.not_a_photo", ["name": name]))
        }
        let named = photoName(name, photo: say("attachment.photo"))
        try check(name: named, size: jpeg.count, mediaType: "image/jpeg", say: say)
        return PreparedFile(name: named, mediaType: "image/jpeg", data: jpeg, thumbnail: Self.jpeg(scaled(image, to: 160), quality: 0.7))
    }

    /// The image drawn again with its long edge at most `edge` pixels, on white: only its pixels
    /// are kept, and a transparent PNG isn't black as a JPEG.
    static func scaled(_ image: CGImage, to edge: Int) -> CGImage {
        let long = max(image.width, image.height)
        guard long > 0 else { return image }
        let ratio = min(1, Double(edge) / Double(long))
        let width = max(1, Int((Double(image.width) * ratio).rounded()))
        let height = max(1, Int((Double(image.height) * ratio).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// A file's SHA-256, in lowercase hex, as its upload is declared with.
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Storage, reached with no session: a file's bytes go up as `upload` says, and come back from
/// the address tafs cloud gives, as the iPad's `upload` and `attachment` (TafsCloud.swift:1091-1110).
struct URLSessionFileStore: FileStore {
    func put(_ data: Data, to upload: AttachmentUpload) async throws {
        var request = URLRequest(url: upload.url)
        request.httpMethod = upload.method
        request.timeoutInterval = 120
        for (name, value) in upload.headers { request.setValue(value, forHTTPHeaderField: name) }
        let (_, response) = try await URLSession.shared.upload(for: request, from: data)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw FileProblem(message: Words.app("error.file_not_uploaded")) }
    }

    func get(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw FileProblem(message: Words.app("chat.file.could_not_open")) }
        return data
    }
}

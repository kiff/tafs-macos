import Foundation

/// Files (tafs docs/files.md), as the iPad's `Files.swift` and `TafsCloud+Files.swift`: what the account's tafs delivered
/// in their runs, kept 30 days from the run and seen by everyone on the account. tafs cloud lists them (`/v1/files`), and
/// its own switch alone decides: a 404 draws nothing.
struct DeliveredFile: Identifiable, Hashable, Decodable {
    var id: String
    /// Its name, cleaned (`FileText.name`): one name, never a path.
    var name: String
    /// Its type, as its extension says it, upper case ("CSV"), else its media type's last part.
    var type: String
    var bytes: Int
    /// The taf that made it, by tafs cloud's id, and its name as tafs has it now ("" once the taf is gone).
    var tafID: String
    var tafName: String
    /// The run it came from, and when that run was.
    var runID: String
    var runAt: Date
    /// The chat the run answered in, for the files under that chat.
    var chat: String?
    /// When it goes away, as tafs cloud says: the app counts the days to it and never decides it.
    var goesAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, taf, run, chat, name, mediaType = "media_type", size, created, expires, tafName = "taf_name"
    }

    init(id: String, name: String, type: String, bytes: Int, tafID: String, tafName: String, runID: String, runAt: Date,
         chat: String? = nil, goesAt: Date) {
        self.id = id; self.name = name; self.type = type; self.bytes = bytes; self.tafID = tafID; self.tafName = tafName
        self.runID = runID; self.runAt = runAt; self.chat = chat; self.goesAt = goesAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        let raw = try c.decode(String.self, forKey: .name)
        name = FileText.name(raw, fallback: id)
        let ext = (raw as NSString).pathExtension
        let media = (try? c.decode(String.self, forKey: .mediaType)) ?? ""
        type = (ext.isEmpty ? (media.split(separator: "/").last.map(String.init) ?? "") : ext).uppercased()
        bytes = try c.decode(Int.self, forKey: .size)
        tafID = try c.decode(String.self, forKey: .taf)
        tafName = ((try? c.decodeIfPresent(String.self, forKey: .tafName)) ?? nil) ?? ""
        runID = try c.decode(String.self, forKey: .run)
        runAt = try c.decode(Date.self, forKey: .created)
        chat = (try? c.decodeIfPresent(String.self, forKey: .chat)) ?? nil
        goesAt = try c.decode(Date.self, forKey: .expires)
    }
}

/// A file's start as tafs cloud sends it: its first 4 KB as plain text, and whether there's more.
struct FilePreviewText: Equatable {
    var text: String
    var truncated: Bool
}

/// A file's name and its preview as the app draws them, as the iPad's `FileText` (qa-kiff's musts): plain text only,
/// never a path, and no control or direction character, even if tafs cloud's own cleaning ever let one through.
enum FileText {
    /// U+202A–U+202E (embeddings and overrides), U+2066–U+2069 (isolates), and the marks U+200E, U+200F and U+061C.
    static func isDirection(_ s: Unicode.Scalar) -> Bool {
        (0x202A...0x202E).contains(s.value) || (0x2066...0x2069).contains(s.value) || [0x200E, 0x200F, 0x061C].contains(s.value)
    }

    static func isControl(_ s: Unicode.Scalar) -> Bool { s.properties.generalCategory == .control }

    /// The name alone: what follows the last `/` or `\`, with control and direction characters taken out; `fallback` if
    /// nothing's left, or only "." or "..".
    static func name(_ raw: String, fallback: String) -> String {
        let last = raw.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        var kept = String.UnicodeScalarView()
        kept.append(contentsOf: last.unicodeScalars.filter { !isDirection($0) && !isControl($0) })
        let clean = String(kept).trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty || clean == "." || clean == ".." ? fallback : clean
    }

    /// A preview's text: lines and tabs kept, every other control or direction character taken out, Windows' line ends
    /// made one.
    static func preview(_ raw: String) -> String {
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var kept = String.UnicodeScalarView()
        kept.append(contentsOf: lines.unicodeScalars.filter { $0 == "\n" || $0 == "\t" || (!isDirection($0) && !isControl($0)) })
        return String(kept)
    }

    /// The types tafs cloud gives a text start for. Their bytes are never drawn on a failed read: that would show the raw
    /// file, which the cleaned start is there to avoid.
    static let textTypes: Set<String> = ["CSV", "MD", "TXT", "JSON"]
}

/// How the lists are drawn, as the iPad's `FilesGrouping`: in tafs cloud's facts, grouped and ordered, nothing else
/// worked out.
enum FilesGrouping {
    struct Group: Identifiable, Equatable {
        /// The day (`YYYY-MM-DD`), the taf's id or the run's id.
        var id: String
        var files: [DeliveredFile]
    }

    /// Newest first, under the day of their run in the account's zone.
    static func byDay(_ files: [DeliveredFile], zone: TimeZone) -> [Group] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        func day(_ date: Date) -> String {
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
        return grouped(newestFirst(files), by: { day($0.runAt) })
    }

    /// Each taf with its files, the taf with the newest run first.
    static func byTaf(_ files: [DeliveredFile]) -> [Group] { grouped(newestFirst(files), by: \.tafID) }

    /// Each run with its files, the newest run first.
    static func byRun(_ files: [DeliveredFile]) -> [Group] { grouped(newestFirst(files), by: \.runID) }

    /// Whole days left before it goes, never below none: 0 is today.
    static func daysLeft(_ file: DeliveredFile, now: Date) -> Int {
        max(0, Int((file.goesAt.timeIntervalSince(now) / 86_400).rounded(.down)))
    }

    /// When it goes, in the shared words: today, tomorrow, or in so many days.
    static func goes(_ days: Int, words: Words) -> String {
        switch days {
        case 0: return words("files.goes_today")
        case 1: return words("files.goes_tomorrow")
        default: return words.count("files.goes_in_days", days)
        }
    }

    static func newestFirst(_ files: [DeliveredFile]) -> [DeliveredFile] {
        // Stable for files of one run: the name breaks the tie, so the order never moves between reads.
        files.sorted { $0.runAt != $1.runAt ? $0.runAt > $1.runAt : $0.name < $1.name }
    }

    /// Groups in the order their first file comes, each keeping its files' order.
    private static func grouped(_ files: [DeliveredFile], by key: (DeliveredFile) -> String) -> [Group] {
        var order: [String] = []
        var groups: [String: [DeliveredFile]] = [:]
        for file in files {
            let k = key(file)
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(file)
        }
        return order.map { Group(id: $0, files: groups[$0] ?? []) }
    }
}

/// Where a file's bytes may be read from (tafs cloud's `/download`, a URL that lasts a minute), as Linux's
/// `read_download`: only `https`, with no user or password in it. It's read with no token and no redirect: the session
/// goes only to KIFF's and tafs cloud's own hosts.
enum FileDownload {
    static func url(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https", url.host?.isEmpty == false,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}

extension CloudClient {
    /// One page of the account's files, newest first, or one taf's; `after` reads the page after.
    func files(taf: String? = nil, after: String? = nil) async throws -> (files: [DeliveredFile], next: String?) {
        struct Page: Decodable {
            let files: [Lenient<DeliveredFile>]
            var next: String?
        }
        let query = [("taf", taf), ("after", after)].compactMap { key, value in value.map { "\(key)=\(Self.query($0))" } }
        let page: Page = try await get("/v1/files" + (query.isEmpty ? "" : "?" + query.joined(separator: "&")))
        return (page.files.compactMap(\.value), page.next)
    }

    /// Every file, at most `pages` pages of them (a month of an account's files, well past what a screen shows). A
    /// tafs cloud with Files off (404) has none.
    func allFiles(taf: String? = nil, pages: Int = 10) async throws -> [DeliveredFile] {
        var all: [DeliveredFile] = []
        var after: String?
        do {
            for _ in 0..<pages {
                let page = try await files(taf: taf, after: after)
                all += page.files
                guard let next = page.next else { break }
                after = next
            }
        } catch KIFFError.refused(status: 404, code: _) where all.isEmpty {
            return []
        }
        return all
    }

    /// One file's start as plain text, as tafs cloud cleaned it, cleaned again here; nil for a file with none.
    func filePreview(_ id: String) async throws -> FilePreviewText? {
        struct Read: Decodable {
            var preview: String?
            var preview_truncated: Bool?
        }
        let read: Read = try await get("/v1/files/\(Self.escaped(id))")
        return read.preview.map { FilePreviewText(text: FileText.preview($0), truncated: read.preview_truncated ?? false) }
    }

    /// Where a file's bytes can be read, for a minute: an https URL with no user in it, else unreadable.
    func fileDownload(_ id: String) async throws -> URL {
        struct Read: Decodable { let url: String }
        let read: Read = try await get("/v1/files/\(Self.escaped(id))/download")
        guard let url = FileDownload.url(read.url) else { throw KIFFError.unreadable }
        return url
    }

    /// Delete now, for everyone on the account.
    func deleteFile(_ id: String) async throws {
        _ = try await delete("/v1/files/\(Self.escaped(id))")
    }
}

/// One file read on its own: one that doesn't read is left out, never the page.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

import Foundation

/// What a taf remembers between its runs and chats, as the iPad's `TafsCloud.Note`
/// (`GET /v1/tafs/{id}/memory`): its notes, newest first, each drawn as sent.
enum TafMemory {
    struct Note: Decodable, Equatable, Identifiable {
        let id: String
        let path: String
        let content: String
        let updatedAt: Date

        enum CodingKeys: String, CodingKey { case id, path, content, updatedAt = "updated_at" }

        /// The note's name, from its path, as the iPad's `title`: "/customers/acme.md" reads
        /// "customers · acme".
        var title: String {
            path.split(separator: "/").map { $0.replacingOccurrences(of: ".md", with: "").replacingOccurrences(of: "-", with: " ") }
                .joined(separator: " · ")
        }

        /// The line under a note, as the iPad's: its name, then when it last changed.
        func byline(_ time: String) -> String { title + " · " + time }
    }

    /// The notes once one is forgotten, as the iPad's `forget`: it goes from the list at once.
    static func without(_ note: Note, in notes: [Note]) -> [Note] { notes.filter { $0.id != note.id } }

    /// The notes with one put back where it was, newest first, as the iPad's `putBack`: only that
    /// note, never one another Forget took away meanwhile.
    static func putting(_ note: Note, backInto notes: [Note]) -> [Note] {
        guard !notes.contains(where: { $0.id == note.id }) else { return notes }
        return (notes + [note]).sorted { $0.updatedAt > $1.updatedAt }
    }
}

extension CloudClient {
    /// A taf's notes: the latest few, or, with `all`, every one.
    func memory(of taf: String, all: Bool = false) async throws -> [TafMemory.Note] {
        struct Answer: Decodable { let notes: [TafMemory.Note] }
        let answer: Answer = try await get("/v1/tafs/\(Self.escaped(taf))/memory" + (all ? "?all=true" : ""), saying: true)
        return answer.notes
    }

    /// Forgets one note: the taf won't see it on its next run or chat. Unsigned, as the iPad's
    /// `forget(_:note:)`.
    func forget(note: String, of taf: String) async throws {
        struct Answer: Decodable { let forgotten: String }
        let request = HTTPRequest(method: "DELETE", path: "/v1/tafs/\(Self.escaped(taf))/memory/\(Self.escaped(note))", headers: [
            "Authorization": "Bearer \(session.accessToken)", "Accept": "application/json",
            "Accept-Language": language, "User-Agent": "tafs-macos",
        ])
        let (status, body) = try await transport.send(request)
        guard (200..<300).contains(status) else { throw CloudRefusal(status: status, body: body) }
        guard (try? JSONDecoder().decode(Answer.self, from: body)) != nil else { throw KIFFError.unreadable }
    }
}

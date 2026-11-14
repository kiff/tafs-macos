import Foundation

/// tafs cloud's routes for a signed-in person. tafs cloud finds, words and decides; the app
/// sends what is typed or tapped and draws the answer as sent.
struct CloudClient {
    /// tafs cloud's address. It takes the person's KIFF session.
    static let base = "https://cloud.tafs.kiff.dev"

    let transport: Transport
    let session: Session
    /// The language the app shows: tafs cloud writes its lines in it.
    var language = "en"

    /// Reads one route. A refusal throws tafs cloud's code; an answer that isn't the
    /// expected shape is unreadable, never an empty page.
    func get<Answer: Decodable>(_ path: String) async throws -> Answer {
        let request = HTTPRequest(method: "GET", path: path, headers: [
            "Authorization": "Bearer \(session.accessToken)", "Accept": "application/json",
            "Accept-Language": language, "User-Agent": "tafs-macos",
        ])
        let (status, body) = try await transport.send(request)
        guard (200..<300).contains(status) else { throw KIFFError(status: status, body: body) }
        guard let answer = try? AccountClient.decoder.decode(Answer.self, from: body) else { throw KIFFError.unreadable }
        return answer
    }

    /// A value as one part of a query: only letters and digits stay as they are.
    static func query(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }
}

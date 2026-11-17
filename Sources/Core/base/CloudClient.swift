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
    /// With `saying`, a refusal throws `CloudRefusal` instead, with tafs cloud's own words for
    /// the person, for a screen that says them (the iPad's `CloudError`, kiff/tafs#397).
    func get<Answer: Decodable>(_ path: String, saying: Bool = false, headers extra: [String: String] = [:]) async throws -> Answer {
        try decoded(try await read(path, saying: saying, headers: extra))
    }

    /// One route's answer as sent, refused as `get` refuses. `extra` headers go with it.
    func read(_ path: String, saying: Bool = false, headers extra: [String: String] = [:]) async throws -> Data {
        var headers = [
            "Authorization": "Bearer \(session.accessToken)", "Accept": "application/json",
            "Accept-Language": language, "User-Agent": "tafs-macos",
        ]
        headers.merge(extra) { _, new in new }
        let request = HTTPRequest(method: "GET", path: path, headers: headers)
        let (status, body) = try await transport.send(request)
        guard (200..<300).contains(status) else {
            if saying { throw CloudRefusal(status: status, body: body) }
            throw KIFFError(status: status, body: body)
        }
        return body
    }

    /// An answer in the expected shape; any other is unreadable, never an empty page.
    func decoded<Answer: Decodable>(_ body: Data) throws -> Answer {
        guard let answer = try? AccountClient.decoder.decode(Answer.self, from: body) else { throw KIFFError.unreadable }
        return answer
    }

    /// Sends one request that changes something, and answers its body. A refusal throws
    /// `CloudRefusal`, with tafs cloud's own words for the person when it sent some.
    func post(_ path: String, _ fields: [String: String]) async throws -> Data {
        try await post(path, body: fields)
    }

    /// The same, with any body that encodes. `extra` headers go with it.
    func post<Body: Encodable>(_ path: String, body fields: Body, headers extra: [String: String] = [:]) async throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var headers = [
            "Authorization": "Bearer \(session.accessToken)", "Accept": "application/json", "Content-Type": "application/json",
            "Accept-Language": language, "User-Agent": "tafs-macos",
        ]
        headers.merge(extra) { _, new in new }
        let request = HTTPRequest(method: "POST", path: path, headers: headers, body: try encoder.encode(fields))
        let (status, body) = try await transport.send(request)
        guard (200..<300).contains(status) else { throw CloudRefusal(status: status, body: body) }
        return body
    }

    /// A value as one part of a query: only letters and digits stay as they are.
    static func query(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    /// An id as one segment of a path, as the iPad's `escaped`: what a path allows stays as it
    /// is (`taf-1`, `a.b`, `x_y`, `me@acme`), and only `/` and what a path can't carry are
    /// escaped. tafs cloud matches the path as sent, so an id must reach it as written.
    static func escaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? value
    }
}

/// tafs cloud didn't do what was asked, as the iPad's `CloudError` (TafsCloud.swift:9-49): its
/// status, its `error`, its code, and its words for the person.
struct CloudRefusal: Error, Equatable {
    let status: Int
    /// tafs cloud's `error`, as sent; nil when it sent none.
    let error: String?
    let code: String?
    /// tafs cloud's line in the person's language, as sent; nil when it sent none.
    let words: String?
    /// The AI-data consent's words, when the refusal is for want of it.
    let consent: TafsCloud.AIConsent?

    init(status: Int, body: Data) {
        struct Body: Decodable { let words: String?; let error: String? }
        let refusal = TafsCloud.Refusal(status: status, body: body)
        let read = try? JSONDecoder().decode(Body.self, from: body)
        self.status = status
        error = read?.error
        code = refusal.code ?? read?.error
        words = read?.words
        consent = refusal.consent
    }

    /// What the person is told, as the iPad's `errorDescription`: tafs cloud's words, else its
    /// `error`, else the app's line for the status. Never the code on its own.
    func why(_ say: Words) -> String {
        words ?? error ?? say("error.cloud_answered", ["status": String(status)])
    }

    /// The person must allow AI use first, and the screen for it can be drawn.
    var needsConsent: Bool { code == TafsCloud.aiConsentRequired && consent?.drawable == true }
    /// Too many messages in a few minutes.
    var tooMany: Bool { status == 429 }
}

import Foundation

/// A step a taf handed its owner, as Home lists it (`your_steps`), as the iPad's
/// `TafsCloud.YourStep`. Every word is tafs cloud's, in the person's language.
struct YourStep: Decodable, Equatable, Identifiable {
    struct Taf: Decodable, Equatable { let id: String; var name = "" }
    /// `open` comes only with a vouched link.
    struct Words: Decodable, Equatable {
        var title = ""
        var done = ""
        var skip = ""
        var open: String?
        var line = ""

        init(title: String = "", done: String = "", skip: String = "", open: String? = nil, line: String = "") {
            self.title = title; self.done = done; self.skip = skip; self.open = open; self.line = line
        }
        enum CodingKeys: String, CodingKey { case title, done, skip, open, line }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
            done = (try? c.decodeIfPresent(String.self, forKey: .done)) ?? ""
            skip = (try? c.decodeIfPresent(String.self, forKey: .skip)) ?? ""
            open = (try? c.decodeIfPresent(String.self, forKey: .open)) ?? nil
            line = (try? c.decodeIfPresent(String.self, forKey: .line)) ?? ""
        }
    }

    /// KIFF's hand-off id: what the answer names and signs.
    let handoff: String
    var run = ""
    /// Home's steps name their taf; a taf's request view, already on its taf, doesn't.
    var taf: Taf?
    var what = ""
    var why = ""
    var link: String?
    var linkHost: String?
    var since = ""
    var expires = ""
    var words = Words()
    var id: String { handoff }

    enum CodingKeys: String, CodingKey { case handoff, run, taf, what, why, link, since, expires, words, linkHost = "link_host" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        handoff = try c.decode(String.self, forKey: .handoff)
        run = (try? c.decodeIfPresent(String.self, forKey: .run)) ?? ""
        taf = (try? c.decodeIfPresent(Taf.self, forKey: .taf)) ?? nil
        what = (try? c.decodeIfPresent(String.self, forKey: .what)) ?? ""
        why = (try? c.decodeIfPresent(String.self, forKey: .why)) ?? ""
        link = (try? c.decodeIfPresent(String.self, forKey: .link)) ?? nil
        linkHost = (try? c.decodeIfPresent(String.self, forKey: .linkHost)) ?? nil
        since = (try? c.decodeIfPresent(String.self, forKey: .since)) ?? ""
        expires = (try? c.decodeIfPresent(String.self, forKey: .expires)) ?? ""
        words = (try? c.decodeIfPresent(Words.self, forKey: .words)) ?? Words()
    }

    /// The vendor's page, only as tafs cloud vouched for it: an https link with its host apart
    /// and the button's words. The host is tafs cloud's, never parsed here, and must be the
    /// link's own, so the line under the button names where it really goes. Anything else is
    /// no button, only the words.
    var openLink: (url: URL, host: String, words: String)? {
        guard let link, let host = linkHost, !host.isEmpty, let words = words.open, !words.isEmpty,
              let url = URL(string: link), url.scheme?.lowercased() == "https",
              url.host?.lowercased() == host.lowercased() else { return nil }
        return (url, host, words)
    }
}

/// A step a taf handed its owner, as KIFF keeps it, as the iPad's `KIFFClient.Handoff`: its
/// `version` is what the Mac signs, and a `status` other than "waiting" means it was answered
/// or has ended.
struct Handoff: Decodable, Equatable {
    let id: String
    var version = 1
    var status = ""
    enum CodingKeys: String, CodingKey { case id, version, status }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? ""
    }
}

/// The time an answer or a planque proof is signed at, as the iPad's `SigningTime`: RFC 3339
/// with milliseconds, never the same twice in this app. planque and KIFF each refuse a signed
/// request they have already seen, and the time is part of what's signed.
enum SigningTime {
    private static let lock = NSLock()
    private static var last = Date.distantPast
    private static let format: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func next(now: Date = Date()) -> String {
        lock.lock()
        defer { lock.unlock() }
        let ms = (now.timeIntervalSince1970 * 1000).rounded(.down)
        let floor = (last.timeIntervalSince1970 * 1000).rounded(.down) + 1
        last = Date(timeIntervalSince1970: max(ms, floor) / 1000)
        return format.string(from: last)
    }
}

extension KIFFMessage {
    /// What the device key signs to answer a step, as the iPad's `handoffMessage`: `kiff.handoff.v1`.
    static func handoff(tenant: String, handoffID: String, answer: String, version: Int = 1, signedAt: String) -> String {
        ["kiff.handoff.v1", tenant, handoffID, answer, String(version), signedAt].joined(separator: "\n")
    }
}

/// KIFF didn't take a step's read or answer, as the iPad's `KIFFError.server`: its status, its
/// `error`, and its `reason`, which say why in a code the app turns into words.
struct StepRefusal: Error, Equatable {
    let status: Int
    let error: String?
    let reason: String?

    init(status: Int, body: Data) {
        struct Body: Decodable { let error: String?; let reason: String? }
        let read = try? JSONDecoder().decode(Body.self, from: body)
        self.status = status
        error = read?.error
        reason = read?.reason
    }

    /// The app's own line for what happened, by its status, as the iPad's `PlainError.words`:
    /// never KIFF's code.
    static func plainKey(status: Int) -> String {
        switch status {
        case 0: return "error.offline"
        case 401: return "error.youre_signed_out"
        case 403: return "error.not_allowed"
        case 409: return "error.changed"
        case 429: return "error.busy"
        case 500...599: return "error.down"
        default: return "error.ours"
        }
    }
}

extension AccountClient {
    /// The step as KIFF keeps it now.
    func handoff(_ id: String) async throws -> Handoff {
        try read(try await stepSend("GET", "/v1/me/handoffs/\(Self.pathPart(id))"))
    }

    /// Answers a step handed to the owner, "done" or "skipped", signed with the device key.
    /// It grants nothing, so no approval key is asked for; KIFF answers it once.
    func answerHandoff(_ id: String, answer: String, signedAt: String, signature: String) async throws {
        struct Signature: Encodable { let signed_at: String; let value: String }
        struct Body: Encodable { let answer: String; let signature: Signature }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(Body(answer: answer, signature: Signature(signed_at: signedAt, value: signature)))
        _ = try await stepSend("POST", "/v1/me/handoffs/\(Self.pathPart(id))/answer", body: body)
    }

    /// One request about a step, with the session; a refusal throws `StepRefusal`, with KIFF's
    /// `error` and `reason` both kept.
    private func stepSend(_ method: String, _ path: String, body: Data = Data()) async throws -> Data {
        var request = HTTPRequest(method: method, path: path, headers: [
            "Authorization": "Bearer \(session.accessToken)", "Accept": "application/json",
            "Accept-Language": language, "User-Agent": "tafs-macos",
        ], body: body)
        if !body.isEmpty { request.headers["Content-Type"] = "application/json" }
        let (status, answer) = try await transport.send(request)
        guard (200..<300).contains(status) else { throw StepRefusal(status: status, body: answer) }
        return answer
    }

    /// One part of a path: everything but what a path segment may hold is escaped, `/` too.
    static func pathPart(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

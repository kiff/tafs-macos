import Foundation

/// A taf's versions, like app builds (`GET /v1/tafs/{id}/versions`), ported from the iPad's
/// `TafsCloud.Version`, `TrialSummary`, `Switching` and `VersionsPanel`'s lines. Installing one
/// and trying one are signed by the phone, so on this Mac they're read, never changed.
enum TafVersions {
    /// One trial of a version that ended: when, how many calls, and how it ended.
    struct Trial: Decodable, Equatable {
        let started: Date
        let ended: Date
        /// installed, back, idle or replaced.
        let why: String
        let calls: Int
        let held: Int
        let refused: Int
    }

    struct Version: Decodable, Equatable, Identifiable {
        let n: Int
        /// What changed, in plain words.
        let note: String?
        /// Who made it: the owner's subject, or "setup".
        let by: String?
        /// Who made it, in tafs cloud's words ("By Coach mode", "By you").
        let byWords: String?
        let created: Date
        let live: Bool
        /// The KIFF draft whose confirmation brings its Card, while it isn't confirmed.
        let draft: String?
        let trials: [Trial]
        var id: Int { n }

        enum CodingKeys: String, CodingKey { case n, note, by, created, live, draft, trials, byWords = "by_words" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            n = try c.decode(Int.self, forKey: .n)
            note = try c.decodeIfPresent(String.self, forKey: .note)
            by = try c.decodeIfPresent(String.self, forKey: .by)
            byWords = try c.decodeIfPresent(String.self, forKey: .byWords)
            created = try c.decode(Date.self, forKey: .created)
            live = try c.decode(Bool.self, forKey: .live)
            draft = try c.decodeIfPresent(String.self, forKey: .draft)
            trials = try c.decodeIfPresent([Trial].self, forKey: .trials) ?? []
        }
    }

    /// A switch to version n under way: nothing of the taf runs until it ends.
    struct Switching: Decodable, Equatable {
        let n: Int
        /// The KIFF draft whose confirmation it waits for.
        let draft: String?
        let at: Date
    }

    struct State: Decodable, Equatable {
        let versions: [Version]
        let switching: Switching?
    }

    /// Under a version: who made it, when, and that it brings a new Card, as the iPad's `byline`.
    static func byline(_ v: Version, _ words: Words, when: (Date) -> String) -> String {
        [v.byWords, when(v.created), v.draft == nil ? nil : words("version.brings_new_card")].compactMap { $0 }.joined(separator: " · ")
    }

    /// One ended trial, in a line: "Tried 21 Oct · 3 calls, 1 held · went back", as `tried`.
    static func tried(_ t: Trial, _ words: Words, day: (Date) -> String) -> String {
        let counts = [words.count("version.tried.calls", t.calls),
                      t.held > 0 ? words.count("version.tried.held", t.held) : nil,
                      t.refused > 0 ? words.count("version.tried.refused", t.refused) : nil].compactMap { $0 }.joined(separator: ", ")
        let how: String
        switch t.why {
        case "installed": how = words("version.tried.installed")
        case "back": how = words("version.tried.went_back")
        case "idle": how = words("version.tried.ended_unused")
        default: how = words("version.tried.ended")
        }
        return [words("version.tried.on", ["date": day(t.started)]), counts, how].joined(separator: " · ")
    }

    /// The header's way in: "Version 3 · live", else "Versions".
    static func headerLine(_ versions: [Version]?, _ words: Words) -> String {
        guard let live = versions?.first(where: \.live) else { return words("version.title") }
        return words("version.live_number", ["version": String(live.n)])
    }
}

extension CloudClient {
    /// A taf's versions, oldest first, the live one marked, and a switch under way.
    func versions(of taf: String) async throws -> TafVersions.State {
        try await get("/v1/tafs/\(Self.escaped(taf))/versions")
    }

    /// Drops a switch under way, as the iPad's `cancelSwitch`: the live version runs again. It
    /// gives no authority, so it isn't signed.
    @discardableResult
    func cancelSwitch(of taf: String) async throws -> Bool {
        struct Answer: Decodable { let cancelled: Bool }
        let request = HTTPRequest(method: "DELETE", path: "/v1/tafs/\(Self.escaped(taf))/switching", headers: [
            "Authorization": "Bearer \(session.accessToken)", "Accept": "application/json",
            "Accept-Language": language, "User-Agent": "tafs-macos",
        ])
        let (status, body) = try await transport.send(request)
        guard (200..<300).contains(status) else { throw CloudRefusal(status: status, body: body) }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: body) else { throw KIFFError.unreadable }
        return answer.cancelled
    }
}

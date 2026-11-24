import Foundation

/// planque's digest on a connection's request, checked as the iPad's `PlanqueClient.grants`
/// (PlanqueClient.swift:356-391): the SHA-256 of what it covers, in RFC 8785 form (`JCS`), from the
/// answer as planque sent it, numbers as written. The approval card warns when it doesn't match:
/// what's shown isn't what the phone would sign.
enum GrantDigest {
    /// planque's list, by the key `ConnectionsSource` decodes it with: no source names the list in quotes (the routes'
    /// guard), so its name comes from this Decodable's own coding key.
    private struct Listed: Decodable {
        let grants: [Int]
        static var key: String { CodingKeys.grants.stringValue }
    }

    /// What a grant's digest covers, by its `digest_v`: none, the request; 2, its `lang`, the request and planque's
    /// `text` together, so the words the owner reads are covered too. Any other version covers nothing this app knows.
    static func covers(_ raw: JCS.Value) -> JCS.Value? {
        guard let request = raw["request"] else { return nil }
        switch raw["digest_v"] {
        case nil:
            return request
        case .number("2")?:
            guard let lang = raw["lang"], lang.string?.isEmpty == false, let text = raw["text"], text.string != nil else { return nil }
            return .object(["lang": lang, "request": request, "text": text])
        default:
            return nil
        }
    }

    /// Marks each grant read from `answer` (planque's list of grants, in its order, a grant that didn't read
    /// left as nil in its place) with whether its digest matches, and its request's profile. Each is paired with
    /// planque's entry at its own position, never looked up by id: two entries with one id would mark the second as
    /// matching from the first's bytes. An id that repeats, or a list of another length, pairs nothing, so none matches.
    static func check(_ grants: inout [AppConnections.Grant?], answer: Data, sha256: (Data) -> Data) {
        let raws = (try? JCS.parse(answer))?[Listed.key]?.array ?? []
        let ids = grants.compactMap { $0?.id }
        let paired = raws.count == grants.count && Set(ids).count == ids.count
        for i in grants.indices where grants[i] != nil {
            guard paired, raws[i]["id"]?.string == grants[i]?.id, let request = raws[i]["request"] else {
                grants[i]?.digestMatches = false
                continue
            }
            grants[i]?.profile = request["profile"]
            guard let covered = covers(raws[i]), let canonical = try? JCS.canonical(covered), let digest = grants[i]?.digest else {
                grants[i]?.digestMatches = false
                continue
            }
            grants[i]?.digestMatches = Encoding.hex(sha256(canonical)) == digest
        }
    }
}

/// KIFF's words for a connection's profile (`kiff.words.v1` or `kiff.words.v2`), as the iPad's `ProfileWords`
/// (ProfileWords.swift): what the owner reads before approving a connection. KIFF writes them, never Coach or the
/// app: each line's text is shown verbatim, in order. They're read with this person's session, for the profile in
/// the grant's request, and shown only when both digests check: the words are KIFF's render of exactly that profile.
struct ProfileWords: Equatable {
    struct Line: Equatable {
        /// The operation it's about; none for a line about the whole connection.
        let op: String?
        let kind: String
        let text: String
        /// What KIFF can't check for this connection (missing, probation, an unpinned vendor): shown in amber.
        var caution: Bool { ProfileWords.cautionKinds.contains(kind) }
    }

    /// The words this app reads: it asks for v2 (`?v=2`) and takes either, as the iPad and Android.
    static let versions: Set<String> = ["kiff.words.v1", "kiff.words.v2"]
    static let cautionKinds: Set<String> = ["missing", "probation", "unpinned"]
    static let path = "/v1/profiles/words?v=2"

    enum Failure: Error, Equatable {
        /// KIFF answered something that isn't words this app reads.
        case notWords
        /// The words are for another profile than the one shown.
        case otherProfile
        /// The words aren't the ones their digest names.
        case wordsChanged

        /// The line the card shows in the words' place, as the iPad's `errorDescription`.
        var key: String {
            switch self {
            case .notWords: return "connect.kiff_words_connection_could_not"
            case .otherProfile: return "connect.words_another_connection_than_one"
            case .wordsChanged: return "kiff.kiff_words_do_not_match"
            }
        }
    }

    let lines: [Line]
    let profileSHA256: String
    let wordsSHA256: String

    /// The hex SHA-256 of a JSON value's RFC 8785 form.
    static func digest(_ value: JCS.Value, sha256: (Data) -> Data) throws -> String {
        Encoding.hex(sha256(try JCS.canonical(value)))
    }

    /// KIFF's answer to `POST /v1/profiles/words?v=2`, checked against `profile`, the profile the owner is shown: its
    /// digest, the words' version and their own digest.
    static func checked(_ data: Data, profile: JCS.Value, sha256: (Data) -> Data) throws -> ProfileWords {
        guard let answer = try? JCS.parse(data), let words = answer["words"], let v = words["v"]?.string, versions.contains(v),
              let profileSHA = answer["profile_sha256"]?.string, let wordsSHA = answer["words_sha256"]?.string,
              let raw = words["lines"]?.array else { throw Failure.notWords }
        guard try digest(profile, sha256: sha256) == profileSHA else { throw Failure.otherProfile }
        guard try digest(words, sha256: sha256) == wordsSHA else { throw Failure.wordsChanged }
        let lines = try raw.map { line -> Line in
            guard let kind = line["kind"]?.string, let text = line["text"]?.string else { throw Failure.notWords }
            return Line(op: line["op"]?.string, kind: kind, text: text)
        }
        return ProfileWords(lines: lines, profileSHA256: profileSHA, wordsSHA256: wordsSHA)
    }
}

extension AccountClient {
    /// KIFF's words for `profile`, read with the session (`POST /v1/profiles/words?v=2`, the profile canonical), and
    /// checked (`ProfileWords.checked`) before anything is shown.
    func profileWords(for profile: JCS.Value, sha256: (Data) -> Data) async throws -> ProfileWords {
        let answer = try await send("POST", ProfileWords.path, body: try JCS.canonical(profile))
        return try ProfileWords.checked(answer, profile: profile, sha256: sha256)
    }
}

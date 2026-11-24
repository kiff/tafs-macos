import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "acme/1", subject: "u1", deviceID: nil)

private func hex(_ json: String) throws -> String { Encoding.hex(testSHA256(try JCS.canonical(try JCS.parse(Data(json.utf8))))) }

private let profile = #"{"v":"kiff.profile.v1","vendor":"qonto","ops":[{"op":"list_invoices","risk":"read"}]}"#
private let request = #"{"server":"mcp.qonto.com","agent":"a_refunds","tools":[],"profile":"# + profile + "}"

/// planque's grants with their digests: one over its request, one (`digest_v` 2) over its lang, request and text, one
/// whose digest is another's, and one of a version this app doesn't know.
private func answer() throws -> String {
    let v1 = try hex(request)
    let v2 = try hex(#"{"lang":"fr","request":"# + request + #","text":"Lire vos factures Qonto"}"#)
    return #"""
    {"grants":[
      {"id":"g1","status":"pending","text":"Read your Qonto invoices","terms":["list_invoices · qonto · pinned"],"digest":"\#(v1)","request":\#(request)},
      {"id":"g2","status":"pending","digest_v":2,"lang":"fr","text":"Lire vos factures Qonto","digest":"\#(v2)","request":\#(request)},
      {"id":"g3","status":"pending","text":"Read your Qonto invoices","digest":"\#(v2)","request":\#(request)},
      {"id":"g4","status":"pending","digest_v":3,"text":"x","digest":"\#(v1)","request":\#(request)}
    ]}
    """#
}

private func source(_ transport: CannedTransport, sha256: ((Data) -> Data)? = testSHA256) -> ConnectionsSource {
    ConnectionsSource(transport: transport, tenant: "acme/1", proof: { "proof" }, sha256: sha256)
}

private func words(profile p: String = profile, v: String = "kiff.words.v2", lines: String = #"[{"op":"list_invoices","kind":"read","text":"Reads your invoices"},{"kind":"unpinned","text":"Qonto isn't pinned"}]"#,
                   profileSHA: String? = nil, wordsSHA: String? = nil) throws -> String {
    let w = #"{"v":"\#(v)","lines":\#(lines)}"#
    return #"{"words":\#(w),"profile_sha256":"\#(try profileSHA ?? hex(p))","words_sha256":"\#(try wordsSHA ?? hex(w))"}"#
}

/// planque's own words on a connection's request, its digest, and KIFF's words for its profile: what the approval card
/// shows before the phone's Approve, read-only on this Mac.
let grantWordsTests: [Test] = [
    Test("a grant reads planque's words, its terms and its digest; empty terms are none") {
        let grant = try AccountClient.decoder.decode(AppConnections.Grant.self, from: Data(#"{"id":"g","status":"pending","text":"Read invoices","terms":[],"digest":"ab","request":{"agent":"a"}}"#.utf8))
        try expectEqual(grant.text, "Read invoices")
        try expectEqual(grant.terms, nil)
        try expectEqual(grant.digest, "ab")
        try expectEqual(grant.digestMatches, nil)
    },
    Test("each digest is checked against what it covers, as planque sent it", awaiting: {
        let grants = try await source(CannedTransport([(200, try answer())])).grants()
        try expectEqual(grants.map(\.id), ["g1", "g2", "g3", "g4"])
        try expectEqual(grants.map(\.digestMatches), [true, true, false, false])
        try expectEqual(grants[0].terms, ["list_invoices · qonto · pinned"])
        try expectEqual(grants[0].profile, try JCS.parse(Data(profile.utf8)))
    }),
    Test("without SHA-256 nothing is checked, and nothing is said to match or not", awaiting: {
        let grants = try await source(CannedTransport([(200, try answer())]), sha256: nil).grants()
        try expectEqual(grants.map(\.digestMatches), [nil, nil, nil, nil])
        try expectEqual(grants[0].profile, nil)
    }),
    Test("an id that repeats pairs nothing: none matches, never the second from the first's bytes", awaiting: {
        let twice = try answer().replacingOccurrences(of: #""id":"g2""#, with: #""id":"g1""#)
        let grants = try await source(CannedTransport([(200, twice)])).grants()
        try expect(grants.allSatisfy { $0.digestMatches == false }, "none matches")
    }),
    Test("a grant that doesn't read keeps the others in their places", awaiting: {
        let broken = try answer().replacingOccurrences(of: #"{"id":"g3","status":"pending","#, with: #"{"status":"pending","#)
        let grants = try await source(CannedTransport([(200, broken)])).grants()
        try expectEqual(grants.map(\.id), ["g1", "g2", "g4"])
        try expectEqual(grants.map(\.digestMatches), [true, true, false])
    }),
    Test("KIFF's words are shown only for exactly the profile shown, unchanged") {
        let p = try JCS.parse(Data(profile.utf8))
        let read = try ProfileWords.checked(Data(try words().utf8), profile: p, sha256: testSHA256)
        try expectEqual(read.lines.map(\.text), ["Reads your invoices", "Qonto isn't pinned"])
        try expectEqual(read.lines.map(\.caution), [false, true])
        try expectEqual(try? ProfileWords.checked(Data(try words(v: "kiff.words.v1").utf8), profile: p, sha256: testSHA256).lines.count, 2)
        func refused(_ body: String) -> ProfileWords.Failure? {
            do { _ = try ProfileWords.checked(Data(body.utf8), profile: p, sha256: testSHA256); return nil } catch { return error as? ProfileWords.Failure }
        }
        try expectEqual(refused(try words(profile: #"{"v":"kiff.profile.v1","vendor":"other"}"#)), .otherProfile)
        try expectEqual(refused(try words(wordsSHA: String(repeating: "0", count: 64))), .wordsChanged)
        try expectEqual(refused(try words(v: "kiff.words.v9")), .notWords)
        try expectEqual(refused(try words(lines: #"[{"kind":"read"}]"#)), .notWords)
        try expectEqual(refused("not json"), .notWords)
    },
    Test("KIFF's words are read with the session, for the profile in its canonical form", awaiting: {
        let transport = CannedTransport([(200, try words())])
        let p = try JCS.parse(Data(profile.utf8))
        let read = try await AccountClient(transport: transport, session: session, language: "fr").profileWords(for: p, sha256: testSHA256)
        try expectEqual(read.lines.count, 2)
        guard let sent = transport.sent.first else { throw Failure(description: "nothing sent") }
        try expectEqual(sent.method, "POST")
        try expectEqual(sent.path, "/v1/profiles/words?v=2")
        try expectEqual(sent.body, try JCS.canonical(p))
        try expectEqual(sent.headers["Authorization"], "Bearer tok")
    }),
    Test("the card's lines are shared words in every shipped language") {
        let folder = URL(fileURLWithPath: ".shared/app/strings")
        let keys = ["coach.kiff_counts_way", "coach.reading_kiff_words_short", "connect.request_does_not_match_what", "common.details",
                    ProfileWords.Failure.notWords.key, ProfileWords.Failure.otherProfile.key, ProfileWords.Failure.wordsChanged.key]
        for language in try Words.shipped(folder: folder) {
            let words = try Words(language: language, folder: folder)
            for key in keys { try expect(words(key) != key, "\(key) in \(language)") }
        }
    },
]

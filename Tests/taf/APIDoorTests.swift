import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

private let apiDoor = #"""
{"door":{"id":"d9","app":"api","kind":"api","label":"Acme ERP","open":false,"address":"/v1/doors/d9/work","proof":"proven","how":"by its key",
 "keys":[{"id":"k1","name":"Production","last4":"a1b2","made_at":"2026-11-20T09:00:00Z","last_used_at":"2026-11-22T10:00:00Z"},{"id":"k2","last4":"c3d4","made_at":"2026-11-21T09:00:00Z"}],
 "today":4,"limit":100,"resting":false,"last_request":{"status":"done","at":"2026-11-22T10:00:00Z","words":" Done "}}}
"""#

let tafAPIDoorTests: [Test] = [
    Test("an API door reads its keys' last four and times, and its last request in tafs cloud's words only") {
        struct Answer: Decodable { let door: TafDoors.Door }
        let door = try AccountClient.decoder.decode(Answer.self, from: Data(apiDoor.utf8)).door
        try expectEqual(door.keys.map(\.shownName), ["Production", "…c3d4"])
        try expectEqual(door.keys[0].lastUsedAt, "2026-11-22T10:00:00Z")
        try expectEqual(door.keys[1].lastUsedAt, nil)
        try expectEqual(door.lastRequest?.shownWords, "Done")
        let bare = try AccountClient.decoder.decode(TafDoors.Door.LastRequest.self, from: Data(#"{"status":"failed","at":"x","words":"  "}"#.utf8))
        try expectEqual(bare.shownWords, nil)
    },
    Test("an API door's Reopen, Revoke and Remove are the iPad's exact requests, signed on the key as a removal is") {
        let reopen = KeyAct.reopenAPIDoor(taf: "taf/1", door: "d9")
        try expectEqual(reopen.method + " " + reopen.path, "PATCH /v1/tafs/taf%2F1/doors/d9")
        try expectEqual(String(decoding: reopen.body, as: UTF8.self), #"{"open":true}"#)
        let revoke = KeyAct.revokeAPIDoorKey(taf: "t", door: "d9", key: "k/1")
        try expectEqual(revoke.method + " " + revoke.path, "DELETE /v1/tafs/t/doors/d9/keys/k%2F1")
        try expectEqual(revoke.body, Data())
        let remove = KeyAct.removeAPIDoor(taf: "t", door: "d9")
        try expectEqual(remove.method + " " + remove.path, "DELETE /v1/tafs/t/doors/d9")
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        try expectEqual(revoke.title(words, device: "Production"), "Revoke “Production”")
    },
    Test("tafs cloud gets the act's own request with the key's assertion, and its door when it answers one", awaiting: {
        let transport = CannedTransport([(200, apiDoor), (200, #"{"revoked":"k1"}"#), (403, #"{"error":"x","code":"critical_key_required"}"#)])
        let cloud = CloudClient(transport: transport, session: session)
        let reopened = try await cloud.signedDoorChange(.reopenAPIDoor(taf: "t", door: "d9"), assertion: "t=1,a=x")
        try expectEqual(reopened?.id, "d9")
        try expectEqual(transport.sent[0].headers[Passkeys.headerName], "t=1,a=x")
        try expectEqual(transport.sent[0].headers["Content-Type"], "application/json")
        try expectEqual(String(decoding: transport.sent[0].body, as: UTF8.self), #"{"open":true}"#)
        let revoked = try await cloud.signedDoorChange(.revokeAPIDoorKey(taf: "t", door: "d9", key: "k1"), assertion: "t=2,a=y")
        try expectEqual(revoked, nil)
        try expectEqual(transport.sent[1].headers["Content-Type"], nil)
        do { _ = try await cloud.signedDoorChange(.removeAPIDoor(taf: "t", door: "d9"), assertion: "t=3,a=z"); throw Failure(description: "taken") } catch is CloudRefusal {}
    }),
]

/// The API instructions (`APIInstructions`), as the iPad's `testAnAPIDoorsLinesNeverCarryTheKey`: the endpoint is whole
/// and only ever on tafs cloud's own host, over HTTPS; the example never holds a key.
let tafAPIInstructionsTests: [Test] = [
    Test("the endpoint is the door's address on tafs cloud, and the example reads the key from the caller's own secret") {
        try expectEqual(APIInstructions.endpoint("/v1/doors/api/door_ord7/requests"), "https://cloud.tafs.kiff.dev/v1/doors/api/door_ord7/requests")
        let example = APIInstructions.example(endpoint: APIInstructions.endpoint("/v1/doors/api/door_ord7/requests"))
        try expect(example.contains("$TAFS_API_KEY"), "the caller's own secret")
        try expect(example.contains("https://cloud.tafs.kiff.dev/v1/doors/api/door_ord7/requests"), "the endpoint")
        try expect(!example.contains("tafs_api_"), "never a key")
    },
    Test("the shared rule's exact cases: the path is kept only when plain, on tafs cloud's own address, never a query or fragment") {
        // The rule every app matches (`vectors/api-door-endpoint.json`'s `exact`, in kiff/tafs).
        let base = URL(string: "https://cloud.test")!
        for (address, shown) in [
            ("/v1/doors/api/door_ord7/requests", "https://cloud.test/v1/doors/api/door_ord7/requests"),
            ("v1/x", "https://cloud.test/v1/x"),
            ("https://cloud.test/v1/x", "https://cloud.test/v1/x"),
            ("https://CLOUD.test/v1/x", "https://cloud.test/v1/x"),
            ("http://cloud.test/v1/x", "https://cloud.test/v1/x"),
            ("https://cloud.test:8443/v1/x", "https://cloud.test/v1/x"),
            ("https://me@cloud.test/v1/x", "https://cloud.test/v1/x"),
            ("https://cloud.test.evil.example/v1/x", "https://cloud.test/v1/x"),
            ("https://evil.example/v1/x", "https://cloud.test/v1/x"),
            ("/v1/x?a=1", "https://cloud.test/v1/x"),
            ("/v1/x#top", "https://cloud.test/v1/x"),
            ("/v1/x$(id)", "https://cloud.test/"),
            ("/v1/x;id", "https://cloud.test/"),
            ("/v1/x&id", "https://cloud.test/"),
            ("/v1/x'id'", "https://cloud.test/"),
            ("/v1/x$IFS!*+,=", "https://cloud.test/"),
            ("/v1/x%20y", "https://cloud.test/"),
        ] {
            try expectEqual(APIInstructions.endpoint(address, base: base), shown)
        }
        try expectEqual(APIInstructions.endpoint("/v1/x", base: URL(string: CloudClient.base)!), "https://cloud.tafs.kiff.dev/v1/x")
        try expectEqual(APIInstructions.endpoint("$(id)"), "https://cloud.tafs.kiff.dev/")
    },
    Test("a hostile address always stays on tafs cloud's host, over HTTPS, with a plain path and no query or fragment") {
        let base = URL(string: "https://cloud.test")!
        for address in ["/v1/x`id`", "/v1/x$(curl$IFS-T$IFS~/.ssh/id_rsa$IFS//evil.example)", "foo:x@evil.example/v1/x",
                        "mailto:a@evil.example", "//evil.example/v1/x", "\\\\evil.example\\x", "/v1/x y", "/v1/x\nid",
                        "javascript:alert(1)", "", "@evil.example/x", "https://evil.example@cloud.test.evil.example/"] {
            let shown = APIInstructions.endpoint(address, base: base)
            guard let url = URLComponents(string: shown) else { throw Failure(description: "\(address) → \(shown)") }
            try expect(url.scheme == "https" && url.host == "cloud.test" && url.port == nil && url.user == nil, "\(address) → \(shown)")
            try expect(url.query == nil && url.fragment == nil && APIInstructions.isPlainPath(url.percentEncodedPath.isEmpty ? "/" : url.percentEncodedPath),
                       "\(address) → \(shown)")
        }
        let example = APIInstructions.example(endpoint: "https://cloud.test/v1/x")
        try expect(example.hasPrefix("curl -X POST 'https://cloud.test/v1/x' \\"), example)
        try expect(!APIInstructions.example(endpoint: "https://x/'$(id)'").contains("'$(id)'"), "a quote can't close the quoting")
    },
]

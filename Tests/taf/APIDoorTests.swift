import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

private let apiDoor = #"""
{"door":{"id":"d9","app":"api","kind":"api","label":"Acme ERP","open":false,"address":"/v1/doors/d9/work","proof":"proven","how":"by its key",
 "keys":[{"id":"k1","name":"Production","last4":"a1b2","made_at":"2026-11-20T09:00:00Z","last_used_at":"2026-11-22T10:00:00Z"},{"id":"k2","last4":"c3d4","made_at":"2026-11-21T09:00:00Z"}],
 "today":4,"limit":100,"resting":false,"last_request":{"status":"done","at":"2026-11-22T10:00:00Z","words":" Done "}}}
"""#

let tafAPIDoorTests: [Test] = [
    Test("a door Coach drafted reads as the iPad's DoorDraft, from its own path; one it can't draw is none, a used one says so", awaiting: {
        let answer = #"{"draft_id":"dd/1","body":{"kind":"api","draft":{"name":" Shop site ","fields":[{"name":"order","type":"string"},{"name":"reason","type":"choice","values":["refund","exchange"]},{"name":7}],"job":"Answer a customer's refund request","outcomes":["done","needs_you"],"text":true}}}"#
        let transport = CannedTransport([(200, answer), (200, #"{"draft_id":"d2","body":{"kind":"slack","draft":{"name":"x","job":"y"}}}"#),
                                         (200, #"{"draft_id":"d3","body":{"kind":"api","draft":{"name":"Shop","job":"  "}}}"#),
                                         (410, #"{"error":"draft_used","words":"A door was already made from this draft."}"#)])
        let cloud = CloudClient(transport: transport, session: session)
        guard let draft = try await cloud.doorDraft(of: "taf 1", draft: "dd/1") else { throw Failure(description: "not read") }
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "GET /v1/tafs/taf%201/doors/drafts/dd%2F1")
        try expectEqual(draft.id, "dd/1")
        try expectEqual(draft.name, "Shop site")
        try expectEqual(draft.fields.map(DoorDraft.line), ["order · string", "reason · refund | exchange"])
        try expectEqual(draft.outcomes, ["done", "needs_you"])
        try expectEqual(draft.text, true)
        let other = try await cloud.doorDraft(of: "t", draft: "d2")
        try expect(other == nil, "only an API door's draft is drawn")
        let noJob = try await cloud.doorDraft(of: "t", draft: "d3")
        try expect(noJob == nil, "a draft with no job is none")
        do { _ = try await cloud.doorDraft(of: "t", draft: "d4"); throw Failure(description: "read") } catch {
            try expect(DoorDraft.isUsed(error), "a used draft is told apart")
            try expectEqual((error as? CloudRefusal)?.words, "A door was already made from this draft.")
        }
    }),
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

/// New key on the security key (`KeyAct.newAPIDoorKey`, the iPad's `DoorsModel.newKey`), and a Slack door's subscription
/// stopped on planque's safe route (`PlanqueClient.Safe.deleteTrigger`, the iPad's `unsubscribe`).
let tafNewKeyTests: [Test] = [
    Test("New key is tafs cloud's POST to the door's keys, with the name as the only field, signed as sent") {
        let act = KeyAct.newAPIDoorKey(taf: "taf/1", door: "api-7", name: "ERP / production")
        try expectEqual(act.method, "POST")
        try expectEqual(act.path, "/v1/tafs/taf%2F1/doors/api-7/keys")
        try expectEqual(String(decoding: act.body, as: UTF8.self), #"{"name":"ERP / production"}"#)
    },
    Test("a new key's name is what was typed, trimmed and at most 60, else the door's own name") {
        try expectEqual(APIInstructions.keyName("  ", door: "Order system"), "Order system")
        try expectEqual(APIInstructions.keyName(" ERP staging ", door: "Order system"), "ERP staging")
        try expectEqual(APIInstructions.keyName(String(repeating: "k", count: 90), door: "x").count, 60)
    },
    Test("the issued key reads with its id, last four and time, and an answer without a key is unreadable") {
        let key = try AccountClient.decoder.decode(CloudClient.IssuedKey.self, from: Data(
            #"{"id":"k3","key":"tafs_api_abc123","last4":"c123","made_at":"2026-11-24T01:00:00Z"}"#.utf8))
        try expectEqual(key.key, "tafs_api_abc123")
        try expectEqual(key.last4, "c123")
    },
    Test("a Slack door's subscription is stopped with planque's DELETE of its trigger, a safe route") {
        let route = PlanqueClient.Safe.deleteTrigger(grant: "g/1", trigger: "t 2")
        try expectEqual(route.method, "DELETE")
        try expectEqual(route.path, "grants/g%2F1/triggers/t%202")
    },
]

/// Coach's drafted door approved on the security key (`KeyAct.addDraftedAPIDoor`, the iPad's `approveDoorDraft`): the
/// draft's `body`, canonical (RFC 8785, the iPad's `JCS`), is what's signed and sent, and the answer is the door and
/// its first key.
let tafDraftedDoorTests: [Test] = [
    Test("the draft keeps tafs cloud's body in canonical form, and the act sends exactly those bytes to the doors") {
        let answer = #"{"draft_id":"dd-1","made_at":"2026-11-24T03:00:00Z","body":{"kind":"api","draft_id":"dd-1","draft":{"text":false,"name":"ERP","job":"File invoices","fields":[{"type":"string","name":"invoice"}],"outcomes":["filed"]}}}"#
        guard let draft = try DoorDraft.read(Data(answer.utf8)) else { throw Failure(description: "no draft") }
        try expectEqual(draft.id, "dd-1")
        let canonical = #"{"draft":{"fields":[{"name":"invoice","type":"string"}],"job":"File invoices","name":"ERP","outcomes":["filed"],"text":false},"draft_id":"dd-1","kind":"api"}"#
        try expectEqual(String(decoding: draft.body, as: UTF8.self), canonical)
        let act = KeyAct.addDraftedAPIDoor(taf: "taf/1", body: draft.body)
        try expectEqual(act.method, "POST")
        try expectEqual(act.path, "/v1/tafs/taf%2F1/doors")
        try expectEqual(act.body, draft.body)
    },
    Test("the approval's answer reads as the door and its first key; a used draft is refused with tafs cloud's words", awaiting: {
        let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev1")
        let added = #"{"door":{"id":"api-7","app":"api","kind":"api","label":"ERP","open":true,"address":"/v1/doors/api/api-7/requests","proof":"proven","how":"by its key","keys":[],"today":0,"limit":100,"resting":false},"key":{"id":"k1","key":"tafs_api_x","last4":"k_x1","made_at":"2026-11-24T03:01:00Z"}}"#
        let transport = CannedTransport([(201, added), (410, #"{"error":"draft_used","words":"A door was already made from this draft."}"#)])
        let cloud = CloudClient(transport: transport, session: session)
        let act = KeyAct.addDraftedAPIDoor(taf: "taf-1", body: Data(#"{"kind":"api"}"#.utf8))
        let door = try await cloud.addDraftedDoor(act, assertion: "assert")
        try expectEqual(door.key.key, "tafs_api_x")
        try expectEqual(door.door.id, "api-7")
        try expectEqual(transport.sent[0].headers[Passkeys.headerName], "assert")
        try expectEqual(transport.sent[0].body, Data(#"{"kind":"api"}"#.utf8))
        do {
            _ = try await cloud.addDraftedDoor(act, assertion: "assert")
            throw Failure(description: "a used draft went through")
        } catch let refusal as CloudRefusal {
            try expectEqual(refusal.code, "draft_used")
            try expectEqual(refusal.words, "A door was already made from this draft.")
        }
    }),
]

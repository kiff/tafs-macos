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

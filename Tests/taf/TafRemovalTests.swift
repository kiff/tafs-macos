import Foundation

private func english() throws -> Words { try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings")) }

/// Remove for good on the security key, as the iPad's `removeTaf`: the key first, then the Cards, then tafs cloud.
let tafRemovalTests: [Test] = [
    Test("the key approves first, named; then each Card is revoked; then tafs cloud's DELETE goes with that assertion", awaiting: {
        let words = try english()
        var steps: [String] = []
        let said = await TafRemoval.remove(taf: "Refunds", cloudID: "taf-1", cardIDs: ["c1", "c2"], words: words,
                                           sign: { act, title in steps.append("sign \(act.method) \(act.path) \(title)"); return "t=1,a=X" },
                                           revoke: { steps.append("revoke \($0)") },
                                           remove: { steps.append("delete \($0)"); return .init(done: true, removed: ["connections", "schedule"], failed: []) })
        try expectEqual(steps, ["sign DELETE /v1/tafs/taf-1 Remove Refunds for good", "revoke c1", "revoke c2", "delete t=1,a=X"])
        try expectEqual(said, words("connect.schedule_chats_run_reports_memory",
                                    ["cards": words("taf.remove.cards_revoked") + words("connect.connections_disconnected"), "taf": "Refunds"]))
    }),
    Test("a closed sheet changes nothing and says nothing; a key that didn't approve changes nothing and says so", awaiting: {
        let words = try english()
        var touched = false
        let closed = await TafRemoval.remove(taf: "R", cloudID: "t", cardIDs: ["c"], words: words, sign: { _, _ in throw CancellationError() },
                                             revoke: { _ in touched = true }, remove: { _ in touched = true; return .init(done: true, removed: [], failed: []) })
        try expectEqual(closed, nil)
        struct Refused: Error {}
        let refused = await TafRemoval.remove(taf: "R", cloudID: "t", cardIDs: ["c"], words: words, sign: { _, _ in throw Refused() },
                                              revoke: { _ in touched = true }, remove: { _ in touched = true; return .init(done: true, removed: [], failed: []) })
        try expectEqual(refused, words("taf.remove.not_confirmed"))
        try expectEqual(touched, false)
    }),
    Test("a Card KIFF didn't revoke and steps tafs cloud didn't finish are each said, as the iPad's", awaiting: {
        let words = try english()
        struct Failed: Error {}
        let said = await TafRemoval.remove(taf: "R", cloudID: "t", cardIDs: ["c1", "c2"], words: words, sign: { _, _ in "a" },
                                           revoke: { if $0 == "c2" { throw Failed() } },
                                           remove: { _ in .init(done: false, removed: [], failed: ["memory", "key"]) })
        try expectEqual(said, words("taf.remove.not_finished_after", ["cards": words("card.kiff_did_not_revoke_cards", ["cards_left": "1"]),
                                                                       "failed": "memory, key"]))
        try expectEqual(TafRemoval.body(words, goes: "Qonto goes with it."), words("taf.remove_body") + "\n\nQonto goes with it.")
        try expectEqual(TafRemoval.body(words, goes: nil), words("taf.remove_body"))
    }),
    Test("tafs cloud's DELETE carries the passkey assertion only", awaiting: {
        let transport = CannedTransport([(200, #"{"done":true,"removed":["name"],"failed":[]}"#)])
        let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
        let removal = try await CloudClient(transport: transport, session: session).remove("taf-1", assertion: "t=1,a=X")
        try expectEqual(removal, .init(done: true, removed: ["name"], failed: []))
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "DELETE /v1/tafs/taf-1")
        try expectEqual(transport.sent[0].headers[Passkeys.headerName], "t=1,a=X")
        try expectEqual(transport.sent[0].headers["KIFF-Device-Signature"], nil)
    }),
]

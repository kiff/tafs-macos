import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private func english() throws -> Words { try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings")) }

private func begun(draft: String?) throws -> TafVersions.Begun {
    let d = draft.map { #""\#($0)""# } ?? "null"
    let sw = try AccountClient.decoder.decode(TafVersions.Switching.self, from: Data(#"{"n":4,"draft":\#(d),"at":"2026-11-24T01:00:00Z"}"#.utf8))
    return TafVersions.Begun(switching: sw, stoppedWords: nil)
}

private func draft(_ version: String, status: String = "draft") throws -> AccountClient.Draft {
    try AccountClient.decoder.decode(AccountClient.Draft.self, from: Data(#"{"id":"dr_1","agent_id":"a","status":"\#(status)","version":"\#(version)"}"#.utf8))
}

/// What one install did, in order.
private final class Steps {
    var did: [String] = []
}

private func use(_ steps: Steps, draft d: String?, shown: String?, read: AccountClient.Draft? = nil,
                 owner: Error? = nil, key: Error? = nil, live: Error? = nil) async throws -> VersionSwitch.Done {
    let words = try english()
    let b = try begun(draft: d)
    return await VersionSwitch.use(n: 4, shownDraft: shown, words: words,
                                   begin: { steps.did.append("begin"); return b },
                                   readDraft: { steps.did.append("read \($0)"); return try read ?? draft("v7") },
                                   confirmOwner: { steps.did.append("owner"); if let owner { throw owner } },
                                   confirm: { act in
                                       if case .confirmDraft(let id, let v) = act { steps.did.append("key \(id) \(v)") }
                                       if let key { throw key }
                                       return Data(#"{"status":"confirmed"}"#.utf8)
                                   },
                                   cancel: { steps.did.append("cancel") },
                                   makeLive: { steps.did.append("live"); if let live { throw live } })
}

let tafVersionSwitchTests: [Test] = [
    Test("a version with a Card: KIFF's draft read here, the key confirms the version shown, then tafs cloud makes it live", awaiting: {
        let steps = Steps()
        let done = try await use(steps, draft: "dr_1", shown: "v7")
        guard case .live = done else { throw Failure(description: "\(done)") }
        try expectEqual(steps.did, ["begin", "read dr_1", "key dr_1 v7", "live"])
    }),
    Test("a version with no Card: the owner confirms (Touch ID or the password), then it goes live; nothing on the key", awaiting: {
        let steps = Steps()
        let done = try await use(steps, draft: nil, shown: nil)
        guard case .live = done else { throw Failure(description: "\(done)") }
        try expectEqual(steps.did, ["begin", "owner", "live"])
    }),
    Test("a Card KIFF already took isn't confirmed again, and the owner still confirms before it goes live", awaiting: {
        for status in ["confirmed", "claimed"] {
            let steps = Steps()
            let done = try await use(steps, draft: "dr_1", shown: "v7", read: try draft("v7", status: status))
            guard case .live = done else { throw Failure(description: "\(done)") }
            try expectEqual(steps.did, ["begin", "read dr_1", "owner", "live"])
        }
    }),
    Test("a Card no one was shown is read first, and nothing is signed or sent", awaiting: {
        let steps = Steps()
        let done = try await use(steps, draft: "dr_1", shown: nil)
        try expectEqual(done, .read)
        try expectEqual(steps.did, ["begin"])
    }),
    Test("a Card that changed since it was shown is never confirmed: the switch is cancelled and it's shown again", awaiting: {
        let steps = Steps()
        let done = try await use(steps, draft: "dr_1", shown: "v6")
        try expectEqual(done, .changed(try draft("v7")))
        try expectEqual(steps.did, ["begin", "read dr_1", "cancel"])
    }),
    Test("the key's sheet or the owner's prompt closed cancels the switch and says nothing; nothing goes live", awaiting: {
        let keyClosed = Steps()
        let r1 = try await use(keyClosed, draft: "dr_1", shown: "v7", key: CancellationError())
        try expectEqual(r1, .closed)
        try expectEqual(keyClosed.did, ["begin", "read dr_1", "key dr_1 v7", "cancel"])
        let ownerClosed = Steps()
        let r2 = try await use(ownerClosed, draft: nil, shown: nil, owner: OwnerPrompt.Closed())
        try expectEqual(r2, .closed)
        try expectEqual(ownerClosed.did, ["begin", "owner", "cancel"])
        let ownerFailed = Steps()
        let r3 = try await use(ownerFailed, draft: nil, shown: nil, owner: KIFFError.unreadable)
        try expectEqual(r3, .failed(try english()("common.not_sent_unconfirmed")))
        try expectEqual(ownerFailed.did, ["begin", "owner", "cancel"])
    }),
    Test("KIFF's card_revised offers Draft its Card again; another refusal leaves the switch to finish or cancel", awaiting: {
        let words = try english()
        let stale = Steps()
        let r4 = try await use(stale, draft: "dr_1", shown: "v7", key: KIFFError.refused(status: 409, code: "card_revised"))
        try expectEqual(r4, .stale(words("version.card_out_of_date", ["n": "4"])))
        try expectEqual(stale.did, ["begin", "read dr_1", "key dr_1 v7"])
        let other = Steps()
        let failed = try await use(other, draft: "dr_1", shown: "v7", key: KIFFError.refused(status: 503, code: "down"))
        guard case .failed(let line) = failed, line.hasPrefix("Installing version 4 didn't finish") else { throw Failure(description: "\(failed)") }
        try expectEqual(other.did, ["begin", "read dr_1", "key dr_1 v7"])
        let phone = Steps()
        let r5 = try await use(phone, draft: "dr_1", shown: "v7", key: ApproveOnPhone())
        try expectEqual(r5, .failed(words("approval.device_can_not_approve_approve")))
    }),
    Test("tafs cloud refusing to make it live says so, as not live without a Card and unfinished with one", awaiting: {
        let words = try english()
        let refusal = CloudRefusal(status: 409, body: Data(#"{"error":"card not confirmed"}"#.utf8))
        let bare = try await use(Steps(), draft: nil, shown: nil, live: refusal)
        try expectEqual(bare, .failed(words("version.not_live", ["n": "4", "why": "card not confirmed"])))
        let carded = try await use(Steps(), draft: "dr_1", shown: "v7", live: refusal)
        try expectEqual(carded, .failed(words("version.install_unfinished", ["n": "4", "why": "card not confirmed"])))
    }),
    Test("beginning: a run in the way says tafs cloud's words and is offered Stop it and install; another refusal can't go live", awaiting: {
        let words = try english()
        let blocked = await VersionSwitch.prepare(n: 4, words: words, begin: {
            throw CloudRefusal(status: 409, body: Data(#"{"error":"blocked","words":"A run waits on you.","blocking":[{"run":"r1"}]}"#.utf8))
        })
        try expectEqual(blocked, .blocked("A run waits on you."))
        let plain = await VersionSwitch.prepare(n: 4, words: words, begin: {
            throw CloudRefusal(status: 409, body: Data(#"{"error":"switching"}"#.utf8))
        })
        try expectEqual(plain, .failed(words("version.cant_go_live", ["n": "4", "why": "switching"])))
    }),
    Test("tafs cloud's switch routes: begin with redraft and stop_blocking, its stopped words, and make live; none signed", awaiting: {
        let transport = CannedTransport([
            (200, #"{"switching":{"n":4,"draft":"dr_1","at":"2026-11-24T01:00:00Z"},"stopped":[{"run":"r1"}],"words":"Stopped 1 run."}"#),
            (200, #"{"switching":{"n":4,"draft":null,"at":"2026-11-24T01:00:00Z"},"stopped":[],"words":"Nothing stopped."}"#),
            (200, #"{"live":4}"#),
        ])
        let cloud = CloudClient(transport: transport, session: session)
        let first = try await cloud.beginSwitch(of: "taf/1", version: 4, redraft: true, stopBlocking: true)
        try expectEqual(first.switching.draft, "dr_1")
        try expectEqual(first.stoppedWords, "Stopped 1 run.")
        let second = try await cloud.beginSwitch(of: "taf/1", version: 4)
        try expectEqual(second.stoppedWords, nil)
        try await cloud.makeLive(of: "taf/1", version: 4)
        try expectEqual(transport.sent.map { $0.method + " " + $0.path },
                        ["POST /v1/tafs/taf%2F1/versions/4/switch", "POST /v1/tafs/taf%2F1/versions/4/switch", "POST /v1/tafs/taf%2F1/versions/4/live"])
        try expectEqual(String(decoding: transport.sent[0].body, as: UTF8.self), #"{"redraft":true,"stop_blocking":true}"#)
        try expectEqual(String(decoding: transport.sent[1].body, as: UTF8.self), #"{"redraft":false,"stop_blocking":false}"#)
        try expectEqual(transport.sent.contains { $0.headers.keys.contains { $0.hasPrefix("KIFF-") } }, false)
    }),
    Test("a draft's Cards as the owner reads them: new ones as one, a revised one now and after, an unchanged one once, removed ones") {
        let words = try english()
        let json = #"""
        {"id":"dr_1","agent_id":"a","status":"draft","version":"v7",
         "cards":[{"lines":["Refund a payment: up to €100.00 each"]},
                  {"lines":["Refund a payment: up to €100.00 each"]},
                  {"lines":["Send an email"],"current":{"lines":["Read email"]}},
                  {"lines":["20 calls a day"]},
                  {"lines":["Read files"],"current":{"lines":["Read files"]},"unchanged":true}],
         "retires":[{"id":"c9","current":{"lines":["Delete files"]}}]}
        """#
        let d = try AccountClient.decoder.decode(AccountClient.Draft.self, from: Data(json.utf8))
        try expectEqual(d.shown(words), [
            .new(lines: ["Refund a payment: up to €100.00 each", "20 calls a day"]),
            .one(now: ["Read email"], after: ["Send an email"], unchanged: false),
            .one(now: ["Read files"], after: ["Read files"], unchanged: true),
        ])
        try expectEqual(d.retires?.first.flatMap { $0.current }.map { AccountClient.Draft.lines(of: $0, words) }, ["Delete files"])
    },
]

import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private func english() throws -> Words { try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings")) }
private let openJSON = #"{"id":"tr1","n":3,"draft":"dr_1","session":"s9","started":"2026-11-22T10:00:00Z","used":"2026-11-22T10:00:00Z","title":"Trying version 3","try":"Refund order 4471","ends":"2026-11-29T10:00:00Z"}"#

private func draft(_ version: String) throws -> AccountClient.Draft {
    try AccountClient.decoder.decode(AccountClient.Draft.self, from: Data(#"{"id":"dr_1","agent_id":"a","status":"draft","version":"\#(version)"}"#.utf8))
}

let tafTrialsTests: [Test] = [
    Test("a trial starts as the iPad's: tafs cloud's draft, read here, confirmed as a trial on the key, then opened", awaiting: {
        let words = try english()
        var acts: [KeyAct] = [], opened: [String] = []
        let done = await Trials.start(n: 3, shownDraft: "v7", words: words, makeDraft: { "dr_1" }, readDraft: { _ in try draft("v7") },
                                      confirm: { acts.append($0); return Data(#"{"status":"trying"}"#.utf8) },
                                      open: { opened.append($0); return try AccountClient.decoder.decode(Trials.Open.self, from: Data(openJSON.utf8)) })
        guard case .started(let open) = done else { throw Failure(description: "\(done)") }
        try expectEqual(open.tryWith, "Refund order 4471")
        try expectEqual(acts, [.confirmTrial(id: "dr_1", version: "v7")])
        try expectEqual(opened, ["dr_1"])
    }),
    Test("a draft that changed since it was shown is never confirmed; a KIFF that answers anything but trying started no trial", awaiting: {
        let words = try english()
        var asked = 0
        let changed = await Trials.start(n: 3, shownDraft: "v6", words: words, makeDraft: { "dr_1" }, readDraft: { _ in try draft("v7") },
                                         confirm: { _ in asked += 1; return Data() }, open: { _ in throw CancellationError() })
        try expectEqual(changed, .changed)
        try expectEqual(asked, 0)
        let confirmed = await Trials.start(n: 3, shownDraft: "v7", words: words, makeDraft: { "dr_1" }, readDraft: { _ in try draft("v7") },
                                           confirm: { _ in Data(#"{"status":"confirmed"}"#.utf8) }, open: { _ in throw CancellationError() })
        try expectEqual(confirmed, .notATrial("confirmed"))
        try expectEqual(Trials.notATrialLine("confirmed", words: words), words("version.not_a_trial.confirmed"))
        let closed = await Trials.start(n: 3, shownDraft: "v7", words: words, makeDraft: { "dr_1" }, readDraft: { _ in try draft("v7") },
                                        confirm: { _ in throw CancellationError() }, open: { _ in throw CancellationError() })
        try expectEqual(closed, .closed)
    }),
    Test("the key approves exactly the confirm's bytes: sorted, with `as` only for a trial") {
        let trial = KeyAct.confirmTrial(id: "dr/1", version: "v7"), install = KeyAct.confirmDraft(id: "dr_1", version: "v7")
        try expectEqual(trial.method + " " + trial.path, "POST /v1/me/agent-drafts/dr%2F1/confirm")
        try expectEqual(String(decoding: trial.body, as: UTF8.self), #"{"as":"trial","version":"v7"}"#)
        try expectEqual(String(decoding: install.body, as: UTF8.self), #"{"version":"v7"}"#)
    },
    Test("tafs cloud's trial routes: try, open, read, install, go back; KIFF's end is the device key's signed call", awaiting: {
        let transport = CannedTransport([(200, #"{"draft":"dr_1"}"#), (200, #"{"trial":\#(openJSON)}"#), (200, #"{"trial":null}"#)])
        let cloud = CloudClient(transport: transport, session: session)
        let made = try await cloud.trialDraft(of: "taf-1", version: 3)
        try expectEqual(made, "dr_1")
        let open = try await cloud.openTrial(of: "taf-1", version: 3, draft: "dr_1")
        try expectEqual(open.n, 3)
        let none = try await cloud.openTrial(of: "taf-1")
        try expectEqual(none, nil)
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["POST /v1/tafs/taf-1/versions/3/try", "PUT /v1/tafs/taf-1/trial", "GET /v1/tafs/taf-1/trial"])
    }),
]

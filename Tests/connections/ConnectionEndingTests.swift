import Foundation

private let english = { try! Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings")) }()

private struct Refused: Error {}

/// A removed taf's connections as tafs cloud lists them: `d` no taf uses, `k` Chargebacks' Card uses.
private func listed() throws -> [String: Apps.RemovedTaf.Grant] {
    let removed = try AccountClient.decoder.decode([Apps.RemovedTaf].self, from: Data(#"""
    [{"agent":"a_gone","grants":[{"grant":"d","used_by":[]},{"grant":"k","used_by":[{"taf":"t2","name":"Chargebacks"}]}]}]
    """#.utf8))
    return AppConnections.removedListed(removed)
}

let connectionEndingTests: [Test] = [
    Test("a Mac without Touch ID, or without its key in the Secure Enclave, ends nothing itself: it goes to the phone") {
        try expectEqual(ConnectionEnding.route(enclaveKey: true, biometrics: false), .phone)
        try expectEqual(ConnectionEnding.route(enclaveKey: false, biometrics: true), .phone)
        try expectEqual(ConnectionEnding.route(enclaveKey: false, biometrics: false), .phone)
        try expectEqual(ConnectionEnding.route(enclaveKey: true, biometrics: true), .touchID)
        try expectEqual(ConnectionEnding.phoneLine, "approval.device_can_not_approve_approve")
        try expectEqual(english(ConnectionEnding.phoneLine), "This device can't approve. Approve on another device signed in to your account.")
    },
    Test("only a session whose key is in the Secure Enclave can end a connection; a software key or none can't") {
        let session = Session(accessToken: "tok", expiresIn: 60, tenant: "acme-1", subject: "u1", deviceID: nil)
        var account = AccountClient(transport: CannedTransport([]), session: session, signMessage: { _ in "SIG" })
        let planque = PlanqueClient(baseURL: "https://planque.test")
        let transport = CannedTransport([])
        try expect(!ConnectionsSource(account: account, planque: planque, transport: transport).enclaveKey, "a key nobody named")
        account.keyStore = "software"
        try expect(!ConnectionsSource(account: account, planque: planque, transport: transport).enclaveKey, "a software key")
        account.keyStore = "enclave"
        try expect(ConnectionsSource(account: account, planque: planque, transport: transport).enclaveKey, "the Secure Enclave's")
        try expect(ConnectionsSource(transport: transport, tenant: "acme-1", proof: { nil }).end == nil, "a source made for a read ends nothing")
    },
    Test("the source's ending is planque's DELETE, signed by the session's device key with this device", awaiting: {
        let session = Session(accessToken: "tok", expiresIn: 60, tenant: "acme-1", subject: "u1", deviceID: nil)
        var signed: [String] = []
        var account = AccountClient(transport: CannedTransport([]), session: session, signMessage: { signed.append($0); return "SIG" })
        account.keyStore = "enclave"
        let planque = PlanqueClient(baseURL: "https://planque.test")
        planque.deviceID = "dev_9"
        let transport = CannedTransport([(200, "{}")])
        let source = ConnectionsSource(account: account, planque: planque, transport: transport)
        try await source.end?("g1")
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["DELETE /v1/accounts/acme-1/grants/g1"])
        try expectEqual(signed.count, 1)
        try expect(planque.signer == nil, "the shared signer stays unarmed")
        // No device key in the session: nothing is signed or sent.
        let bare = ConnectionsSource(account: AccountClient(transport: CannedTransport([]), session: session), planque: planque, transport: transport)
        do { try await bare.end?("g2"); throw Failure(description: "sent") } catch PlanqueClient.PlanqueError.notSigning {}
        try expectEqual(transport.sent.count, 1)
    }),
    Test("Touch ID is asked once, with the question as its reason, then each connection is ended in turn", awaiting: {
        var asked: [String] = []
        var sent: [String] = []
        let out = await ConnectionEnding.end(["a", "b"], prompt: "Remove access to Stripe for Rae?", confirm: { asked.append($0) },
                                             delete: { sent.append($0) }, current: { true }, english)
        try expectEqual(asked, ["Remove access to Stripe for Rae?"])
        try expectEqual(sent, ["a", "b"])
        try expectEqual(out, ConnectionEnding.Outcome())
        try expectEqual(ConnectionEnding.disconnectNote(out), nil)
    }),
    Test("a closed Touch ID prompt sends nothing: Disconnect says nothing, Clear says it wasn't done", awaiting: {
        var sent: [String] = []
        let out = await ConnectionEnding.end(["a"], prompt: "?", confirm: { _ in throw OwnerPrompt.Closed() },
                                             delete: { sent.append($0) }, current: { true }, english)
        try expect(sent.isEmpty, "nothing sent")
        try expectEqual(out, ConnectionEnding.Outcome(left: 1, unconfirmed: true))
        try expectEqual(ConnectionEnding.disconnectNote(out), nil)
        try expectEqual(ConnectionEnding.clearNote(out, ending: 1, keptFor: [], english), "Not done: it wasn't confirmed.")
        // Nothing to end: nothing asked.
        var asked = 0
        let none = await ConnectionEnding.end([], prompt: "?", confirm: { _ in asked += 1 }, delete: { sent.append($0) }, current: { true }, english)
        try expectEqual(none, ConnectionEnding.Outcome())
        try expectEqual(asked, 0)
    }),
    Test("a refusal is counted and said, and the next connection is still ended", awaiting: {
        var sent: [String] = []
        let out = await ConnectionEnding.end(["a", "b"], prompt: "?", confirm: { _ in }, delete: { id in
            sent.append(id)
            if id == "a" { throw PlanqueClient.PlanqueError.server(status: 503, message: "", words: "planque is down.") }
        }, current: { true }, english)
        try expectEqual(sent, ["a", "b"])
        try expectEqual(out.left, 1)
        try expectEqual(out.why, "Access not removed. planque is down.")
        try expectEqual(ConnectionEnding.disconnectNote(out), "Access not removed. planque is down.")
        try expectEqual(ConnectionEnding.clearNote(out, ending: 2, keptFor: [], english), "Cleared 1. 1 couldn't be cleared. Try again.")
    }),
    Test("signed out on the way: nothing more is sent, and nothing is said", awaiting: {
        var sent: [String] = []
        var live = true
        let out = await ConnectionEnding.end(["a", "b"], prompt: "?", confirm: { _ in }, delete: { id in sent.append(id); live = false },
                                             current: { live }, english)
        try expectEqual(sent, ["a"])
        try expect(out.stopped && out.left == 1, "stopped with one left: \(out)")
        try expectEqual(ConnectionEnding.clearNote(out, ending: 2, keptFor: [], english), nil)
        try expectEqual(ConnectionEnding.disconnectNote(out), nil)
    }),
    Test("Clear ends only what tafs cloud lists with no Card using it, and keeps what a Card uses") {
        let plan = ConnectionEnding.clearPlan(["d", "k", "x"], listed: try listed())
        try expectEqual(plan.ending, ["d"])
        try expectEqual(plan.keptFor, [["Chargebacks"]])
        try expectEqual(ConnectionEnding.cleared(done: 1, kept: 1, keptFor: ["Chargebacks"], left: 1, english),
                        "Cleared 1. Kept 1 for Chargebacks, whose Card uses it. 1 couldn't be cleared. Try again.")
        try expectEqual(ConnectionEnding.cleared(done: 0, kept: 2, keptFor: ["", "Ana", "Bo", "Ana"], left: 0, english),
                        "Kept 2 for \(english.list(["Ana", "Bo"])), whose Cards use them.")
        try expectEqual(ConnectionEnding.cleared(done: 0, kept: 1, keptFor: [], left: 0, english), "Kept 1 for another taf, whose Card uses it.")
    },
    Test("the ending's words are in every shipped language") {
        let folder = URL(fileURLWithPath: ".shared/app/strings")
        for language in try Words.shipped(folder: folder) {
            let words = try Words(language: language, folder: folder)
            for key in ["connect.not_disconnected", "common.not_done_unconfirmed", "connect.could_not_cleared_try_again",
                        "connect.kept.another_taf", "approval.device_can_not_approve_approve", "approval.security_key.on_phone"] {
                try expect(words(key, ["why": "x", "left": "1"]) != key, "\(key) in \(language)")
            }
            for key in ["connect.clear_removed.cleared", "connect.kept.for_card", "connect.kept.for_cards", "connect.clear_removed.title"] {
                try expect(words.count(key, 2, ["who": "x"]) != key, "\(key) in \(language)")
            }
        }
    },
    Test("Touch ID alone, never the Mac's password: the check is biometrics only, with no password button") {
        let check = try String(contentsOf: URL(fileURLWithPath: "Sources/App/connections/TouchIDOnly.swift"), encoding: .utf8)
        try expectEqual(check.components(separatedBy: ".deviceOwnerAuthenticationWithBiometrics").count - 1, 3)
        try expectEqual(check.components(separatedBy: ".deviceOwnerAuthentication").count - 1, 3)
        try expect(check.contains(#"context.localizedFallbackTitle = """#), "no password button")
        try expect(check.contains("catch where NeedsYouModel.closed(error)"), "its password button counts as closed")
        // Nothing that ends a connection asks the owner's prompt, which lets the password in.
        for path in ["Sources/App/connections/ConnectAppsView.swift", "Sources/App/connections/AppConnectionsView.swift",
                     "Sources/App/connections/TouchIDOnly.swift", "Sources/Core/connections/ConnectionEnding.swift",
                     "Sources/Core/connections/AppConnections.swift"] {
            let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
            try expect(!text.contains("confirmOwner("), "\(path) asks the owner's prompt")
            try expect(!text.contains("confirmOwnerForCore"), "\(path) asks the owner's prompt")
        }
        let model = try String(contentsOf: URL(fileURLWithPath: "Sources/App/connections/ConnectAppsView.swift"), encoding: .utf8)
        try expectEqual(model.components(separatedBy: "confirm: touchID.confirm").count - 1, 2)
        try expect(model.contains("touchID ?? .system(session:"), "Touch ID only, by default, held to this session's fingers")
        // The fingers Touch ID passed with are checked against the ones kept, after the prompt.
        try expect(check.contains("context.evaluatedPolicyDomainState"), "the enrolled set is read")
        try expect(check.contains("== .same else {\n                throw FingersChanged()"), "a changed set after the prompt sends nothing")
    },
    Test("a finger added since the session began ends nothing here: Touch ID goes to the phone until the next sign-in") {
        let session = "t1|u1|dev_1"
        let first = Data([1, 2, 3])
        try expectEqual(ConnectionEnding.fingers(recorded: nil, session: session, now: first), .first)
        let kept = ConnectionEnding.fingersRecord(session: session, now: first)
        try expectEqual(ConnectionEnding.fingers(recorded: kept, session: session, now: first), .same)
        // A finger added (or one removed): another set.
        try expectEqual(ConnectionEnding.fingers(recorded: kept, session: session, now: Data([1, 2, 4])), .changed)
        // None enrolled, or none readable: never Touch ID.
        try expectEqual(ConnectionEnding.fingers(recorded: kept, session: session, now: nil), .changed)
        try expectEqual(ConnectionEnding.fingers(recorded: nil, session: session, now: Data()), .changed)
        // The next sign-in is another session: its first set is kept anew.
        try expectEqual(ConnectionEnding.fingers(recorded: kept, session: "t1|u1|dev_2", now: Data([9])), .first)
        // A session id with a line break can't be told apart from its record: never Touch ID.
        try expectEqual(ConnectionEnding.fingers(recorded: nil, session: "t1\n", now: first), .changed)
        // A set whose bytes hold a line break still reads as itself.
        let broken = Data([0x0A, 7, 0x0A])
        try expectEqual(ConnectionEnding.fingers(recorded: ConnectionEnding.fingersRecord(session: session, now: broken), session: session, now: broken), .same)
    },
    Test("once the session ends, an ending on its way sends nothing more: the model's check, and the window's") {
        let model = try String(contentsOf: URL(fileURLWithPath: "Sources/App/connections/ConnectAppsView.swift"), encoding: .utf8)
        try expectEqual(model.components(separatedBy: "current: { [weak self] in self?.current ?? false }").count - 1, 2)
        try expect(!model.contains("current: { !Task.isCancelled }"), "a task nobody cancels is no session check")
        try expect(model.contains("private var current: Bool { !sessionEnded && !Task.isCancelled }"), "the session's end stops it")
        let window = try String(contentsOf: URL(fileURLWithPath: "Sources/App/shell/SignedInView.swift"), encoding: .utf8)
        // On sign-out, and whenever the window goes with its session.
        try expectEqual(window.components(separatedBy: "connect.endSession()").count - 1, 2)
    },
    Test("only an ending is done here: Sign in again and Replace the key stay on the phone") {
        let view = try String(contentsOf: URL(fileURLWithPath: "Sources/App/connections/AppConnectionsView.swift"), encoding: .utf8)
        guard let fix = view.range(of: #"GatedAction(title: words(grant.takesKey ? "connect.replace_key" : "connect.sign_in_again")"#) else {
            throw Failure(description: "Sign in again's action")
        }
        let line = view[fix.lowerBound...].prefix { $0 != "\n" }
        try expect(!line.contains("perform") && !line.contains("route"), "Sign in again is never done here: \(line)")
        // Every action done here ends a connection.
        let performs = view.components(separatedBy: "perform: {").count - 1
        try expectEqual(performs, 4)
        try expectEqual(view.components(separatedBy: "await model.disconnect(").count + view.components(separatedBy: "await model.clear(").count
                        + view.components(separatedBy: "await perform(words)").count - 3, 4)
    },
]

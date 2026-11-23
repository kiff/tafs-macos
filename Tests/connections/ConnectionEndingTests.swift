import Foundation

private let english = { try! Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings")) }()

private struct Refused: Error {}

/// The ending key's Keychain item, counted: what was written and deleted.
private final class KeptKey {
    var record: Data?
    var writes = 0
    var removes = 0
    func save(_ data: Data) { writes += 1; record = data }
    func remove() { removes += 1; record = nil }
    func check(session: String, biometrics: @escaping () -> Bool = { true }, loads: @escaping (Data) -> Bool = { _ in true },
               sign: @escaping (Data, String, Data) async throws -> Void = { _, _, _ in }) -> ConnectionEnding.EndingKeyCheck {
        ConnectionEnding.EndingKeyCheck(session: session, read: { [unowned self] in self.record }, remove: { [unowned self] in self.remove() },
                                        biometrics: biometrics, loads: loads, sign: sign)
    }
}

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
        var signed: [Data] = []
        let out = await ConnectionEnding.end(["a", "b"], tenant: "acme-1", prompt: "Remove access to Stripe for Rae?",
                                             confirm: { asked.append($0); signed.append($1) },
                                             delete: { sent.append($0) }, current: { true }, english)
        try expectEqual(asked, ["Remove access to Stripe for Rae?"])
        // The iPad's own confirmation is what the ending key signs.
        try expectEqual(signed, [Data("tafs.disconnect.v1|acme-1|a,b".utf8)])
        try expectEqual(sent, ["a", "b"])
        try expectEqual(out, ConnectionEnding.Outcome())
        try expectEqual(ConnectionEnding.disconnectNote(out, english), nil)
    }),
    Test("a closed Touch ID prompt sends nothing: Disconnect says nothing, Clear says it wasn't done", awaiting: {
        var sent: [String] = []
        let out = await ConnectionEnding.end(["a"], tenant: "t", prompt: "?", confirm: { _, _ in throw OwnerPrompt.Closed() },
                                             delete: { sent.append($0) }, current: { true }, english)
        try expect(sent.isEmpty, "nothing sent")
        try expectEqual(out, ConnectionEnding.Outcome(left: 1, unconfirmed: true))
        try expectEqual(ConnectionEnding.disconnectNote(out, english), nil)
        try expectEqual(ConnectionEnding.clearNote(out, ending: 1, keptFor: [], english), "Not done: it wasn't confirmed.")
        // Nothing to end: nothing asked.
        var asked = 0
        let none = await ConnectionEnding.end([], tenant: "t", prompt: "?", confirm: { _, _ in asked += 1 }, delete: { sent.append($0) }, current: { true }, english)
        try expectEqual(none, ConnectionEnding.Outcome())
        try expectEqual(asked, 0)
    }),
    Test("a refusal is counted and said, and the next connection is still ended", awaiting: {
        var sent: [String] = []
        let out = await ConnectionEnding.end(["a", "b"], tenant: "t", prompt: "?", confirm: { _, _ in }, delete: { id in
            sent.append(id)
            if id == "a" { throw PlanqueClient.PlanqueError.server(status: 503, message: "", words: "planque is down.") }
        }, current: { true }, english)
        try expectEqual(sent, ["a", "b"])
        try expectEqual(out.left, 1)
        try expectEqual(out.why, "Access not removed. planque is down.")
        try expectEqual(ConnectionEnding.disconnectNote(out, english), "Access not removed. planque is down.")
        try expectEqual(ConnectionEnding.clearNote(out, ending: 2, keptFor: [], english), "Cleared 1. 1 couldn't be cleared. Try again.")
    }),
    Test("signed out on the way: nothing more is sent, and nothing is said", awaiting: {
        var sent: [String] = []
        var live = true
        let out = await ConnectionEnding.end(["a", "b"], tenant: "t", prompt: "?", confirm: { _, _ in }, delete: { id in sent.append(id); live = false },
                                             current: { live }, english)
        try expectEqual(sent, ["a"])
        try expect(out.stopped && out.left == 1, "stopped with one left: \(out)")
        try expectEqual(ConnectionEnding.clearNote(out, ending: 2, keptFor: [], english), nil)
        try expectEqual(ConnectionEnding.disconnectNote(out, english), nil)
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
    Test("Touch ID alone, never the Mac's password: the ending key's access control is biometrics only, with no password button") {
        let check = try String(contentsOf: URL(fileURLWithPath: "Sources/App/connections/TouchIDOnly.swift"), encoding: .utf8)
        // Touch ID is only read (`canEvaluatePolicy`), never evaluated as a policy that takes the password.
        try expectEqual(check.components(separatedBy: ".deviceOwnerAuthenticationWithBiometrics").count - 1, 1)
        try expectEqual(check.components(separatedBy: ".deviceOwnerAuthentication").count - 1, 1)
        try expect(!check.contains("evaluatePolicy("), "no policy prompt: the key's signature is the check")
        // The ending key's access control: exactly these flags, made in one place.
        try expectEqual(check.components(separatedBy: "SecAccessControlCreateWithFlags(").count - 1, 1)
        try expect(check.contains("SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .biometryCurrentSet], nil)"),
                   "exactly [.privateKeyUsage, .biometryCurrentSet]")
        for other in [".biometryAny", ".touchIDAny", ".touchIDCurrentSet", ".userPresence", ".devicePasscode", ".or]", ".or,", ".applicationPassword",
                      ".watch", ".companion", "kSecAttrAccessibleAfterFirstUnlock", "kSecAttrAccessibleAlways"] {
            try expect(!check.contains(other), "the ending key never takes \(other)")
        }
        try expect(check.contains("SecureEnclave.P256.Signing.PrivateKey(accessControl: access)"), "made in the Secure Enclave with it")
        // The prompt: the question as its reason, no password button, and the signature checked.
        try expect(check.contains("context.localizedReason = reason"), "the question is the reason")
        try expect(check.contains(#"context.localizedFallbackTitle = """#), "no password button")
        try expect(check.contains("context.interactionNotAllowed = true"), "reading the key asks nothing")
        try expect(check.contains("key.publicKey.isValidSignature(signature, for: message)"), "the signature is checked with the key's own public half")
        try expect(check.contains("catch where NeedsYouModel.closed(error)"), "a closed prompt counts as closed")
        // The fingers record is gone.
        for gone in ["evaluatedPolicyDomainState", "tafs.touch-id.fingers", "FingersChanged"] {
            try expect(!check.contains(gone), "no \(gone)")
        }
        let core = try String(contentsOf: URL(fileURLWithPath: "Sources/Core/connections/ConnectionEnding.swift"), encoding: .utf8)
        try expect(!core.contains("enum Fingers") && !core.contains("fingersRecord"), "no fingers record")
        // Nothing that ends a connection asks the owner's prompt, which lets the password in.
        for path in ["Sources/App/connections/ConnectAppsView.swift", "Sources/App/connections/AppConnectionsView.swift",
                     "Sources/App/connections/TouchIDOnly.swift", "Sources/Core/connections/ConnectionEnding.swift",
                     "Sources/Core/connections/EndingKeyCheck.swift", "Sources/Core/connections/AppConnections.swift"] {
            let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
            try expect(!text.contains("confirmOwner("), "\(path) asks the owner's prompt")
            try expect(!text.contains("confirmOwnerForCore"), "\(path) asks the owner's prompt")
        }
        let model = try String(contentsOf: URL(fileURLWithPath: "Sources/App/connections/ConnectAppsView.swift"), encoding: .utf8)
        try expectEqual(model.components(separatedBy: "confirm: touchID.confirm").count - 1, 2)
        try expect(model.contains("touchID ?? .system(session: cloud.session)"), "Touch ID only, by default, through this sign-in's ending key")
    },
    Test("the ending key is made at sign-in, kept, and deleted at sign-out; the sign-in's code asks nothing") {
        let check = try String(contentsOf: URL(fileURLWithPath: "Sources/App/connections/TouchIDOnly.swift"), encoding: .utf8)
        // Only sign-in's hook writes it; the check reads, and deletes only a key gone.
        try expectEqual(check.components(separatedBy: "store.save(").count - 1, 1)
        try expect(check.contains("save: { try store.save($0, for: EndingKey.account) }"), "the hook keeps it")
        try expect(check.contains("forgotten: { store.delete(EndingKey.account) })"), "sign-out deletes it")
        try expect(check.contains(#"enclave: keyStore == "enclave" && SecureEnclave.isAvailable"#), "only beside a Secure Enclave device key")
        let signIn = try String(contentsOf: URL(fileURLWithPath: "Sources/App/pairing/SignInModel.swift"), encoding: .utf8)
        guard let out = signIn.range(of: "func signedOut() {") else { throw Failure(description: "signedOut") }
        let body = signIn[out.lowerBound...].prefix(600)
        try expect(body.contains("endingKey.forgotten()"), "sign-out deletes the ending key")
        try expectEqual(signIn.components(separatedBy: "endingKey.kept(got, ").count - 1, 2)
        try expectEqual(signIn.components(separatedBy: "try sessions.save(got)\n").count - 1, 2)
        let app = try String(contentsOf: URL(fileURLWithPath: "Sources/App/entry/TafsApp.swift"), encoding: .utf8)
        try expect(app.contains("endingKey: EndingKey.hook(store: store)"), "the app's sign-in makes it")
        // Sign-in itself never names Touch ID's frameworks: the hook is the connections' own.
        let fm = FileManager.default
        for file in try fm.contentsOfDirectory(atPath: "Sources/App/pairing") where file.hasSuffix(".swift") {
            let text = try String(contentsOf: URL(fileURLWithPath: "Sources/App/pairing/\(file)"), encoding: .utf8)
            for asking in ["import LocalAuthentication", "LAContext", "SecAccessControl", "biometry"] {
                try expect(!text.contains(asking), "\(file) names \(asking)")
            }
        }
    },
    Test("the ending key's record is this sign-in's handle: none, another sign-in's or a broken one is no key") {
        let record = ConnectionEnding.endingKeyRecord(session: "s1", handle: Data([0x0A, 7]))
        try expectEqual(ConnectionEnding.endingKeyHandle(recorded: record, session: "s1"), Data([0x0A, 7]))
        try expectEqual(ConnectionEnding.endingKeyHandle(recorded: nil, session: "s1"), nil)
        try expectEqual(ConnectionEnding.endingKeyHandle(recorded: record, session: "s2"), nil)
        try expectEqual(ConnectionEnding.endingKeyHandle(recorded: record, session: "s"), nil)
        try expectEqual(ConnectionEnding.endingKeyHandle(recorded: Data("s1".utf8), session: "s1"), nil)
        try expectEqual(ConnectionEnding.endingKeyHandle(recorded: ConnectionEnding.endingKeyRecord(session: "s1", handle: Data()), session: "s1"), nil)
        try expectEqual(ConnectionEnding.endingKeyHandle(recorded: record, session: ""), nil)
        try expectEqual(ConnectionEnding.confirmation(tenant: "t_01", ids: ["g_01"]), Data("tafs.disconnect.v1|t_01|g_01".utf8))
    },
    Test("at sign-in: the old ending key goes, and a new one is made only beside a Secure Enclave key with Touch ID") {
        let kept = KeptKey()
        kept.record = ConnectionEnding.endingKeyRecord(session: "old", handle: Data([1]))
        var made = 0
        ConnectionEnding.keepEndingKey(session: "s1", enclave: true, biometrics: { true }, create: { made += 1; return Data([9]) },
                                       save: kept.save, remove: kept.remove)
        try expectEqual(made, 1)
        try expectEqual(ConnectionEnding.endingKeyHandle(recorded: kept.record, session: "s1"), Data([9]))
        // A software key, or no Touch ID: none made, and the one before is gone.
        for (enclave, biometrics) in [(false, true), (true, false), (false, false)] {
            kept.record = ConnectionEnding.endingKeyRecord(session: "old", handle: Data([1]))
            ConnectionEnding.keepEndingKey(session: "s1", enclave: enclave, biometrics: { biometrics }, create: { made += 1; return Data([9]) },
                                           save: kept.save, remove: kept.remove)
            try expectEqual(kept.record, nil)
        }
        try expectEqual(made, 1)
        // A key that can't be made, or kept: none, and the sign-in goes on.
        ConnectionEnding.keepEndingKey(session: "s1", enclave: true, biometrics: { true }, create: { throw Refused() },
                                       save: kept.save, remove: kept.remove)
        try expectEqual(kept.record, nil)
        ConnectionEnding.keepEndingKey(session: "s1", enclave: true, biometrics: { true }, create: { Data([9]) },
                                       save: { _ in throw Refused() }, remove: kept.remove)
        try expectEqual(kept.record, nil)
        ConnectionEnding.keepEndingKey(session: "s1", enclave: true, biometrics: { true }, create: { Data() }, save: kept.save, remove: kept.remove)
        try expectEqual(kept.record, nil)
    },
    Test("Touch ID's check reads only: no ending key, another sign-in's, or one that doesn't load is the phone", awaiting: {
        let kept = KeptKey()
        var loads = true
        var biometrics = true
        let check = kept.check(session: "s1", biometrics: { biometrics }, loads: { _ in loads })
        // No record: the phone (a session from before the ending key has none).
        try expect(!check.available(), "no record")
        try expectEqual(ConnectionEnding.route(enclaveKey: true, biometrics: check.available()), .phone)
        kept.record = ConnectionEnding.endingKeyRecord(session: "s2", handle: Data([9]))
        try expect(!check.available(), "another sign-in's")
        kept.record = ConnectionEnding.endingKeyRecord(session: "s1", handle: Data([9]))
        try expect(check.available(), "this sign-in's")
        try expectEqual(ConnectionEnding.route(enclaveKey: true, biometrics: check.available()), .touchID)
        loads = false
        try expect(!check.available(), "a key that doesn't load")
        loads = true
        biometrics = false
        try expect(!check.available(), "Touch ID that can't be checked")
        // Reading writes nothing, and deletes nothing.
        try expectEqual(kept.writes + kept.removes, 0)
        try expectEqual(kept.record, ConnectionEnding.endingKeyRecord(session: "s1", handle: Data([9])))
        // No key: confirming throws before anything is asked.
        kept.record = nil
        var asked = 0
        do { try await kept.check(session: "s1", sign: { _, _, _ in asked += 1 }).confirm("?", Data()); throw Failure(description: "passed") }
        catch is ConnectionEnding.KeyGone {}
        try expectEqual(asked, 0)
    }),
    Test("a key the system invalidated (fingers changed) is deleted, sends nothing and says to use the phone; a closed prompt keeps it", awaiting: {
        let kept = KeptKey()
        kept.record = ConnectionEnding.endingKeyRecord(session: "s1", handle: Data([9]))
        var signed: [(Data, String, Data)] = []
        let passes = kept.check(session: "s1", sign: { signed.append(($0, $1, $2)) })
        try await passes.confirm("Remove access?", Data("m".utf8))
        try expectEqual(signed.map(\.0), [Data([9])])
        try expectEqual(signed.map(\.1), ["Remove access?"])
        try expectEqual(signed.map(\.2), [Data("m".utf8)])
        // Closed, failed or locked out: nothing sent, the key stays, Disconnect is silent and Clear not done.
        var sent: [String] = []
        let closed = kept.check(session: "s1", sign: { _, _, _ in throw OwnerPrompt.Closed() })
        let out = await ConnectionEnding.end(["a"], tenant: "t", prompt: "?", confirm: closed.confirm, delete: { sent.append($0) }, current: { true }, english)
        try expect(sent.isEmpty && out.unconfirmed && !out.phone, "nothing sent: \(out)")
        try expectEqual(ConnectionEnding.disconnectNote(out, english), nil)
        try expectEqual(ConnectionEnding.clearNote(out, ending: 1, keptFor: [], english), "Not done: it wasn't confirmed.")
        try expect(closed.available(), "the key stays")
        // Invalidated: deleted, nothing sent, and the phone's line, until the next sign-in.
        let gone = kept.check(session: "s1", sign: { _, _, _ in throw ConnectionEnding.KeyGone() })
        let lost = await ConnectionEnding.end(["a"], tenant: "t", prompt: "?", confirm: gone.confirm, delete: { sent.append($0) }, current: { true }, english)
        try expect(sent.isEmpty && lost.unconfirmed && lost.phone, "nothing sent: \(lost)")
        try expectEqual(kept.record, nil)
        try expect(!gone.available(), "the phone now")
        let phone = english(ConnectionEnding.phoneLine)
        try expectEqual(ConnectionEnding.disconnectNote(lost, english), phone)
        try expectEqual(ConnectionEnding.clearNote(lost, ending: 1, keptFor: [], english), phone)
        // A newer sign-in's key, kept meanwhile, isn't the one deleted.
        kept.record = ConnectionEnding.endingKeyRecord(session: "s1", handle: Data([9]))
        let racing = kept.check(session: "s1", sign: { _, _, _ in
            kept.record = ConnectionEnding.endingKeyRecord(session: "s1", handle: Data([8]))
            throw ConnectionEnding.KeyGone()
        })
        do { try await racing.confirm("?", Data()); throw Failure(description: "passed") } catch is ConnectionEnding.KeyGone {}
        try expectEqual(ConnectionEnding.endingKeyHandle(recorded: kept.record, session: "s1"), Data([8]))
    }),
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

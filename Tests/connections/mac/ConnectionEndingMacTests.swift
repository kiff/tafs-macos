import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

/// A Mac whose key is in the Secure Enclave (or not), with Touch ID (or not), counting what it asks and sends.
@MainActor
private func make(enclave: Bool, touchID: Bool, passes: Bool = true) -> (ConnectAppsModel, CannedTransport, () -> [String], () -> [String]) {
    // The ending itself is `end`; planque's transport carries only the read again, a signed GET.
    let planque = CannedTransport([(200, #"{"grants":[]}"#)])
    var asked: [String] = []
    var ended: [String] = []
    let source = ConnectionsSource(transport: planque, tenant: "t1", proof: { "t=1,v1=c2ln,d=dev_1" }, enclaveKey: enclave, end: { ended.append($0) })
    let check = TouchIDOnly(available: { touchID }, confirm: { reason, _ in
        asked.append(reason)
        if !passes { throw OwnerPrompt.Closed() }
    })
    let cloud = CannedTransport([(200, #"{"apps":[]}"#)])
    return (ConnectAppsModel(cloud: CloudClient(transport: cloud, session: session), connections: source, touchID: check), planque, { asked }, { ended })
}

/// A device key that says it's in the Secure Enclave, for sign-in's ending key.
private struct EnclaveLike: SigningKey {
    let key = SoftwareKey(key: .init())
    var publicKeyDER: Data { key.publicKeyDER }
    var keyStore: String { "enclave" }
    func sign(_ message: Data) throws -> Data { try key.sign(message) }
}

/// Ending a connection from this Mac (`ConnectionEnding`, docs/approvals.md).
let connectionEndingMacTests: [Test] = [
    Test("a Mac without Touch ID, or whose key isn't in the Secure Enclave, asks nothing and sends nothing: the phone", awaiting: { @MainActor in
        for (enclave, touchID) in [(true, false), (false, true), (false, false)] {
            let (model, _, asked, ended) = make(enclave: enclave, touchID: touchID)
            try expectEqual(model.endRoute, .phone)
            await model.disconnect("g1", prompt: "Remove access to Qonto?", id: "g1|end")
            await model.clear(["g1"])
            try expect(asked().isEmpty && ended().isEmpty, "nothing asked or sent: \(enclave) \(touchID)")
            // A click that finds the phone's route says so, never nothing.
            let phone = Words.app(ConnectionEnding.phoneLine)
            try expectEqual(model.notes, ["g1|end": phone, "clear": phone])
        }
        // No source that can end one: the phone too.
        let bare = ConnectAppsModel(cloud: CloudClient(transport: CannedTransport([]), session: session), touchID: TouchIDOnly(available: { true }, confirm: { _, _ in }))
        try expectEqual(bare.endRoute, .phone)
    }),
    Test("a Touch ID Mac asks Touch ID with the question, then ends the connection and reads them again", awaiting: { @MainActor in
        let (model, planque, asked, ended) = make(enclave: true, touchID: true)
        try expectEqual(model.endRoute, .touchID)
        await model.disconnect("g1", prompt: "Remove access to Qonto?", id: "g1|end")
        try expectEqual(asked(), ["Remove access to Qonto?"])
        try expectEqual(ended(), ["g1"])
        try expectEqual(model.notes["g1|end"], nil)
        try expect(model.ending.isEmpty, "done")
        try expectEqual(planque.sent.map { $0.method + " " + $0.path }, ["GET /v1/accounts/t1/grants"])
    }),
    Test("a key the system invalidated since sign-in (a finger added): nothing sent, the key deleted, and the phone", awaiting: { @MainActor in
        let store = MemoryStore()
        let binding = EndingKey.binding(session)
        try store.save(ConnectionEnding.endingKeyRecord(session: binding, handle: Data([9])), for: EndingKey.account)
        var signed: [Data] = []
        var invalidated = false
        var ended: [String] = []
        let check = TouchIDOnly.checked(ConnectionEnding.EndingKeyCheck(
            session: binding, read: { store.load(EndingKey.account) }, remove: { store.delete(EndingKey.account) },
            biometrics: { true }, loads: { _ in true }, sign: { _, _, message in
                if invalidated { throw ConnectionEnding.KeyGone() }
                signed.append(message)
            }))
        let source = ConnectionsSource(transport: CannedTransport([(200, #"{"grants":[]}"#)]), tenant: "t1", proof: { nil }, enclaveKey: true,
                                       end: { ended.append($0) })
        let model = ConnectAppsModel(cloud: CloudClient(transport: CannedTransport([(200, #"{"apps":[]}"#)]), session: session),
                                     connections: source, touchID: check)
        try expectEqual(model.endRoute, .touchID)
        await model.disconnect("g1", prompt: "Remove access to Qonto?", id: "g1|end")
        try expectEqual(signed, [Data("tafs.disconnect.v1|t1|g1".utf8)])
        try expectEqual(ended, ["g1"])
        invalidated = true
        await model.disconnect("g2", prompt: "Remove access to Qonto?", id: "g2|end")
        try expectEqual(ended, ["g1"])
        try expectEqual(store.load(EndingKey.account), nil)
        try expectEqual(model.endRoute, .phone)
        try expectEqual(model.notes["g2|end"], Words.app(ConnectionEnding.phoneLine))
    }),
    Test("no ending key, or another sign-in's, is the phone; reading it writes nothing", awaiting: { @MainActor in
        let store = MemoryStore()
        let source = ConnectionsSource(transport: CannedTransport([]), tenant: "t1", proof: { nil }, enclaveKey: true, end: { _ in })
        let model = ConnectAppsModel(cloud: CloudClient(transport: CannedTransport([]), session: session), connections: source,
                                     touchID: .system(session: session, store: store))
        try expectEqual(model.endRoute, .phone)
        try expectEqual(store.load(EndingKey.account), nil)
        let other = Session(accessToken: "another", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
        let theirs = ConnectionEnding.endingKeyRecord(session: EndingKey.binding(other), handle: Data([9]))
        try store.save(theirs, for: EndingKey.account)
        model.refreshRoute()
        try expectEqual(model.endRoute, .phone)
        try expectEqual(store.load(EndingKey.account), theirs)
    }),
    Test("the ending key is made at sign-in beside a Secure Enclave device key, and sign-out deletes it", awaiting: { @MainActor in
        let store = MemoryStore()
        var made = 0
        let hook = EndingKeyHook(kept: { got, keyStore in
            ConnectionEnding.keepEndingKey(session: EndingKey.binding(got), enclave: keyStore == "enclave", biometrics: { true },
                                           create: { made += 1; return Data([9]) },
                                           save: { try store.save($0, for: EndingKey.account) }, remove: { store.delete(EndingKey.account) })
        }, forgotten: { store.delete(EndingKey.account) })
        let start = #"{"device_code":"dc","user_code":"ABCD-EFGH","verification_uri":"https://app.kiff.dev/device","verification_uri_complete":"https://app.kiff.dev/device?code=ABCD-EFGH","expires_in":600,"interval":5}"#
        let granted = #"{"access_token":"tok2","token_type":"Bearer","expires_in":60,"tenant":"t1","subject":"u1","device_id":"dev_1"}"#
        let model = SignInModel(client: KIFFClient(transport: CannedTransport([(200, start), (200, granted)])), key: EnclaveLike(),
                                approval: .passkey, sessions: SessionStore(store: store), deviceName: "A Mac", sleep: { _ in }, open: { _ in },
                                onboarding: false, endingKey: hook)
        await model.signIn()
        guard let got = model.session else { throw Failure(description: "no session") }
        try expectEqual(made, 1)
        try expectEqual(ConnectionEnding.endingKeyHandle(recorded: store.load(EndingKey.account), session: EndingKey.binding(got)), Data([9]))
        model.signedOut()
        try expectEqual(store.load(EndingKey.account), nil)
    }),
    Test("signed out while Touch ID was asking: nothing is sent and nothing read again", awaiting: { @MainActor in
        var ended: [String] = []
        let planque = CannedTransport([])
        let source = ConnectionsSource(transport: planque, tenant: "t1", proof: { "t=1,v1=c2ln,d=dev_1" }, enclaveKey: true, end: { ended.append($0) })
        var model: ConnectAppsModel?
        let check = TouchIDOnly(available: { true }, confirm: { _, _ in model?.endSession() })
        model = ConnectAppsModel(cloud: CloudClient(transport: CannedTransport([]), session: session), connections: source, touchID: check)
        await model?.disconnect("g1", prompt: "Remove access to Qonto?", id: "g1|end")
        try expect(ended.isEmpty && planque.sent.isEmpty, "nothing sent")
        try expectEqual(model?.notes ?? [:], [:])
        // Ended: nothing more starts.
        await model?.clear(["g1"])
        try expect(ended.isEmpty, "nothing sent")
    }),
    Test("a closed Touch ID prompt sends nothing and Disconnect says nothing", awaiting: { @MainActor in
        let (model, _, asked, ended) = make(enclave: true, touchID: true, passes: false)
        await model.disconnect("g1", prompt: "Remove access to Qonto?", id: "g1|end")
        try expectEqual(asked().count, 1)
        try expect(ended().isEmpty, "nothing sent")
        try expectEqual(model.notes["g1|end"], nil)
    }),
]

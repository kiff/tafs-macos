import Foundation

private let startAnswer = #"{"device_code":"dc","user_code":"ABCD-EFGH","verification_uri":"https://app.kiff.dev/device","verification_uri_complete":"https://app.kiff.dev/device?code=ABCD-EFGH","expires_in":600,"interval":5}"#
private let sessionAnswer = #"{"access_token":"tok","token_type":"Bearer","expires_in":60,"tenant":"t1","subject":"u1","device_id":"dev_1"}"#
private let pending = (400, #"{"error":"authorization_pending"}"#)

@MainActor
private func model(_ answers: [(Int, String)], store: MemoryStore = MemoryStore(), opened: @escaping (URL) -> Void = { _ in }) throws -> (SignInModel, CannedTransport) {
    let transport = CannedTransport(answers)
    let key = try DeviceKey.load(from: store, enclave: false)
    let model = SignInModel(client: KIFFClient(transport: transport), key: key, approval: .passkey, sessions: SessionStore(store: store),
                            deviceName: "A Mac", sleep: { _ in }, open: opened, now: { Date(timeIntervalSince1970: 1_794_679_200) })
    return (model, transport)
}

let pairingModelTests: [Test] = [
    Test("a new session and a sign-out each leave no exported chats on this Mac", awaiting: { @MainActor in
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("export-signin-\(UUID().uuidString)", isDirectory: true)
        let (model, _) = try model([(200, startAnswer), (200, sessionAnswer)])
        model.exportFolder = folder
        _ = try ChatsExport.write((json: Data("{}".utf8), text: "chats"), in: folder)
        await model.signIn()
        try expectEqual(model.session?.tenant, "t1")
        try expectEqual(FileManager.default.fileExists(atPath: folder.path), false)
        _ = try ChatsExport.write((json: Data("{}".utf8), text: "chats"), in: folder)
        model.signedOut()
        try expectEqual(FileManager.default.fileExists(atPath: folder.path), false)
    }),
    Test("a read KIFF refuses with 401 forgets the session once, and sign-in opens; a newer session stays", awaiting: { @MainActor in
        let store = MemoryStore()
        let (model, _) = try model([(200, startAnswer), (200, sessionAnswer)], store: store)
        await model.signIn()
        guard let session = model.session else { throw Failure(description: "no session") }
        let watch = model.sessionWatch(session)
        try expect(model.sessionWatch(session) === watch, "one watch for the session, however often the window is made")
        // The window's reads, through the watch: KIFF refuses the stored sign-in.
        let reads = WatchedTransport(inner: CannedTransport([(401, #"{"error":"unauthorized"}"#), (401, "{}")]), watch: watch)
        let header = ["Authorization": "Bearer \(session.accessToken)"]
        _ = try await reads.send(HTTPRequest(method: "GET", path: "/v1/me", headers: header))
        _ = try await reads.send(HTTPRequest(method: "GET", path: "/v1/home", headers: header))
        for _ in 0..<50 where model.session != nil { await Task.yield() }
        try expect(model.session == nil, "signed out")
        try expect(SessionStore(store: store).load() == nil, "and forgotten in the store")
        try expectEqual(model.step, .welcome)

        // A refusal for a session this Mac has since replaced changes nothing.
        let (other, _) = try model([(200, startAnswer), (200, sessionAnswer)])
        await other.signIn()
        other.sessionRefused("an older token")
        try expect(other.session != nil)
    }),
    Test("signing in opens KIFF's page, waits, and keeps the session", awaiting: { @MainActor in
        var opened: [URL] = []
        let store = MemoryStore()
        let (model, transport) = try model([(200, startAnswer), pending, (200, sessionAnswer)], store: store) { opened.append($0) }
        await model.signIn()
        try expectEqual(opened.map(\.absoluteString), ["https://app.kiff.dev/device?code=ABCD-EFGH"])
        try expectEqual(transport.sent.map(\.path), ["/v1/auth/device/start", "/v1/auth/device/token", "/v1/auth/device/token"])
        try expectEqual(model.session?.tenant, "t1")
        try expectEqual(SessionStore(store: store).load()?.accessToken, "tok")
        try expectEqual(model.step, .welcome)
    }),
    Test("a page that isn't KIFF's over HTTPS is never opened", awaiting: { @MainActor in
        for page in ["http://app.kiff.dev/device", "https://kiff.dev.example.com/device", "file:///etc/passwd"] {
            var opened = 0
            let start = startAnswer.replacingOccurrences(of: "https://app.kiff.dev/device?code=ABCD-EFGH", with: page)
            let (model, _) = try model([(200, start), (200, sessionAnswer)]) { _ in opened += 1 }
            await model.signIn()
            try expectEqual(opened, 0)
        }
    }),
    Test("a sign-in that can't start says why, and keeps no session", awaiting: { @MainActor in
        let (model, _) = try model([(403, #"{"error":"platform_not_allowed"}"#)])
        await model.signIn()
        try expectEqual(model.step, .failed(why: "platform_not_allowed", pairing: false))
        try expectEqual(model.session, nil)
    }),
    Test("pairing shows this Mac's keys and check code, and claims with a proof by the device key", awaiting: { @MainActor in
        let store = MemoryStore()
        let key = try DeviceKey.load(from: store, enclave: false)
        let (model, transport) = try model([pending, (200, sessionAnswer)], store: store)
        var shown: SignInModel.Code?
        let watching = model.$step.sink { if case .pairing(let code) = $0 { shown = code } }
        await model.pair()
        watching.cancel()
        guard let shown else { throw Failure(description: "no code was shown") }
        let payload = try JSONDecoder().decode(PairingPayload.self, from: Data(shown.text.utf8))
        try expectEqual(payload.pub, Encoding.base64URL(key.publicKeyDER))
        try expectEqual(payload.approvalPub, nil)
        try expectEqual(payload.kind, .passkey)
        try expectEqual(payload.keyStore, "software")
        try expect(shown.text.contains(#""key_store":"software""#), shown.text)
        try expectEqual(payload.name, "A Mac")
        try expectEqual(payload.exp, "2026-11-14T18:05:00Z")
        try expectEqual(shown.check, Signing.checkCode(deviceKey: key.publicKeyDER, approvalKey: nil))
        let claim = try JSONDecoder().decode([String: String].self, from: transport.sent[1].body)
        try expectEqual(claim["nonce"], payload.nonce)
        try expectEqual(claim["pub"], payload.pub)
        let message = KIFFMessage.pairClaim(nonce: payload.nonce, keyHash: Signing.sha256Hex(key.publicKeyDER))
        try expect(Signing.verifies(claim["proof"] ?? "", over: message, publicKeyDER: key.publicKeyDER), "the proof verifies")
        try expectEqual(model.session?.deviceID, "dev_1")
    }),
    Test("a pairing code that runs out says so, and a refused proof is a failure, with no session either way", awaiting: { @MainActor in
        let (expired, _) = try model([(400, #"{"error":"expired_token"}"#)])
        await expired.pair()
        try expectEqual(expired.step, .codeExpired)
        let (refused, _) = try model([(403, #"{"error":"invalid_proof"}"#)])
        await refused.pair()
        try expectEqual(refused.step, .failed(why: "invalidProof", pairing: true))
        try expectEqual(expired.session ?? refused.session, nil)
    }),
    Test("each pairing code has a new nonce", awaiting: { @MainActor in
        let (model, transport) = try model([(400, #"{"error":"expired_token"}"#), (400, #"{"error":"expired_token"}"#)])
        await model.pair()
        await model.pair()
        let nonces = try transport.sent.map { try JSONDecoder().decode([String: String].self, from: $0.body)["nonce"] }
        try expectEqual(nonces.count, 2)
        try expect(nonces[0] != nonces[1], "two nonces")
    }),
    Test("a session kept from the last launch is there at the next, and signing out forgets it", awaiting: { @MainActor in
        let store = MemoryStore()
        let (first, _) = try model([(200, startAnswer), (200, sessionAnswer)], store: store)
        await first.signIn()
        let (second, _) = try model([], store: store)
        try expectEqual(second.session?.accessToken, "tok")
        second.signedOut()
        try expectEqual(second.session, nil)
        try expectEqual(SessionStore(store: store).load(), nil)
    }),
]

private let viewOnly = Session(accessToken: "old", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_view")

/// A Mac that is already signed in, view-only, with its device key and session kept.
@MainActor
private func signedIn(_ answers: [(Int, String)]) throws -> (SignInModel, CannedTransport, MemoryStore, SigningKey, () -> [(String, Data)]) {
    let store = MemoryStore()
    let oldKey = try DeviceKey.load(from: store, enclave: false)
    try SessionStore(store: store).save(viewOnly)
    let transport = CannedTransport(answers)
    var ended: [(String, Data)] = []
    let model = SignInModel(client: KIFFClient(transport: transport), key: oldKey, approval: .passkey, sessions: SessionStore(store: store),
                            deviceName: "A Mac", sleep: { _ in }, open: { _ in }, now: { Date(timeIntervalSince1970: 1_794_679_200) },
                            enclave: false, endSession: { session, key in ended.append((session.accessToken, key.publicKeyDER)) })
    return (model, transport, store, oldKey, { ended })
}

let pairingFreshKeyTests: [Test] = [
    Test("a signed-in Mac pairs with a new device key, never the one KIFF already has", awaiting: { @MainActor in
        let (model, transport, store, oldKey, ended) = try signedIn([pending, (200, sessionAnswer)])
        var shown: SignInModel.Code?
        let watching = model.$step.sink { if case .pairing(let code) = $0 { shown = code } }
        await model.pair()
        watching.cancel()
        guard let shown else { throw Failure(description: "no code was shown") }
        let payload = try JSONDecoder().decode(PairingPayload.self, from: Data(shown.text.utf8))
        try expect(payload.pub != Encoding.base64URL(oldKey.publicKeyDER), "the code carries a new key")
        try expectEqual(payload.pub, Encoding.base64URL(model.key.publicKeyDER))
        // The claim's proof is the new key's, and the new key is now the device key kept.
        let claim = try JSONDecoder().decode([String: String].self, from: transport.sent[1].body)
        let message = KIFFMessage.pairClaim(nonce: payload.nonce, keyHash: Signing.sha256Hex(model.key.publicKeyDER))
        try expect(Signing.verifies(claim["proof"] ?? "", over: message, publicKeyDER: model.key.publicKeyDER), "the new key's proof")
        try expectEqual(try DeviceKey.load(from: store, enclave: false).publicKeyDER, model.key.publicKeyDER)
        try expectEqual(store.load(DeviceKey.nextAccount), nil)
        // The new session is kept; the old one is ended with the old key, once, afterwards.
        try expectEqual(model.session?.accessToken, "tok")
        try expectEqual(SessionStore(store: store).load()?.accessToken, "tok")
        try expectEqual(ended().count, 1)
        try expectEqual(ended()[0].0, "old")
        try expectEqual(ended()[0].1, oldKey.publicKeyDER)
    }),
    Test("if the pairing doesn't happen, the old session and its key stay, and nothing is signed out", awaiting: { @MainActor in
        for answer in [(400, #"{"error":"expired_token"}"#), (403, #"{"error":"invalid_proof"}"#), (500, "")] {
            let (model, _, store, oldKey, ended) = try signedIn([answer])
            await model.pair()
            try expectEqual(ended().count, 0)
            try expectEqual(model.session, viewOnly)
            try expectEqual(SessionStore(store: store).load(), viewOnly)
            try expectEqual(model.key.publicKeyDER, oldKey.publicKeyDER)
            try expectEqual(try DeviceKey.load(from: store, enclave: false).publicKeyDER, oldKey.publicKeyDER)
            try expectEqual(store.load(DeviceKey.nextAccount), nil)
        }
    }),
    Test("a cancelled pairing leaves the old session, forgets the new key, and signs nothing out", awaiting: { @MainActor in
        let (model, _, store, oldKey, ended) = try signedIn([pending, (200, sessionAnswer)])
        let watching = model.$step.sink { if case .pairing = $0 { model.cancel() } }
        await model.pair()
        watching.cancel()
        try expectEqual(ended().count, 0)
        try expectEqual(model.session, viewOnly)
        try expectEqual(model.key.publicKeyDER, oldKey.publicKeyDER)
        try expectEqual(store.load(DeviceKey.nextAccount), nil)
    }),
    Test("a Mac with no session still pairs with its own device key", awaiting: { @MainActor in
        let store = MemoryStore()
        let key = try DeviceKey.load(from: store, enclave: false)
        let (model, _) = try model([(200, sessionAnswer)], store: store)
        await model.pair()
        try expectEqual(model.key.publicKeyDER, key.publicKeyDER)
        try expectEqual(store.load(DeviceKey.nextAccount), nil)
    }),
]

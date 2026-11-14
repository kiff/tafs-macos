import Foundation

let accountSessionTests: [Test] = [
    Test("the session is kept, read back, and forgotten") {
        let sessions = SessionStore(store: MemoryStore())
        try expectEqual(sessions.load(), nil)
        let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")
        try sessions.save(session)
        try expectEqual(sessions.load(), session)
        sessions.forget()
        try expectEqual(sessions.load(), nil)
    },
    Test("a signed-in Mac's signed request verifies with its device key, over the bytes sent", awaiting: {
        let key = try DeviceKey.load(from: MemoryStore(), enclave: false)
        let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
        let transport = CannedTransport([(200, "{}")])
        let account = AccountClient(session: session, key: key, language: "en", transport: transport)
        let body = Data(#"{"a":1}"#.utf8)
        _ = try await account.send("POST", "/v1/me/window/win_a/close?x=1", body: body, signed: true)
        let header = transport.sent[0].headers["KIFF-Device-Signature"] ?? ""
        let parts = header.split(separator: ",").map(String.init)
        try expectEqual(parts.count, 2)
        let message = KIFFMessage.request(tenant: "t1", method: "POST", path: "/v1/me/window/win_a/close?x=1",
                                          bodyHash: Signing.sha256Hex(body), signedAt: String(parts[0].dropFirst(2)))
        try expect(Signing.verifies(String(parts[1].dropFirst(3)), over: message, publicKeyDER: key.publicKeyDER), "verifies")
    }),
]

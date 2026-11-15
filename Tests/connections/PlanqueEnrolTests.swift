import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t_01", subject: "u1", deviceID: "dev_9")
private let deviceKey = Data([1, 2, 3])
private let route = "/v1/accounts/t_01/enrolment"
private let minted = #"{"id":"key_c","plaintext":"kiff_live_connector","roles":["connector"]}"#

/// A transport planque never answers: not reached.
private struct Unreached: Transport {
    struct Down: Error {}
    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) { throw Down() }
}

/// planque and KIFF as stubs, each with its answers; what the device key signed is kept.
private final class Stubs {
    let planque: PlanqueClient
    let planqueSent: CannedTransport
    let kiff: CannedTransport
    let account: AccountClient
    var signed: [String] = []

    init(planque answers: [(Int, String)], kiff: [(Int, String)] = [], transport: Transport? = nil, cancelOnMint: Bool = false) {
        planqueSent = CannedTransport(answers)
        self.kiff = CannedTransport(kiff)
        account = AccountClient(transport: cancelOnMint ? CancelOnMint(self.kiff) : self.kiff, session: session, sign: { _ in "t=x,v1=SIG" })
        planque = PlanqueClient(baseURL: "https://planque.test/")
        planque.tenant = "t_01"
        planque.deviceID = "dev_9"
        planque.transport = transport ?? planqueSent
        planque.bodyHash = { "hash(\(String(decoding: $0, as: UTF8.self)))" }
        planque.signer = { [unowned self] message in signed.append(message); return "SIG" }
    }

    func enrol() async -> PlanqueEnrolment.Stop? {
        await PlanqueEnrolment.enrol(planque: planque, account: account, deviceKey: deviceKey)
    }

    /// The connector keys handed to planque, one per enrolment sent: nil asks only.
    var keysHanded: [String?] {
        planqueSent.sent.map { (try? JSONSerialization.jsonObject(with: $0.body) as? [String: String])?["connector_key"] }
    }

    var mints: Int { kiff.sent.filter { $0.path == "/v1/keys" }.count }
}

/// KIFF, which cancels the task that minted, right after the mint: as a sign-out at that moment.
private final class CancelOnMint: Transport, @unchecked Sendable {
    let inner: CannedTransport
    init(_ inner: CannedTransport) { self.inner = inner }
    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        let answer = try await inner.send(request)
        if request.path == "/v1/keys" { withUnsafeCurrentTask { $0?.cancel() } }
        return answer
    }
}

let planqueEnrolTests: [Test] = [
    Test("a kept enrolment mints no connector key: asked once with no key, signed with this device's id, as the iPad's", awaiting: {
        let stubs = Stubs(planque: [(200, #"{"tenant":"t_01","device":"ab12","kept":true}"#)], kiff: [(201, minted)])
        let stop = await stubs.enrol()
        try expectEqual(stop, nil)
        try expectEqual(stubs.mints, 0)
        try expectEqual(stubs.keysHanded, [nil])
        let sent = stubs.planqueSent.sent[0]
        try expectEqual(sent.method + " " + sent.path, "POST " + route)
        try expectEqual(String(decoding: sent.body, as: UTF8.self), #"{"device_key":"AQID"}"#)
        // planque's message for exactly the body sent: the base without its slash, the tenant, the
        // method, the path as sent, the body's hash and the time.
        guard let header = sent.headers["Planque-Device-Signature"], let at = header.split(separator: ",").first?.dropFirst(2) else {
            throw Failure(description: "unsigned")
        }
        try expectEqual(header, "t=\(at),v1=SIG,d=dev_9")
        try expectEqual(stubs.signed, [PlanqueClient.message(base: "https://planque.test/", tenant: "t_01", method: "POST", uri: route,
                                                             bodyHash: #"hash({"device_key":"AQID"})"#, signedAt: String(at))])
    }),
    Test("with no standing key (409 needs_key), one key is minted with a signed setup call and handed over", awaiting: {
        let stubs = Stubs(planque: [(409, #"{"error":"no connector key stands for this account","code":"needs_key"}"#),
                                    (201, #"{"tenant":"t_01","device":"ab12"}"#)], kiff: [(201, minted)])
        let stop = await stubs.enrol()
        try expectEqual(stop, nil)
        try expectEqual(stubs.mints, 1)
        try expectEqual(stubs.keysHanded, [nil, "kiff_live_connector"])
        let mint = stubs.kiff.sent[0]
        try expectEqual(mint.method + " " + mint.path, "POST /v1/keys")
        try expectEqual(String(decoding: mint.body, as: UTF8.self), #"{"label":"planque","roles":["connector"]}"#)
        try expectEqual(mint.headers["KIFF-Device-Signature"], "t=x,v1=SIG")
        // Both enrolments are signed.
        try expectEqual(stubs.signed.count, 2)
    }),
    Test("an enrolment answered 2xx without kept mints nothing, and says it isn't set up (Windows #63, Android)", awaiting: {
        let stubs = Stubs(planque: [(201, #"{"tenant":"t_01","device":"ab12"}"#), (201, #"{"tenant":"t_01","device":"ab12"}"#)],
                          kiff: [(201, minted)])
        let stop = await stubs.enrol()
        try expectEqual(stop, .notSetUp(why: .unreadable))
        try expectEqual(stubs.mints, 0)
        try expectEqual(stubs.keysHanded, [nil])
    }),
    Test("a key once minted is handed to planque even when the task ends right after the mint, then it ends", awaiting: {
        let stubs = Stubs(planque: [(409, #"{"error":"needs a key","code":"needs_key"}"#), (201, #"{"tenant":"t_01","device":"ab12","kept":true}"#)],
                          kiff: [(201, minted)], cancelOnMint: true)
        let stop = await Task { await stubs.enrol() }.value
        try expectEqual(stubs.mints, 1)
        try expectEqual(stubs.keysHanded, [nil, "kiff_live_connector"])
        try expectEqual(stop, .ended)
    }),
    Test("planque not reached, a 400, a 5xx, a replayed signature or a changed enrolment mints nothing, and says why, never another device", awaiting: {
        let failures: [(String, (Int, String)?)] = [
            ("not reached", nil),
            ("400", (400, #"{"error":"bad request"}"#)),
            ("503", (503, #"{"error":"unavailable"}"#)),
            ("replayed", (409, #"{"error":"this signature was already used","code":"signature_replayed"}"#)),
            ("changed", (409, #"{"error":"the enrolment changed","code":"enrolment_changed","words":"Another device set this up just now."}"#)),
        ]
        for (name, answer) in failures {
            let stubs = answer.map { Stubs(planque: [$0], kiff: [(201, minted)]) } ?? Stubs(planque: [], kiff: [(201, minted)], transport: Unreached())
            let stop = await stubs.enrol()
            try expectEqual(stubs.mints, 0)
            guard case .notSetUp = stop else { throw Failure(description: "\(name): \(String(describing: stop))") }
        }
        let changed = await Stubs(planque: [(409, #"{"code":"enrolment_changed","words":"Another device set this up just now."}"#)]).enrol()
        try expectEqual(changed, .notSetUp(why: .planque(status: 409, words: "Another device set this up just now.")))
    }),
    Test("an older planque's code-less 409 is another device's enrolment, first or second, and mints nothing the first time", awaiting: {
        let first = Stubs(planque: [(409, #"{"error":"another phone is enrolled"}"#)], kiff: [(201, minted)])
        let got1 = await first.enrol()
        try expectEqual(got1, .otherDevice)
        try expectEqual(first.mints, 0)
        let second = Stubs(planque: [(409, #"{"code":"needs_key"}"#), (409, #"{"error":"another phone is enrolled"}"#)], kiff: [(201, minted)])
        let got2 = await second.enrol()
        try expectEqual(got2, .otherDevice)
        // A coded 409 on the second says why.
        let coded = Stubs(planque: [(409, #"{"code":"needs_key"}"#), (409, #"{"code":"signature_replayed"}"#)], kiff: [(201, minted)])
        let got3 = await coded.enrol()
        try expectEqual(got3, .notSetUp(why: .planque(status: 409, words: nil)))
    }),
    Test("KIFF's 403 on the mint is admin only; another refusal says KIFF's plain line, and nothing is handed over", awaiting: {
        let admin = Stubs(planque: [(409, #"{"code":"needs_key"}"#)], kiff: [(403, #"{"error":"forbidden"}"#)])
        let got4 = await admin.enrol()
        try expectEqual(got4, .adminOnly)
        try expectEqual(admin.keysHanded, [nil])
        let down = Stubs(planque: [(409, #"{"code":"needs_key"}"#)], kiff: [(503, "")])
        let got5 = await down.enrol()
        try expectEqual(got5, .notSetUp(why: .kiff(status: 503)))
        let keyless = Stubs(planque: [(409, #"{"code":"needs_key"}"#)])
        let noKey = AccountClient(transport: keyless.kiff, session: session)
        let got6 = await PlanqueEnrolment.enrol(planque: keyless.planque, account: noKey, deviceKey: deviceKey)
        try expectEqual(got6, .notSetUp(why: .notSigning))
        try expectEqual(keyless.kiff.sent.count, 0)
    }),
    Test("no device id, or no signer, sends nothing to planque", awaiting: {
        let stubs = Stubs(planque: [(200, "{}")])
        stubs.planque.deviceID = nil
        let got7 = await stubs.enrol()
        try expectEqual(got7, .notSetUp(why: .noDevice))
        let unsigned = Stubs(planque: [(200, "{}")])
        unsigned.planque.signer = nil
        let got8 = await unsigned.enrol()
        try expectEqual(got8, .notSetUp(why: .notSigning))
        try expectEqual(stubs.planqueSent.sent.count + unsigned.planqueSent.sent.count, 0)
    }),
    Test("a session that ends while it runs does nothing more and says nothing, as the iPad's accountGeneration", awaiting: {
        let stubs = Stubs(planque: [(409, #"{"code":"needs_key"}"#), (201, "{}")], kiff: [(201, minted)])
        let run = Task { await stubs.enrol() }
        run.cancel()
        let got9 = await run.value
        try expectEqual(got9, .ended)
        try expectEqual(stubs.mints, 0)
    }),
    Test("each stop says the shared words, the why as the iPad's localizedDescription, never a code") {
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        try expectEqual(PlanqueEnrolment.Stop.otherDevice.words(words), "Another device connects this account's apps for now. Connect them from that one.")
        try expectEqual(PlanqueEnrolment.Stop.adminOnly.words(words), "Only an admin of this KIFF account can connect apps.")
        try expectEqual(PlanqueEnrolment.Stop.notSetUp(why: .planque(status: 409, words: "Another device set this up just now.")).words(words),
                        "Connecting apps isn't set up. Another device set this up just now.")
        try expectEqual(PlanqueEnrolment.Stop.notSetUp(why: .planque(status: 503, words: nil)).words(words),
                        "Connecting apps isn't set up. " + words("error.down"))
        try expectEqual(PlanqueEnrolment.Stop.notSetUp(why: .kiff(status: 401)).words(words), "Connecting apps isn't set up. " + words("error.signed_out"))
        try expectEqual(PlanqueEnrolment.Stop.ended.words(words), nil)
    },
]

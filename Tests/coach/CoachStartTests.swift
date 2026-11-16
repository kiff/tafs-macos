import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t_01", subject: "u1", deviceID: "dev_9")
private let coachRead = #"{"setup":{"id":"taf_setup","name":"Setup"}}"#
private let none = #"{"setup":null}"#
private let draft = #"{"id":"drf_1","agent_id":"setup","status":"confirmed","version":"v1","claim_secret":"sec_1"}"#
private let credential = Data([9, 9, 9])
private let up: UInt8 = 0x01, uv: UInt8 = 0x04

/// The security key's stand-in: kiff.dev's authenticator data with the flags given, and what it
/// was asked.
private final class StartKey: PasskeyAuthenticator {
    let flags: UInt8
    var failure: Error?
    var asked: [Data] = []
    var pins: [[UInt8]?] = []
    init(flags: UInt8 = up | uv) { self.flags = flags }
    func getAssertion(clientDataHash: Data, credentialID: Data, pin: SecurityKeyPIN?) async throws -> PasskeyAssertion {
        asked.append(clientDataHash)
        pins.append(pin?.heldBytesForTests())
        pin?.release()
        if let failure { throw failure }
        return PasskeyAssertion(authenticatorData: testSHA256(Data("kiff.dev".utf8)) + Data([flags, 0, 0, 0, 1]), signatureDER: Data("SIG".utf8))
    }
    func makeCredential(clientDataHash: Data, userID: Data, userName: String, pin: SecurityKeyPIN?) async throws -> PasskeyMade {
        throw PasskeyRefusal.unreadable
    }
}

/// tafs cloud, KIFF's device-key session and its security-key session, each with its answers;
/// what was asked, confirmed and enrolled, as a start sees them.
@MainActor
private final class Start {
    let cloud: CannedTransport
    let kiff: CannedTransport
    let passkeyKIFF: CannedTransport
    let key: StartKey
    var deviceSigned: [String] = []
    var sheets = 0
    var confirmed = 0
    var enrolled = 0
    var enrolStop: PlanqueEnrolment.Stop?
    var sheetCloses = false
    var confirmFails = false
    var confirmCloses = false
    var endsAt: Int?
    var checks = 0
    var enabled = true

    init(cloud: [(Int, String)], kiff: [(Int, String)] = [], passkey: [(Int, String)] = [], key: StartKey = StartKey()) {
        self.cloud = CannedTransport(cloud)
        self.kiff = CannedTransport(kiff)
        passkeyKIFF = CannedTransport(passkey)
        self.key = key
    }

    var account: AccountClient {
        AccountClient(transport: kiff, session: session, sign: { [unowned self] r in deviceSigned.append(r.path); return "t=x,v1=DEVICE" })
    }

    func passkeySession(_ present: Bool = true) -> PasskeySession? {
        guard present else { return nil }
        var approver = PasskeyApprover(authenticator: key, credentialID: credential, sha256: testSHA256)
        approver.enabled = enabled
        return PasskeySession(transport: passkeyKIFF, session: session, approver: approver)
    }

    func run(coach known: Coach? = nil, planqueReady: Bool = false, approval: Bool = true, signing: Bool = true) async throws -> (outcome: CoachStart.Outcome, planqueReady: Bool) {
        let device = signing ? account : AccountClient(transport: kiff, session: session)
        let passkey = passkeySession(approval)
        return await CoachStart.start(
            coach: known, planqueReady: planqueReady, cloud: CloudClient(transport: cloud, session: session), account: device,
            approval: passkey,
            sign: { [unowned self] body in
                sheets += 1
                if sheetCloses { throw CancellationError() }
                var typed: [UInt8] = Array("4821".utf8)
                return try await passkey!.signDraft(body, pin: try SecurityKeyPIN(utf8: &typed))
            },
            confirm: { [unowned self] in
                confirmed += 1
                if confirmCloses { throw OwnerPrompt.Closed() }
                if confirmFails { throw Failure(description: "failed") }
            },
            enrol: { [unowned self] _ in enrolled += 1; return enrolStop },
            ended: { [unowned self] in checks += 1; return endsAt.map { checks >= $0 } ?? false },
            words: try words())
    }
}

private func words(_ language: String = "en") throws -> Words { try Words(language: language, folder: URL(fileURLWithPath: ".shared/app/strings")) }

let coachStartTests: [Test] = [
    Test("Start on the security key's route: Setup read, the draft approved by the key over its exact bytes, planque, then the draft sent and claimed", awaiting: { @MainActor in
        let start = Start(cloud: [(200, none), (201, coachRead)], passkey: [(201, draft)])
        let (outcome, ready) = try await start.run()
        try expectEqual(outcome, .started(Coach(id: "taf_setup", name: "Setup")))
        try expectEqual(ready, true)
        try expectEqual([start.sheets, start.confirmed, start.enrolled], [1, 0, 1])
        try expectEqual(start.cloud.sent.map { $0.method + " " + $0.path }, ["GET /v1/setup", "POST /v1/setup"])
        // Setup's draft: no tools, approved by the security key, sent as `KIFF-Passkey-Assertion`.
        let sent = start.passkeyKIFF.sent
        try expectEqual(sent.map { $0.method + " " + $0.path }, ["POST /v1/me/agent-drafts"])
        let body = #"{"agent_id":"setup","label":"Setup","no_tools":true}"#
        try expectEqual(String(decoding: sent[0].body, as: UTF8.self), body)
        try expectEqual(sent[0].headers["KIFF-Device-Signature"], nil)
        let header = sent[0].headers["KIFF-Passkey-Assertion"] ?? ""
        try expect(header.hasPrefix("t=") && header.contains(",a="), header)
        // The key was asked once, over the challenge of exactly this request, at the header's time.
        let signedAt = String(header.split(separator: ",")[0].dropFirst(2))
        try expect(signedAt.contains("."), "milliseconds: \(signedAt)")
        let message = KIFFMessage.request(tenant: "t_01", method: "POST", path: "/v1/me/agent-drafts",
                                          bodyHash: Encoding.hex(testSHA256(Data(body.utf8))), signedAt: signedAt)
        let clientData = PasskeyApprover.clientDataJSON(Data(message.utf8), sha256: testSHA256)
        try expectEqual(start.key.asked, [testSHA256(clientData)])
        // The PIN reached the key once, as typed.
        try expectEqual(start.key.pins, [Array("4821".utf8)])
        // The device key signed nothing here, and KIFF's device session sent nothing.
        try expectEqual(start.deviceSigned, [])
        try expectEqual(start.kiff.sent.count, 0)
        try expectEqual(String(decoding: start.cloud.sent[1].body, as: UTF8.self), #"{"claim_secret":"sec_1","draft_id":"drf_1"}"#)
    }),
    Test("with Coach there and planque set up, Start asks nothing and sends nothing", awaiting: { @MainActor in
        let start = Start(cloud: [])
        let known = Coach(id: "taf_setup", name: "Setup")
        let (outcome, ready) = try await start.run(coach: known, planqueReady: true)
        try expectEqual(outcome, .started(known))
        try expectEqual(ready, true)
        try expectEqual([start.sheets, start.confirmed, start.enrolled, start.cloud.sent.count, start.passkeyKIFF.sent.count], [0, 0, 0, 0, 0])
    }),
    Test("with Coach there, only planque: the owner confirms, then it's enrolled; no sheet, nothing read or drafted", awaiting: { @MainActor in
        let start = Start(cloud: [])
        let known = Coach(id: "taf_setup", name: "Setup")
        let (outcome, ready) = try await start.run(coach: known)
        try expectEqual(outcome, .started(known))
        try expectEqual(ready, true)
        try expectEqual([start.sheets, start.confirmed, start.enrolled, start.cloud.sent.count, start.passkeyKIFF.sent.count], [0, 1, 1, 0, 0])
    }),
    Test("Coach found by the read with planque set up: started, nothing asked", awaiting: { @MainActor in
        let start = Start(cloud: [(200, coachRead)])
        let (outcome, _) = try await start.run(planqueReady: true)
        try expectEqual(outcome, .started(Coach(id: "taf_setup", name: "Setup")))
        try expectEqual([start.sheets, start.confirmed, start.enrolled, start.passkeyKIFF.sent.count], [0, 0, 0, 0])
    }),
    Test("it fails closed: without the security key's session nothing is asked, read, enrolled, minted or sent", awaiting: { @MainActor in
        let start = Start(cloud: [(200, none)])
        let (outcome, ready) = try await start.run(approval: false)
        try expectEqual(outcome, .stopped(try words()("approval.device_can_not_approve_approve")))
        try expectEqual(ready, false)
        try expectEqual([start.sheets, start.confirmed, start.enrolled, start.cloud.sent.count, start.kiff.sent.count], [0, 0, 0, 0, 0])
        try expectEqual(start.key.asked.count, 0)
        try expectEqual(start.deviceSigned, [])
    }),
    Test("only the security key's route with its session may start", awaiting: { @MainActor in
        let start = Start(cloud: [])
        try expectEqual(CoachStart.mayStart(route: .passkey, approval: start.passkeySession()), true)
        try expectEqual(CoachStart.mayStart(route: .passkey, approval: nil), false)
        try expectEqual(CoachStart.mayStart(route: .phoneOrPasskey, approval: start.passkeySession()), false)
        try expectEqual(CoachStart.mayStart(route: .touchID, approval: start.passkeySession()), false)
    }),
    Test("with Coach there, a closed owner's prompt says \"Cancelled. Nothing changed.\" and enrols nothing; one that failed says it wasn't confirmed", awaiting: { @MainActor in
        let known = Coach(id: "taf_setup", name: "Setup")
        let closed = Start(cloud: [])
        closed.confirmCloses = true
        let (outcome, ready) = try await closed.run(coach: known)
        try expectEqual(outcome, .stopped("Cancelled. Nothing changed."))
        try expectEqual(ready, false)
        try expectEqual([closed.confirmed, closed.enrolled, closed.cloud.sent.count, closed.passkeyKIFF.sent.count], [1, 0, 0, 0])
        let failed = Start(cloud: [])
        failed.confirmFails = true
        let (stopped, _) = try await failed.run(coach: known)
        try expectEqual(stopped, .stopped("Not sent: it wasn't confirmed."))
        try expectEqual(failed.enrolled, 0)
        // A session that ended while the prompt was up says nothing.
        let ended = Start(cloud: [])
        ended.confirmCloses = true
        ended.endsAt = 1
        let (quiet, _) = try await ended.run(coach: known)
        try expectEqual(quiet, .stopped(nil))
    }),
    Test("a closed PIN sheet sends nothing and says nothing; nothing is enrolled", awaiting: { @MainActor in
        let start = Start(cloud: [(200, none)])
        start.sheetCloses = true
        let (outcome, ready) = try await start.run()
        try expectEqual(outcome, .stopped(nil))
        try expectEqual(ready, false)
        try expectEqual([start.enrolled, start.passkeyKIFF.sent.count, start.cloud.sent.count], [0, 0, 1])
    }),
    Test("switched off, the key is never asked and nothing is enrolled or sent", awaiting: { @MainActor in
        let start = Start(cloud: [(200, none)])
        start.enabled = false
        let (outcome, _) = try await start.run()
        try expectEqual(outcome, .stopped(nil))
        try expectEqual([start.key.asked.count, start.enrolled, start.passkeyKIFF.sent.count], [0, 0, 0])
    }),
    Test("authenticator data without user verification is refused before anything is sent", awaiting: { @MainActor in
        let start = Start(cloud: [(200, none)], key: StartKey(flags: up))
        let (outcome, _) = try await start.run()
        try expectEqual(outcome, .stopped(nil))
        try expectEqual([start.key.asked.count, start.enrolled, start.passkeyKIFF.sent.count], [1, 0, 0])
    }),
    Test("no device key: the Mac's words, nothing asked", awaiting: { @MainActor in
        let start = Start(cloud: [])
        let (outcome, _) = try await start.run(signing: false)
        try expectEqual(outcome, .stopped(try words()("sign_in.again_to_sign_device", ["device": "Mac"])))
        try expectEqual([start.sheets, start.cloud.sent.count], [0, 0])
    }),
    Test("planque's stop says its words, and nothing is drafted", awaiting: { @MainActor in
        let start = Start(cloud: [(200, none)])
        start.enrolStop = .adminOnly
        let (outcome, ready) = try await start.run()
        try expectEqual(outcome, .stopped(try words()("coach.connect_admin_only")))
        try expectEqual(ready, false)
        try expectEqual(start.passkeyKIFF.sent.count, 0)
    }),
    Test("tafs cloud's first start sends nothing: no sheet, no enrolment", awaiting: { @MainActor in
        let first = #"{"setup":null,"start":{"state":"to_give","scheme":"kiff.request.v1","requests":[{"id":"draft","method":"POST","path":"/v1/me/agent-drafts","body":{},"cards":[{"title":"Setup"}]}]}}"#
        let start = Start(cloud: [(200, first)])
        let (outcome, _) = try await start.run()
        try expectEqual(outcome, .firstStart)
        try expectEqual([start.sheets, start.enrolled, start.passkeyKIFF.sent.count], [0, 0, 0])
    }),
    Test("a draft without its secret, a refused draft, and an unread Setup each say why", awaiting: { @MainActor in
        let w = try words()
        let noSecret = Start(cloud: [(200, none)], passkey: [(201, #"{"id":"drf_1"}"#)])
        let a = try await noSecret.run().outcome
        try expectEqual(a, .stopped(w("kiff.kiff_did_not_answer_expected")))
        let refused = Start(cloud: [(200, none)], passkey: [(403, #"{"error":"passkey_required"}"#)])
        let b = try await refused.run().outcome
        try expectEqual(b, .stopped(w("coach.couldnt_start", ["why": w("error.not_allowed")])))
        try expectEqual(refused.cloud.sent.count, 1)
        let signedOut = Start(cloud: [(200, none)], passkey: [(401, "{}")])
        let c = try await signedOut.run().outcome
        try expectEqual(c, .stopped(w("coach.couldnt_start", ["why": w("error.signed_out")])))
        let unread = Start(cloud: [(503, "{}")])
        let d = try await unread.run().outcome
        if case .stopped(let why?) = d { try expect(why.hasPrefix("Couldn't start."), why) } else { throw Failure(description: "should stop with why") }
        try expectEqual(unread.sheets, 0)
    }),
    Test("a session that ends after the read, the approval, the enrolment or the draft goes no further and says nothing", awaiting: { @MainActor in
        for (at, drafts, claims) in [(1, 0, 0), (2, 0, 0), (3, 0, 0), (4, 1, 0)] {
            let start = Start(cloud: [(200, none), (201, coachRead)], passkey: [(201, draft)])
            start.endsAt = at
            let (outcome, _) = try await start.run()
            try expectEqual(outcome, .stopped(nil))
            try expectEqual(start.passkeyKIFF.sent.count, drafts)
            try expectEqual(start.cloud.sent.count - 1, claims)
        }
    }),
    Test("the first start reads as startable only as the iPad's, case by case") {
        func first(_ json: String) -> CoachStart.FirstStart? { CoachStart.FirstStart.read(Data(json.utf8)) }
        let alone = first(#"{"start":{"state":"to_give","scheme":"kiff.request.v1","requests":[{"id":"draft","method":"POST","path":"/v1/me/agent-drafts","body":{},"cards":[{"lines":["one"]}]}]}}"#)
        try expectEqual(alone?.startable, true)
        let noCards = first(#"{"start":{"state":"to_give","scheme":"kiff.request.v1","requests":[{"id":"draft","method":"POST","path":"/v1/me/agent-drafts","body":{},"cards":[{}]}]}}"#)
        try expectEqual(noCards?.startable, false)
        let pair = first(#"{"start":{"state":"to_give","scheme":"kiff.requests.v1","requests":[{"id":"connect","method":"POST","path":"/v1/connections/batch","gateway":true,"body":{}},{"id":"draft","method":"POST","path":"/v1/me/agent-drafts","body":{},"cards":[{"title":"A"}]}]}}"#)
        try expectEqual(pair?.startable, true)
        try expectEqual(pair?.together, true)
        let given = first(#"{"start":{"state":"given","scheme":"kiff.request.v1","requests":[]}}"#)
        try expectEqual(given?.startable, false)
        try expectEqual(first(#"{"setup":null}"#), nil)
    },
]

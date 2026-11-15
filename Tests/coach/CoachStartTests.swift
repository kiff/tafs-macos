import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t_01", subject: "u1", deviceID: "dev_9")
private let coach = #"{"setup":{"id":"taf_setup","name":"Setup"}}"#
private let none = #"{"setup":null}"#
private let draft = #"{"id":"drf_1","agent_id":"setup","status":"confirmed","version":"v1","claim_secret":"sec_1"}"#

/// What the Touch ID answers: the context the approval key signs under.
private final class Confirmed {}

/// tafs cloud, KIFF's device-key session and its approval-key session, each with its answers;
/// what each signed, what was confirmed and enrolled, as a start sees them.
@MainActor
private final class Start {
    let cloud: CannedTransport
    let kiff: CannedTransport
    let approvalKIFF: CannedTransport
    var deviceSigned: [String] = []
    var approvalSigned: [String] = []
    var confirmed = 0
    var enrolled = 0
    var enrolStop: PlanqueEnrolment.Stop?
    var confirmFails = false
    /// The context the Touch ID answered, which alone the approval key signs under.
    var context = Confirmed()
    /// The context the confirmation hands on; another one is refused by the approval key.
    var handed: Confirmed?
    var endsAt: Int?
    var checks = 0

    init(cloud: [(Int, String)], kiff: [(Int, String)] = [], approval: [(Int, String)] = []) {
        self.cloud = CannedTransport(cloud)
        self.kiff = CannedTransport(kiff)
        approvalKIFF = CannedTransport(approval)
    }

    var account: AccountClient {
        AccountClient(transport: kiff, session: session, sign: { [unowned self] r in deviceSigned.append(r.path); return "t=x,v1=DEVICE" })
    }

    /// The approval key: it signs only under the context the Touch ID just answered.
    func approvalSession(_ present: Bool = true) -> ApprovalSession? {
        guard present else { return nil }
        return ApprovalSession(transport: approvalKIFF, session: session, bodyHash: { "hash(\(String(decoding: $0, as: UTF8.self)))" },
                               sign: { [unowned self] message, confirmed in
                                   guard confirmed === context else { throw Failure(description: "not under the Touch ID") }
                                   approvalSigned.append(String(decoding: message, as: UTF8.self))
                                   return "APPROVAL"
                               })
    }

    func run(coach known: Coach? = nil, planqueReady: Bool = false, approval: Bool = true, signing: Bool = true) async throws -> (outcome: CoachStart.Outcome, planqueReady: Bool) {
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        let device = signing ? account : AccountClient(transport: kiff, session: session)
        return await CoachStart.start(
            coach: known, planqueReady: planqueReady, cloud: CloudClient(transport: cloud, session: session), account: device,
            approval: approvalSession(approval),
            confirm: { [unowned self] in
                confirmed += 1
                if confirmFails { throw Failure(description: "closed") }
                return handed ?? context
            },
            enrol: { [unowned self] _ in enrolled += 1; return enrolStop },
            ended: { [unowned self] in checks += 1; return endsAt.map { checks >= $0 } ?? false },
            words: words)
    }
}

private func words() throws -> Words { try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings")) }

let coachStartTests: [Test] = [
    Test("Start in the iPad's order: one Touch ID, planque, Setup read, Setup's draft signed by the approval key under it, then tafs cloud claims it", awaiting: { @MainActor in
        let start = Start(cloud: [(200, none), (201, coach)], approval: [(201, draft)])
        let (outcome, ready) = try await start.run()
        try expectEqual(outcome, .started(Coach(id: "taf_setup", name: "Setup")))
        try expectEqual(ready, true)
        try expectEqual([start.confirmed, start.enrolled], [1, 1])
        try expectEqual(start.cloud.sent.map { $0.method + " " + $0.path }, ["GET /v1/setup", "POST /v1/setup"])
        // Setup's draft: no tools, signed by the approval key over `kiff.request.v1`, never the device key.
        let sent = start.approvalKIFF.sent
        try expectEqual(sent.map { $0.method + " " + $0.path }, ["POST /v1/me/agent-drafts"])
        let body = #"{"agent_id":"setup","label":"Setup","no_tools":true}"#
        try expectEqual(String(decoding: sent[0].body, as: UTF8.self), body)
        let header = sent[0].headers["KIFF-Device-Signature"] ?? ""
        try expect(header.hasSuffix(",v1=APPROVAL"), header)
        let signedAt = String(header.split(separator: ",")[0].dropFirst(2))
        try expect(signedAt.contains("."), "milliseconds: \(signedAt)")
        try expectEqual(start.approvalSigned, [KIFFMessage.request(tenant: "t_01", method: "POST", path: "/v1/me/agent-drafts",
                                                                   bodyHash: "hash(\(body))", signedAt: signedAt)])
        try expectEqual(start.deviceSigned, [])
        try expectEqual(start.kiff.sent.count, 0)
        // tafs cloud claims the draft's key with the secret KIFF gave once.
        try expectEqual(String(decoding: start.cloud.sent[1].body, as: UTF8.self), #"{"claim_secret":"sec_1","draft_id":"drf_1"}"#)
    }),
    Test("with Coach there and planque set up, Start asks nothing and sends nothing", awaiting: { @MainActor in
        let start = Start(cloud: [])
        let known = Coach(id: "taf_setup", name: "Setup")
        let (outcome, ready) = try await start.run(coach: known, planqueReady: true)
        try expectEqual(outcome, .started(known))
        try expectEqual(ready, true)
        try expectEqual([start.confirmed, start.enrolled, start.cloud.sent.count, start.approvalKIFF.sent.count], [0, 0, 0, 0])
    }),
    Test("with Coach there, only planque: confirmed, enrolled, nothing read or drafted", awaiting: { @MainActor in
        let start = Start(cloud: [])
        let known = Coach(id: "taf_setup", name: "Setup")
        let (outcome, ready) = try await start.run(coach: known)
        try expectEqual(outcome, .started(known))
        try expectEqual(ready, true)
        try expectEqual([start.confirmed, start.enrolled, start.cloud.sent.count, start.approvalKIFF.sent.count], [1, 1, 0, 0])
    }),
    Test("it fails closed: without the approval key nothing is asked, enrolled, minted, read or sent", awaiting: { @MainActor in
        let start = Start(cloud: [(200, none)])
        let (outcome, ready) = try await start.run(approval: false)
        try expectEqual(outcome, .stopped(try words()("approval.device_can_not_approve_approve")))
        try expectEqual(ready, false)
        try expectEqual([start.confirmed, start.enrolled, start.cloud.sent.count, start.kiff.sent.count], [0, 0, 0, 0])
        try expectEqual(start.kiff.sent.filter { $0.path == "/v1/keys" }.count, 0)
        try expectEqual(start.deviceSigned, [])
        // Only Touch ID's approval key may start.
        try expectEqual(CoachStart.mayStart(route: .phoneOrPasskey, approval: start.approvalSession()), false)
        try expectEqual(CoachStart.mayStart(route: .touchID, approval: nil), false)
        try expectEqual(CoachStart.mayStart(route: .touchID, approval: start.approvalSession()), true)
    }),
    Test("the approval key signs only under the Touch ID that confirmed Start: another context sends no draft", awaiting: { @MainActor in
        let start = Start(cloud: [(200, none)], approval: [(201, draft)])
        start.handed = Confirmed()
        let (outcome, _) = try await start.run()
        guard case .stopped(let why?) = outcome, why.hasPrefix("Couldn't start.") else { throw Failure(description: "\(outcome)") }
        try expectEqual(start.approvalKIFF.sent.count, 0)
        try expectEqual(start.approvalSigned, [])
        try expectEqual(start.cloud.sent.count, 1)
    }),
    Test("a closed prompt starts nothing and says nothing; a session without its key says to sign in again", awaiting: { @MainActor in
        let closed = Start(cloud: [(200, none)])
        closed.confirmFails = true
        let (outcome, ready) = try await closed.run()
        try expectEqual(outcome, .stopped(nil))
        try expectEqual(ready, false)
        try expectEqual([closed.enrolled, closed.cloud.sent.count, closed.approvalKIFF.sent.count], [0, 0, 0])
        let keyless = Start(cloud: [])
        let (unsigned, _) = try await keyless.run(signing: false)
        try expectEqual(unsigned, .stopped(try words()("sign_in.again_to_sign_device", ["device": "Mac"])))
        try expectEqual(keyless.confirmed, 0)
    }),
    Test("planque that doesn't enrol stops Start with its words, and nothing more is read or sent", awaiting: { @MainActor in
        let start = Start(cloud: [(200, none)])
        start.enrolStop = .adminOnly
        let (outcome, ready) = try await start.run()
        try expectEqual(outcome, .stopped(try words()("coach.connect_admin_only")))
        try expectEqual(ready, false)
        try expectEqual([start.cloud.sent.count, start.approvalKIFF.sent.count], [0, 0])
        // Enrolment that isn't set up (an answer that didn't keep it, or not reached) stops it too.
        let notSetUp = Start(cloud: [(200, none)])
        notSetUp.enrolStop = .notSetUp(why: .unreadable)
        let (stopped, stillNot) = try await notSetUp.run()
        let w = try words()
        try expectEqual(stopped, .stopped(w("coach.connecting_not_set_up", ["why": w("error.ours")])))
        try expectEqual(stillNot, false)
        try expectEqual([notSetUp.cloud.sent.count, notSetUp.approvalKIFF.sent.count], [0, 0])
    }),
    Test("a session that ends inside the enrolment mints nothing and says nothing", awaiting: { @MainActor in
        let planqueSent = CannedTransport([(409, #"{"code":"needs_key"}"#), (201, "{}")])
        let kiff = CannedTransport([(201, #"{"id":"key_c","plaintext":"kiff_live_connector","roles":["connector"]}"#)])
        let account = AccountClient(transport: kiff, session: session, sign: { _ in "t=x,v1=DEVICE" })
        let planque = PlanqueClient(baseURL: "https://planque.test/")
        planque.tenant = "t_01"
        planque.deviceID = "dev_9"
        planque.transport = planqueSent
        planque.bodyHash = { _ in "h" }
        var signedOut = false
        // The session ends as planque answers the first enrolment.
        planque.signer = { _ in signedOut = true; return "SIG" }
        let start = Start(cloud: [(200, none)], approval: [(201, draft)])
        let (outcome, _) = await CoachStart.start(
            coach: nil, planqueReady: false, cloud: CloudClient(transport: start.cloud, session: session), account: account,
            approval: start.approvalSession(), confirm: { start.context },
            enrol: { ended in await PlanqueEnrolment.enrol(planque: planque, account: account, deviceKey: Data([1]), ended: ended) },
            ended: { signedOut }, words: try words())
        try expectEqual(outcome, .stopped(nil))
        try expectEqual(kiff.sent.filter { $0.path == "/v1/keys" }.count, 0)
        try expectEqual(planqueSent.sent.count, 1)
        try expectEqual([start.cloud.sent.count, start.approvalKIFF.sent.count], [0, 0])
    }),
    Test("tafs cloud's first start, signed once with Coach's tools, isn't on this Mac yet: nothing is sent", awaiting: { @MainActor in
        let first = #"{"setup":null,"start":{"state":"to_give","scheme":"kiff.request.v1","requests":[{"id":"draft","method":"POST","path":"/v1/me/agent-drafts","gateway":false,"body":{"agent_id":"setup"},"cards":[{"title":"Setup's Card","lines":["Reads your apps"]}]}]}}"#
        let start = Start(cloud: [(200, first)])
        let (outcome, _) = try await start.run()
        try expectEqual(outcome, .firstStart)
        try expectEqual(start.approvalKIFF.sent.count, 0)
        // A start with no Card in KIFF's words isn't one to sign: the draft is started as before.
        let unread = #"{"setup":null,"start":{"state":"to_give","scheme":"kiff.request.v1","requests":[{"id":"draft","method":"POST","path":"/v1/me/agent-drafts","body":{},"cards":[]}]}}"#
        let plain = Start(cloud: [(200, unread), (201, coach)], approval: [(201, draft)])
        let got1 = try await plain.run().outcome
        try expectEqual(got1, .started(Coach(id: "taf_setup", name: "Setup")))
    }),
    Test("which first starts can be signed, as the iPad's CoachStart.startable") {
        func read(_ start: String) -> CoachStart.FirstStart? { CoachStart.FirstStart.read(Data(#"{"setup":null,"start":\#(start)}"#.utf8)) }
        let draftRequest = #"{"id":"draft","method":"POST","path":"/v1/me/agent-drafts","body":{},"cards":[{"title":"Card"}]}"#
        let connect = #"{"id":"connect","method":"POST","path":"/v1/connections/batch","gateway":true,"body":{}}"#
        try expectEqual(read(#"{"state":"to_give","scheme":"kiff.request.v1","requests":[\#(draftRequest)]}"#)?.startable, true)
        try expectEqual(read(#"{"state":"to_give","scheme":"kiff.requests.v1","requests":[\#(connect),\#(draftRequest)]}"#)?.startable, true)
        // The pair under the one-request scheme, a state not to give, or a draft at the gateway: none.
        try expectEqual(read(#"{"state":"to_give","scheme":"kiff.request.v1","requests":[\#(connect),\#(draftRequest)]}"#)?.startable, false)
        try expectEqual(read(#"{"state":"given","scheme":"kiff.request.v1","requests":[\#(draftRequest)]}"#)?.startable, false)
        try expectEqual(read(#"{"state":"to_give","scheme":"kiff.request.v1","requests":[{"id":"draft","method":"POST","path":"/v1/me/agent-drafts","gateway":true,"body":{},"cards":[{"title":"C"}]}]}"#)?.startable, false)
        // A request without its body, or a Card without a title or lines, doesn't read.
        try expectEqual(read(#"{"state":"to_give","requests":[{"id":"draft","method":"POST","path":"/v1/me/agent-drafts"}]}"#)?.requests.count, 0)
        try expectEqual(read(#"{"state":"to_give","requests":[{"id":"draft","method":"POST","path":"/p","body":{},"cards":[{"x":1},{"lines":["a"]}]}]}"#)?.requests.first?.cards, 1)
        try expectEqual(CoachStart.FirstStart.read(Data(#"{"setup":null}"#.utf8)), nil)
    },
    Test("a draft without its secret, or a refused claim, says Coach couldn't start, never a code; KIFF's approval_key_required in the iPad's words", awaiting: { @MainActor in
        let w = try words()
        let noSecret = Start(cloud: [(200, none)], approval: [(201, #"{"id":"drf_1"}"#)])
        let got2 = try await noSecret.run().outcome
        try expectEqual(got2, .stopped(w("kiff.kiff_did_not_answer_expected")))
        try expectEqual(noSecret.cloud.sent.count, 1)
        let refused = Start(cloud: [(200, none), (409, #"{"error":"setup_exists","words":"Coach is already set up."}"#)], approval: [(201, draft)])
        let got3 = try await refused.run().outcome
        try expectEqual(got3, .stopped(w("coach.couldnt_start", ["why": "Coach is already set up."])))
        // KIFF doesn't hold this approval key, in `error` or in `reason`: the iPad's approvalKeyLost.
        let keyGone = w("coach.couldnt_start", ["why": w("approval.key_gone_biometry", ["biometry": "Touch ID"])])
        let inError = Start(cloud: [(200, none)], approval: [(403, #"{"error":"approval_key_required"}"#)])
        let got4 = try await inError.run().outcome
        try expectEqual(got4, .stopped(keyGone))
        let inReason = Start(cloud: [(200, none)], approval: [(403, #"{"error":"forbidden","reason":"approval_key_required"}"#)])
        let got5 = try await inReason.run().outcome
        try expectEqual(got5, .stopped(keyGone))
        // Any other refusal is KIFF's plain line for its status.
        let other = Start(cloud: [(200, none)], approval: [(403, #"{"error":"role_forbidden"}"#)])
        let got6 = try await other.run().outcome
        try expectEqual(got6, .stopped(w("coach.couldnt_start", ["why": w("error.not_allowed")])))
    }),
    Test("a session that ends after the prompt, the read or the draft drops what comes back, and says nothing", awaiting: { @MainActor in
        // ended is read after the prompt (1), the enrolment (2), the read (3), the draft (4) and the claim (5).
        let afterPrompt = Start(cloud: [(200, none), (201, coach)], approval: [(201, draft)])
        afterPrompt.endsAt = 1
        let gotPrompt = try await afterPrompt.run().outcome
        try expectEqual(gotPrompt, .stopped(nil))
        try expectEqual([afterPrompt.enrolled, afterPrompt.cloud.sent.count], [0, 0])
        let afterRead = Start(cloud: [(200, none), (201, coach)], approval: [(201, draft)])
        afterRead.endsAt = 3
        let gotRead = try await afterRead.run().outcome
        try expectEqual(gotRead, .stopped(nil))
        try expectEqual([afterRead.cloud.sent.count, afterRead.approvalKIFF.sent.count], [1, 0])
        let afterDraft = Start(cloud: [(200, none), (201, coach)], approval: [(201, draft)])
        afterDraft.endsAt = 4
        let gotDraft = try await afterDraft.run().outcome
        try expectEqual(gotDraft, .stopped(nil))
        // The draft went; the claim didn't.
        try expectEqual([afterDraft.cloud.sent.count, afterDraft.approvalKIFF.sent.count], [1, 1])
    }),
]

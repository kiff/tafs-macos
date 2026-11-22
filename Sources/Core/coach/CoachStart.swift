import Foundation

/// Starting Coach for the account, as the iPad's `startSetup` (`AppModel.swift:7556-7635`) and
/// Windows' `CoachStart.StartAsync` on its passkey route (tafs-windows#65): planque first, then,
/// for an account with no Coach, Setup's draft with no tools, whose key tafs cloud claims.
///
/// On macOS 12 the draft is approved by **this Mac's security key** (`PasskeySession`), as Windows
/// approves it with its passkey: the PIN sheet, then the key's touch, over exactly the draft sent.
/// That one approval is the confirmation, made before anything is enrolled or sent, as Windows'
/// Windows Hello and the iPad's one Face ID. **It fails closed:** without the passkey session
/// nothing is asked, enrolled, minted or sent, and the device key never approves the draft.
enum CoachStart {
    /// What a start came to.
    enum Outcome: Equatable {
        /// Coach is there: read, or started now.
        case started(Coach)
        /// tafs cloud built Coach's first start, signed once with its tools (`GET /v1/setup`'s
        /// `start`, as the iPad's `startCoachTogether`): not on this Mac yet. Nothing is sent.
        case firstStart
        /// It didn't start; with the person's line for why, or nil to say nothing (a closed
        /// sheet or prompt, or a session that ended).
        case stopped(String?)
    }

    /// Setup's KIFF agent, as the iPad's `setupAgent`.
    static let setupAgent = "setup"
    /// Where a draft is submitted (KIFF's API).
    static let draftPath = "/v1/me/agent-drafts"

    /// Whether this Mac may start Coach, as Windows' `MayStart`: only on the security key's route,
    /// with the passkey session that approves the draft. Any other Mac (its approvals go to the
    /// phone) never starts it: Coach is started on the phone, and this Mac follows it.
    static func mayStart(route: ApprovalRoute, approval: PasskeySession?) -> Bool {
        route == .passkey && approval != nil
    }

    /// Setup's draft, as the iPad's `submitNoToolsDraft(agentID: "setup", label: "Setup")`: the
    /// exact bytes approved and sent.
    static func draftBody() -> Data {
        Data(#"{"agent_id":"setup","label":"Setup","no_tools":true}"#.utf8)
    }

    /// The Start, in Windows' order on its passkey route (`CoachStart.cs`, `StartAsync`):
    /// - `account` signs planque's setup calls with the device key, which asks no one once the
    ///   step is approved (`signConfirmed`); with no device key, nothing is done.
    /// - `approval` sends Setup's draft with its security key's approval; nil stops before
    ///   anything is asked.
    /// - `sign` approves the draft's exact bytes with the security key: the PIN sheet, then the
    ///   key's touch. It throws when the sheet is closed, and nothing is sent.
    /// - `confirm` is the owner's confirmation for planque alone, when Coach is already there
    ///   (Windows' `PlanqueEnrolment.GateAsync`). It throws `OwnerPrompt.Closed` when the person
    ///   closed the prompt, which stops with "Cancelled. Nothing changed."
    /// - `enrol` is planque's enrolment (`PlanqueEnrolment.enrol`), given the account check.
    /// - `ended` says the session ended meanwhile, as the iPad's `gen != accountGeneration`,
    ///   checked after every step.
    @MainActor static func start(coach: Coach?, planqueReady: Bool, cloud: CloudClient, account: AccountClient, approval: PasskeySession?,
                                 sign: (Data) async throws -> PasskeySession.Signed, confirm: () async throws -> Void,
                                 enrol: (@escaping () -> Bool) async -> PlanqueEnrolment.Stop?,
                                 ended: @escaping () -> Bool, words: Words) async -> (outcome: Outcome, planqueReady: Bool) {
        // guard mode == .kiff, sessionHasKey, let tenant
        guard account.sign != nil else { return (.stopped(words("sign_in.again_to_sign_device", ["device": "Mac"])), planqueReady) }
        // if planqueReady, setupTaf != nil { return true }
        if planqueReady, let coach { return (.started(coach), true) }
        // Fails closed (Windows' `MayStart` first): without the passkey session nothing is
        // asked, read, enrolled, minted or sent.
        guard let approval else { return (.stopped(words("approval.device_can_not_approve_approve")), planqueReady) }
        var known = coach
        if known == nil {
            // Setup is read before the approval, so nothing is asked for what won't be sent.
            do {
                let read = try await cloud.setupRead()
                guard !ended() else { return (.stopped(nil), planqueReady) }
                if let existing = read.setup {
                    known = existing
                    if planqueReady { return (.started(existing), true) }
                } else if let start = read.start, start.startable {
                    // A start tafs cloud built, signed once with Coach's tools: not on this Mac yet.
                    return (.firstStart, planqueReady)
                }
            } catch {
                guard !ended() else { return (.stopped(nil), planqueReady) }
                return (.stopped(words("coach.couldnt_start", ["why": why(error, words: words)])), planqueReady)
            }
        }
        // The one approval, before anything is enrolled or sent.
        var signed: PasskeySession.Signed?
        if known == nil {
            do { signed = try await sign(draftBody()) } catch { return (.stopped(nil), planqueReady) }
        } else {
            // Nothing is pending after it, so a closed prompt says "Cancelled. Nothing changed."
            // (`OwnerPrompt`); a session that ended meanwhile says nothing.
            do { try await confirm() } catch {
                guard !ended() else { return (.stopped(nil), planqueReady) }
                return (.stopped(OwnerPrompt.stopped(error, words: words)), planqueReady)
            }
        }
        guard !ended() else { return (.stopped(nil), planqueReady) }
        var ready = planqueReady
        if !ready {
            if let stop = await enrol(ended) { return (.stopped(stop.words(words)), false) }
            ready = true
        }
        guard !ended() else { return (.stopped(nil), ready) }
        if let known { return (.started(known), ready) }
        guard let signed else { return (.stopped(nil), ready) }
        do {
            let draft = try await approval.submitNoToolsDraft(signed)
            guard !ended() else { return (.stopped(nil), ready) }
            guard let secret = draft.claimSecret else { return (.stopped(words("kiff.kiff_did_not_answer_expected")), ready) }
            let started = try await cloud.startSetup(draftID: draft.id, claimSecret: secret)
            // One check more than the iPad's (`:7615`): a session that ended now says nothing.
            guard !ended() else { return (.stopped(nil), ready) }
            return (.started(started), ready)
        } catch {
            guard !ended() else { return (.stopped(nil), ready) }
            return (.stopped(words("coach.couldnt_start", ["why": why(error, words: words)])), ready)
        }
    }

    /// Why a start failed, as the iPad's `error.localizedDescription`: tafs cloud's own words for
    /// a refusal; KIFF's plain line (never its code); the security key's own line; else the
    /// system's words.
    static func why(_ error: Error, words: Words) -> String {
        switch error {
        case let refusal as CloudRefusal: return refusal.why(words)
        case KIFFError.refused(401, _): return words("error.signed_out")
        case KIFFError.refused(let status, _): return words(StepRefusal.plainKey(status: status))
        case KIFFError.unreadable: return words("error.ours")
        case is SecurityKeyFailure, is PasskeyRefusal: return SecurityKeyWords.line(error, words: words)
        case is ApproveOnPhone: return words("approval.device_can_not_approve_approve")
        default: return error.localizedDescription
        }
    }

    /// tafs cloud's first start (`GET /v1/setup`'s `start`), as much as tells whether it can be
    /// signed now, as the iPad's `TafsCloud.CoachStart` (`TafsCloud.swift:2247-2330`) and
    /// Windows' `FirstStart.Read`. Read leniently: a field that doesn't read is the iPad's
    /// default, and a request that doesn't read is left out.
    struct FirstStart: Equatable {
        struct Request: Equatable {
            let id: String
            let method: String
            let path: String
            let gateway: Bool
            /// KIFF's words for the Cards the draft would issue: how many read.
            let cards: Int
        }
        var state = "unknown"
        var scheme = ""
        var requests: [Request] = []

        var connect: Request? { requests.first { $0.id == "connect" } }
        var draft: Request? { requests.first { $0.id == "draft" } }
        /// The pair, signed once: both requests and the scheme that names two.
        var together: Bool { scheme == RequestsTogether.scheme && connect != nil && draft != nil }
        /// Something a device can sign and send now: the pair, or the draft alone.
        var startable: Bool {
            guard state == "to_give", let draft, draft.method == "POST", draft.path == CoachStart.draftPath, !draft.gateway else { return false }
            // Never Cards the person hasn't read in KIFF's own words.
            guard draft.cards > 0 else { return false }
            if let connect { return together && connect.method == "POST" && connect.path == "/v1/connections/batch" && connect.gateway }
            return scheme == "kiff.request.v1"
        }

        /// From `GET /v1/setup`'s answer; nil when it sends no `start`.
        static func read(_ answer: Data) -> FirstStart? {
            guard let top = (try? JSONSerialization.jsonObject(with: answer)) as? [String: Any],
                  let fields = top["start"] as? [String: Any] else { return nil }
            var s = FirstStart()
            s.state = fields["state"] as? String ?? "unknown"
            s.scheme = fields["scheme"] as? String ?? ""
            s.requests = (fields["requests"] as? [Any] ?? []).compactMap { item in
                guard let f = item as? [String: Any], let id = f["id"] as? String, let method = f["method"] as? String,
                      let path = f["path"] as? String, f["body"] != nil else { return nil }
                // A Card reads with a title (`title`, `card_title` or `label`) or lines.
                let cards = (f["cards"] as? [Any] ?? []).filter { item in
                    guard let c = item as? [String: Any] else { return false }
                    let title = (c["title"] as? String) ?? (c["card_title"] as? String) ?? (c["label"] as? String)
                    let lines = (c["lines"] as? [Any])?.compactMap { $0 as? String } ?? []
                    return title != nil || !lines.isEmpty
                }.count
                return Request(id: id, method: method, path: path, gateway: f["gateway"] as? Bool ?? false, cards: cards)
            }
            return s
        }
    }

    /// Setup as `GET /v1/setup` answers it: Coach, or for an account with none, the first start.
    struct SetupRead: Equatable {
        let setup: Coach?
        let start: FirstStart?
    }
}

extension CloudClient {
    /// The account's Coach, or the first start tafs cloud built for an account with none, as the
    /// iPad's `setupRead`. A plain read, as `coach()`: it sends no time zone.
    func setupRead() async throws -> CoachStart.SetupRead {
        struct Answer: Decodable { let setup: Coach? }
        let body = try await read("/v1/setup")
        let answer: Answer = try decoded(body)
        return CoachStart.SetupRead(setup: answer.setup, start: answer.setup == nil ? CoachStart.FirstStart.read(body) : nil)
    }

    /// Starts Coach from Setup's draft: tafs cloud claims its key with the secret KIFF gave once,
    /// as the iPad's `TafsCloud.startSetup` (`TafsCloud.swift:2470-2478`). Unsigned, with the
    /// session's token, as the iPad's.
    func startSetup(draftID: String, claimSecret: String) async throws -> Coach {
        struct Body: Encodable {
            let draftID: String, claimSecret: String
            enum CodingKeys: String, CodingKey { case draftID = "draft_id", claimSecret = "claim_secret" }
        }
        struct Answer: Decodable { let setup: Coach }
        let body = try await post("/v1/setup", body: Body(draftID: draftID, claimSecret: claimSecret))
        guard let answer = try? AccountClient.decoder.decode(Answer.self, from: body) else { throw KIFFError.unreadable }
        return answer.setup
    }
}

extension AccountClient {
    /// A draft as KIFF answers its submit: its id, and the secret tafs cloud claims its key with,
    /// shown once, as the iPad's `AgentDraft`.
    struct AgentDraft: Decodable, Equatable {
        let id: String
        let claimSecret: String?
        enum CodingKeys: String, CodingKey { case id, claimSecret = "claim_secret" }
    }
}

/// The session's security-key side: what grants authority, approved by this Mac's security key
/// (`PasskeyApprover`) and sent as `KIFF-Passkey-Assertion`, as Windows' `SignDraftAsync`. Its own
/// type, so the device-key session (`AccountClient`) can never be passed in its place, and a draft
/// is sent only as `Signed`, which only `signDraft` makes.
struct PasskeySession {
    let transport: Transport
    let session: Session
    var language = "en"
    let approver: PasskeyApprover

    /// A draft's exact bytes and the security key's approval of them. Only `signDraft` makes one.
    struct Signed: Equatable {
        let body: Data
        let assertion: String
        fileprivate init(body: Data, assertion: String) {
            self.body = body
            self.assertion = assertion
        }
    }

    /// Approves Setup's draft with the security key, over exactly `body`, at a signing time never
    /// used twice; the PIN is handed to the key once, then cleared. Off, the key isn't asked.
    func signDraft(_ body: Data, pin: SecurityKeyPIN?) async throws -> Signed {
        let assertion = try await approver.approve(tenant: session.tenant, method: "POST", path: CoachStart.draftPath, body: body, pin: pin)
        return Signed(body: body, assertion: assertion)
    }

    /// Setup's draft, with no tools (`POST /v1/me/agent-drafts`), as the iPad's
    /// `submitNoToolsDraft` (`KIFFClient.swift:1261-1269`): the approved bytes, with their
    /// approval.
    func submitNoToolsDraft(_ signed: Signed) async throws -> AccountClient.AgentDraft {
        let request = HTTPRequest(method: "POST", path: CoachStart.draftPath, headers: [
            "Authorization": "Bearer \(session.accessToken)", "Accept": "application/json", "Content-Type": "application/json",
            "Accept-Language": language, "User-Agent": "tafs-macos", Passkeys.headerName: signed.assertion,
        ], body: signed.body)
        let (status, answer) = try await transport.send(request)
        guard (200..<300).contains(status) else { throw KIFFError(status: status, body: answer) }
        guard let draft = try? AccountClient.decoder.decode(AccountClient.AgentDraft.self, from: answer) else { throw KIFFError.unreadable }
        return draft
    }
}

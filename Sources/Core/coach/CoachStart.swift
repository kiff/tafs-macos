import Foundation

/// Starting Coach for the account, as the iPad's `startSetup` (`AppModel.swift:7556-7635`):
/// planque first, then, for an account with no Coach, Setup's draft with no tools, whose key
/// tafs cloud claims. One confirmation covers it all; nothing is sent before it.
///
/// Setup's draft grants authority (KIFF's `grantsAuthority`: from a device it is confirmed at
/// once, so it issues Setup's Card), so it is signed by the approval key. A Mac with none never
/// signs it with the device key in its place: it doesn't start, and Coach is started on a device
/// that can approve (`mayStart`).
enum CoachStart {
    /// What a start came to.
    enum Outcome: Equatable {
        /// Coach is there: read, or started now.
        case started(Coach)
        /// tafs cloud built Coach's first start, signed once with its tools (`GET /v1/setup`'s
        /// `start`, as the iPad's `startCoachTogether`): not on this Mac yet. Nothing is sent.
        case firstStart
        /// It didn't start; with the person's line for why, or nil to say nothing (a closed
        /// prompt, or a session that ended).
        case stopped(String?)
    }

    /// Whether this Mac may start Coach, as the iPad's `startSetup` guard and its `ApprovalGate`:
    /// only with an approval key that signs Setup's draft. A Mac without one (its approvals go to
    /// the phone or a passkey) never starts it: Coach is started on the phone, and this Mac
    /// follows it.
    static func mayStart(route: ApprovalRoute, approval: AccountClient?) -> Bool {
        route == .touchID && approval?.sign != nil
    }

    /// The Start, in the iPad's order. `account` signs planque's setup calls with the device key,
    /// which asks no one once the step is confirmed (`signConfirmed`); `approval` is the same
    /// session whose signer is the approval key (`approvalSigner`), for Setup's draft.
    /// `confirm` is the one confirmation; `enrol` is planque's enrolment (`PlanqueEnrolment`),
    /// with planque's signers set by the caller. `ended` says the session ended meanwhile, as
    /// the iPad's `gen == accountGeneration`.
    @MainActor static func start(coach: Coach?, planqueReady: Bool, cloud: CloudClient, account: AccountClient, approval: AccountClient?,
                      confirm: () async throws -> Void, enrol: () async -> PlanqueEnrolment.Stop?,
                      ended: () -> Bool, words: Words) async -> (outcome: Outcome, planqueReady: Bool) {
        // guard mode == .kiff, sessionHasKey, let tenant
        guard account.sign != nil else { return (.stopped(words("sign_in.again_to_sign")), planqueReady) }
        // if planqueReady, setupTaf != nil { return true }
        if planqueReady, let coach { return (.started(coach), true) }
        // The one confirmation, before anything is sent: the iPad's Face ID over `tafs.setup.v1|{tenant}`.
        do { try await confirm() } catch { return (.stopped(nil), planqueReady) }
        guard !ended() else { return (.stopped(nil), planqueReady) }
        var ready = planqueReady
        // if !planqueReady { guard await enrolPlanque(...) else { setupError = lastError } }
        if !ready {
            if let stop = await enrol() { return (.stopped(stop.words(words)), false) }
            ready = true
        }
        guard !ended() else { return (.stopped(nil), ready) }
        if let coach { return (.started(coach), ready) }
        do {
            let read = try await cloud.setupRead()
            guard !ended() else { return (.stopped(nil), ready) }
            if let existing = read.setup { return (.started(existing), ready) }
            // A start tafs cloud built, signed once with Coach's tools: the next part.
            if let start = read.start, start.startable { return (.firstStart, ready) }
            // Setup's draft is the approval key's to sign: without it, nothing is sent.
            guard let approval, approval.sign != nil else {
                return (.stopped(words("approval.device_can_not_approve_approve")), ready)
            }
            let draft = try await approval.submitNoToolsDraft(agentID: setupAgent, label: "Setup")
            guard !ended() else { return (.stopped(nil), ready) }
            guard let secret = draft.claimSecret else { return (.stopped(words("kiff.kiff_did_not_answer_expected")), ready) }
            let started = try await cloud.startSetup(draftID: draft.id, claimSecret: secret)
            guard !ended() else { return (.stopped(nil), ready) }
            return (.started(started), ready)
        } catch {
            guard !ended() else { return (.stopped(nil), ready) }
            return (.stopped(words("coach.couldnt_start", ["why": why(error, words: words)])), ready)
        }
    }

    /// Setup's KIFF agent, as the iPad's `setupAgent`.
    static let setupAgent = "setup"

    /// Why a start failed, as the iPad's `error.localizedDescription`: tafs cloud's own words for
    /// a refusal, KIFF's plain line (never its code), else the system's words.
    static func why(_ error: Error, words: Words) -> String {
        switch error {
        case let refusal as CloudRefusal: return refusal.why(words)
        case KIFFError.refused(401, _): return words("error.signed_out")
        case KIFFError.refused(let status, _): return words(StepRefusal.plainKey(status: status))
        case KIFFError.unreadable: return words("error.ours")
        default: return error.localizedDescription
        }
    }

    /// tafs cloud's first start (`GET /v1/setup`'s `start`), as much as tells whether it can be
    /// signed now, as the iPad's `TafsCloud.CoachStart` (`TafsCloud.swift:2247-2330`). Read
    /// leniently: a field that doesn't read is the iPad's default, and a request that doesn't
    /// read is left out.
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
        var together: Bool { scheme == "kiff.requests.v1" && connect != nil && draft != nil }
        /// Something a device can sign and send now: the pair, or the draft alone.
        var startable: Bool {
            guard state == "to_give", let draft, draft.method == "POST", draft.path == "/v1/me/agent-drafts", !draft.gateway else { return false }
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
    /// as the iPad's `TafsCloud.startSetup` (`TafsCloud.swift:2470-2478`).
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

    /// Setup's draft, with no tools (`POST /v1/me/agent-drafts`), as the iPad's
    /// `submitNoToolsDraft` (`KIFFClient.swift:1261-1269`): a signed call that grants authority,
    /// so this client's signer is the approval key's.
    func submitNoToolsDraft(agentID: String, label: String) async throws -> AgentDraft {
        struct Body: Encodable {
            let agentID: String
            let label: String
            let noTools = true
            enum CodingKeys: String, CodingKey { case label, agentID = "agent_id", noTools = "no_tools" }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try read(try await send("POST", "/v1/me/agent-drafts", body: try encoder.encode(Body(agentID: agentID, label: label)), signed: true))
    }
}

import Foundation

/// Trying a version before it's live (kiff/tafs#173, #247), as the iPad's `TrialViews` and `AppModel.startTrying`,
/// `installTrial`, `goBackFromTrial`: the owner chats with version n under a Card of its own, while the live version
/// keeps its schedule, Card and budget. One per taf. On this Mac, what grants authority is the security key's
/// (`KeyAct.confirmTrial`, `confirmDraft`); going back only takes authority away, so it's the device key's signed call.
enum Trials {
    /// The taf's open trial, as tafs cloud keeps it.
    struct Open: Decodable, Equatable {
        let id: String
        let n: Int
        /// The KIFF draft trying as its Card.
        let draft: String
        /// Its chat, opened with the trial.
        let session: String?
        let started: Date
        /// When the owner last wrote in it: unused for 7 days, it ends.
        let used: Date
        /// Its guidance, in tafs cloud's words: a badge ("Trial"), a title, what the version changes, the task to try it
        /// with, and when it ends unused. Absent from an older tafs cloud.
        var label: String?
        var title: String?
        var changed: String?
        var tryWith: String?
        var ends: Date?

        enum CodingKeys: String, CodingKey { case id, n, draft, session, started, used, label, title, changed, ends, tryWith = "try" }
    }

    /// What a version keeps of a trial once it ended.
    struct Summary: Decodable, Equatable {
        let started: Date
        let ended: Date
        /// installed, back, idle or replaced.
        let why: String
        let calls: Int
        let held: Int
        let refused: Int
    }

    /// How starting a trial went.
    enum Started: Equatable {
        case started(Open)
        /// What KIFF holds changed since it was shown: read it again before starting.
        case changed
        /// KIFF confirmed it, but not as a trial (`confirmed`, or another status): nothing runs under it as a trial.
        case notATrial(String)
        /// The security key's sheet closed: nothing changed, nothing said.
        case closed
        /// Didn't start, with why.
        case failed(String)
    }

    /// Starts trying version `n`, as the iPad's `startTrying`: tafs cloud makes the draft (`trialDraft`), this Mac reads
    /// KIFF's draft itself, and only if it's still the version the person was shown does the security key confirm it as a
    /// trial (`KeyAct.confirmTrial`). Only a KIFF that answers `trying` started one; then tafs cloud opens the trial.
    static func start(n: Int, shownDraft: String, words: Words,
                      makeDraft: () async throws -> String,
                      readDraft: (String) async throws -> AccountClient.Draft,
                      confirm: (KeyAct) async throws -> Data,
                      open: (String) async throws -> Open) async -> Started {
        let draft: AccountClient.Draft
        do {
            draft = try await readDraft(try await makeDraft())
        } catch {
            return .failed(words("version.trial.cant_try", ["n": words.number(n), "why": CoachStart.why(error, words: words)]))
        }
        guard draft.version == shownDraft else { return .changed }
        do {
            let answer = try await confirm(.confirmTrial(id: draft.id, version: draft.version))
            struct Status: Decodable { let status: String }
            let status = (try? JSONDecoder().decode(Status.self, from: answer))?.status ?? ""
            guard status == "trying" else { return .notATrial(status) }
            return .started(try await open(draft.id))
        } catch is CancellationError {
            return .closed
        } catch is ApproveOnPhone {
            return .failed(words("approval.device_can_not_approve_approve"))
        } catch {
            return .failed(words("version.trial.not_started", ["n": words.number(n), "why": CoachStart.why(error, words: words)]))
        }
    }

    /// What `notATrial` says, as the iPad's `NotATrial`.
    static func notATrialLine(_ status: String, words: Words) -> String {
        status == "confirmed" ? words("version.not_a_trial.confirmed") : words("version.not_a_trial.other", ["status": status])
    }
}

extension KeyAct {
    /// The exact bytes of a draft's confirm, as KIFF reads them: sorted keys, so what the key approves is what's sent.
    static func confirmBody(version: String, asTrial: Bool) -> Data {
        let fields = asTrial ? ["as": "trial", "version": version] : ["version": version]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(fields)) ?? Data()
    }
}

extension CloudClient {
    /// The KIFF draft to confirm as version n's trial Card.
    func trialDraft(of taf: String, version n: Int) async throws -> String {
        struct Answer: Decodable { let draft: String }
        let answer: Answer = try decoded(try await post("/v1/tafs/\(Self.escaped(taf))/versions/\(n)/try", [:]))
        return answer.draft
    }

    /// Opens the trial of version n, once KIFF has `draft` trying.
    func openTrial(of taf: String, version n: Int, draft: String) async throws -> Trials.Open {
        struct Body: Encodable { let n: Int; let draft: String }
        struct Answer: Decodable { let trial: Trials.Open }
        let answer: Answer = try decoded(try await send("PUT", "/v1/tafs/\(Self.escaped(taf))/trial", body: Body(n: n, draft: draft)))
        return answer.trial
    }

    /// The taf's open trial; nil when it has none.
    func openTrial(of taf: String) async throws -> Trials.Open? {
        struct Answer: Decodable { let trial: Trials.Open? }
        let answer: Answer = try await get("/v1/tafs/\(Self.escaped(taf))/trial")
        return answer.trial
    }

    /// The trial's chat, read as a taf's thread is.
    func trialThread(of taf: String) async throws -> Thread.Page {
        try await get("/v1/tafs/\(Self.escaped(taf))/trial/conversation")
    }

    /// One message to the trial: a turn of the version being tried, in its own chat. Text only.
    func trialMessage(to taf: String, text: String) async throws {
        _ = try await post("/v1/tafs/\(Self.escaped(taf))/trial/messages", ["text": text])
    }

    /// Install: once KIFF confirmed the trial's draft, that version goes live and the trial ends.
    func installTrial(of taf: String) async throws -> Trials.Summary {
        struct Answer: Decodable { let ended: Trials.Summary }
        let answer: Answer = try decoded(try await post("/v1/tafs/\(Self.escaped(taf))/trial/install", [:]))
        return answer.ended
    }

    /// Go back: the trial's chat is deleted, and the live version stays as it was.
    func endTrial(of taf: String) async throws -> Trials.Summary {
        struct Answer: Decodable { let ended: Trials.Summary }
        let answer: Answer = try decoded(try await delete("/v1/tafs/\(Self.escaped(taf))/trial"))
        return answer.ended
    }
}

extension AccountClient {
    /// KIFF ends the draft's trial, so its Cards stop at once, as the iPad's `endTrial(draft:)`: a signed setup call by the
    /// device key, with no prompt, as it only takes authority away. A trial already ended (404 or 409) counts as ended.
    func endTrial(draft id: String) async throws {
        do {
            _ = try await send("DELETE", "/v1/me/agent-drafts/\(CloudClient.escaped(id))/trial", signed: true)
        } catch KIFFError.refused(let status, _) where status == 404 || status == 409 {}
    }
}

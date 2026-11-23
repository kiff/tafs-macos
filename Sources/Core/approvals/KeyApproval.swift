import Foundation

/// One act approved by this Mac's security key alone (docs/approvals.md, "Approving with the security key";
/// kiff/cloud#96): the request the app writes in full, its `kiff.request.v1` message signed by
/// a fresh assertion of the key (UP, and UV from its PIN), and sent with `KIFF-Passkey-Assertion` only. One request
/// per assertion: never a window, never two requests under one (`RequestsTogether` is never used here), never the
/// device key's signature, which grants nothing on a software-key Mac.
extension PasskeySession {
    /// Signs and sends `method path` with exactly `body`, approved by the key through `pin`. A refusal is KIFF's own
    /// (`KIFFError`), so the act's line says it; the key's failures are `SecurityKeyFailure` and `PasskeyRefusal`.
    func approved(method: String, path: String, body: Data = Data(), pin: SecurityKeyPIN?) async throws -> Data {
        let assertion = try await approver.approve(tenant: session.tenant, method: method, path: path, body: body, pin: pin)
        var headers = ["Authorization": "Bearer \(session.accessToken)", "Accept": "application/json",
                       "Accept-Language": language, "User-Agent": "tafs-macos", Passkeys.headerName: assertion]
        if !body.isEmpty { headers["Content-Type"] = "application/json" }
        let (status, answer) = try await transport.send(HTTPRequest(method: method, path: path, headers: headers, body: body))
        guard (200..<300).contains(status) else { throw KIFFError(status: status, body: answer) }
        return answer
    }
}

/// The acts this Mac approves with its security key, each with the request the iPad's `KIFFClient` writes for it.
enum KeyAct: Equatable {
    /// Signing another device out (the iPad's `prepareRemoveDevice`): `DELETE /v1/me/devices/{id}`, empty body.
    case signOutDevice(id: String)
    /// The account's time zone (the iPad's `setTimeZone`): `PUT /v1/me/time-zone` with `{"time_zone": zone}`.
    case timeZone(String)
    /// Resuming a halted KIFF agent, or with none the whole account (the iPad's `KIFFClient.resume`):
    /// `POST /v1/agents/{agent}/resume` or `POST /v1/resume`, with `{}`.
    case resume(agent: String?)
    /// Removing a taf for good (the iPad's `removeTaf`): tafs cloud's `DELETE /v1/tafs/{id}`, empty body, signed before
    /// its Cards are revoked and sent after (`PasskeySession.assertion`).
    case removeTaf(String)
    /// A version's trial Card (the iPad's `confirmDraftAsTrial`): KIFF's `POST` to the draft's confirm step (the one
    /// such path a source may name, pinned in `PlanqueRoutesTests`) with
    /// `{"as":"trial","version":…}`; and installing it (`confirmDraft`), the same without `as`. Each grants authority, so
    /// each is the security key's, once, for that draft at the version the person read.
    case confirmTrial(id: String, version: String)
    case confirmDraft(id: String, version: String)
    /// Discarding a taf being set up (the iPad's `discardSettingUp`): tafs cloud's
    /// `POST /v1/home/setting-up/{agent}/discard`, empty body, signed before its Cards are revoked and sent after.
    case discardSettingUp(String)
    /// An API door's acts (the iPad's `DoorsModel.reopen`, `revoke`, `removeAPI`), each tafs cloud's own request, signed
    /// as a removal is: opening a paused door again (`PATCH …/doors/{door}` with `{"open":true}`), revoking one of its keys
    /// (`DELETE …/keys/{key}`), and removing the door (`DELETE …/doors/{door}`). Pausing is never signed. A new key stays
    /// the phone's: this Mac can't keep a key shown once from screen recording or the clipboard.
    case reopenAPIDoor(taf: String, door: String)
    case revokeAPIDoorKey(taf: String, door: String, key: String)
    case removeAPIDoor(taf: String, door: String)

    var method: String {
        switch self {
        case .signOutDevice: return "DELETE"
        case .timeZone: return "PUT"
        case .resume: return "POST"
        case .removeTaf: return "DELETE"
        case .confirmTrial, .confirmDraft: return "POST"
        case .discardSettingUp: return "POST"
        case .reopenAPIDoor: return "PATCH"
        case .revokeAPIDoorKey, .removeAPIDoor: return "DELETE"
        }
    }

    var path: String {
        switch self {
        case .signOutDevice(let id): return "/v1/me/devices/\(CloudClient.escaped(id))"
        case .timeZone: return "/v1/me/time-zone"
        case .resume(let agent): return agent.map { "/v1/agents/\(CloudClient.escaped($0))/resume" } ?? "/v1/resume"
        case .removeTaf(let id): return "/v1/tafs/\(CloudClient.escaped(id))"
        case .confirmTrial(let id, _), .confirmDraft(let id, _): return "/v1/me/agent-drafts/\(CloudClient.escaped(id))/confirm"
        case .discardSettingUp(let agent): return "/v1/home/setting-up/\(CloudClient.escaped(agent))/discard"
        case .reopenAPIDoor(let taf, let door), .removeAPIDoor(let taf, let door):
            return "/v1/tafs/\(CloudClient.escaped(taf))/doors/\(CloudClient.escaped(door))"
        case .revokeAPIDoorKey(let taf, let door, let key):
            return "/v1/tafs/\(CloudClient.escaped(taf))/doors/\(CloudClient.escaped(door))/keys/\(CloudClient.escaped(key))"
        }
    }

    var body: Data {
        switch self {
        case .signOutDevice: return Data()
        case .timeZone(let zone):
            // The same bytes as the device key's signed call (`AccountClient.setTimeZone`): sorted keys.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return (try? encoder.encode(["time_zone": zone])) ?? Data()
        case .resume: return Data("{}".utf8)
        case .removeTaf: return Data()
        case .confirmTrial(_, let version): return KeyAct.confirmBody(version: version, asTrial: true)
        case .confirmDraft(_, let version): return KeyAct.confirmBody(version: version, asTrial: false)
        case .discardSettingUp: return Data()
        // The iPad's `reopenBody`, these exact bytes.
        case .reopenAPIDoor: return Data(#"{"open":true}"#.utf8)
        case .revokeAPIDoorKey, .removeAPIDoor: return Data()
        }
    }

    /// The act's name in the security key's sheet ("Sign out {device}"), so the person sees what the key approves.
    func title(_ words: Words, device: String = "") -> String {
        switch self {
        case .signOutDevice: return words("settings.devices.sign_out_prompt", ["device": device])
        case .timeZone(let zone): return words("settings.time_zone.prompt", ["zone": zone])
        // The taf's name goes in `device`'s place: the iPad's reason, "Resume {taf}", or "Resume all your tafs".
        case .resume(let agent): return agent == nil ? words("taf.halt.resume_all_prompt") : words("taf.halt.resume_prompt", ["taf": device])
        case .removeTaf: return words("taf.remove.prompt", ["taf": device])
        // The iPad's prompt, filled with the version and the taf by the caller, in `device`'s place.
        case .confirmTrial, .confirmDraft: return device
        // tafs cloud's own words for it, given in `device`'s place: its title, else its button.
        case .discardSettingUp: return device
        // The door's app, or the key's name, in `device`'s place, as the iPad's reasons; Remove door as its button says.
        case .reopenAPIDoor: return words("door.api.open_reason", ["app": device])
        case .revokeAPIDoorKey: return words("door.api.revoke_reason", ["key": device])
        case .removeAPIDoor: return words("door.remove_door")
        }
    }
}

/// The person chose "Approve on your phone instead" in the security key's sheet: nothing was approved or sent here, and
/// nothing is handed to the phone. Every act's line then says to approve on another device
/// (`approval.device_can_not_approve_approve`), through `CoachStart.why`, `NeedsYouModel.why` and `TafRemoval`.
struct ApproveOnPhone: Error {}

extension PasskeySession {
    /// Approve once, on the security key (kiff/cloud's `checkPasskeyAnswer`, from a session that approves with this
    /// Mac's own passkey): one fresh assertion over the answer's `kiff.answer.v1` (the hold, `approve-once`, no next
    /// step or note, the hold's accounting version as the person saw it, `signed_at` now), sent as
    /// `POST` to the hold's answer route, `card-exceptions/{id}/` and the answer (`Answer.rawValue`), with
    /// `{"signature":{"passkey":{…},"signed_at":"…"}}`. Never a
    /// device key's signature, never a window: one approval for this one call. A hold KIFF says can't be approved once,
    /// or one without its accounting version, is refused here before the key is asked. A refusal is KIFF's
    /// (`KIFFError`), so the card's line says it.
    func approveOnce(_ call: HeldCall, pin: SecurityKeyPIN?, now: Date = Date()) async throws {
        guard call.canApproveOnce else { throw KIFFError.refused(status: 0, code: "cannot_approve_once") }
        try await answerWithKey(call, .approveOnce, pin: pin, now: now)
    }

    /// Extra room, on the security key, as the iPad's (kiff/tafs#211, 6.13): KIFF's `change-card`, which gives the
    /// call's Card room for this total until it resets and lets this one call go on. KIFF takes it from the key as it
    /// takes Approve once (`checkPasskeyAnswer`: both grant authority), over the same `kiff.answer.v1` with
    /// `change-card`, sent to `POST /v1/me/card-exceptions/{id}/change-card`. Offered where approving once can't pass
    /// a total, so KIFF's `can_approve_once` isn't asked; the accounting version still is.
    func extraRoom(_ call: HeldCall, pin: SecurityKeyPIN?, now: Date = Date()) async throws {
        try await answerWithKey(call, .changeCard, pin: pin, now: now)
    }

    /// One answer that grants authority, on the key: its assertion in `signature.passkey`, beside the same `signed_at`.
    private func answerWithKey(_ call: HeldCall, _ answer: Answer, pin: SecurityKeyPIN?, now: Date) async throws {
        // A fill in Chrome opens only with the phone's release, which this Mac can't make: refused before the key is
        // asked, whatever drew the answer ("never an allowing answer without its release", the Chrome contract).
        guard !call.fillsInChrome else { throw ApproveOnPhone() }
        guard let version = call.accountingVersion else { throw KIFFError.refused(status: 0, code: "no_accounting_version") }
        let signedAt = KIFFMessage.time(now)
        let passkey = try await approver.answer(tenant: session.tenant, callID: call.id, answer: answer,
                                                accountingVersion: version, signedAt: signedAt, pin: pin)
        // The assertion's object as the key's answer gave it, and the same signed_at, in sorted keys.
        var body = Data(#"{"signature":{"passkey":"#.utf8)
        body.append(passkey)
        body.append(Data(#","signed_at":"\#(signedAt)"}}"#.utf8))
        let headers = ["Authorization": "Bearer \(session.accessToken)", "Accept": "application/json", "Content-Type": "application/json",
                       "Accept-Language": language, "User-Agent": "tafs-macos"]
        // The route is the answer's own name (`Answer.rawValue`), never spelled here: no source names an approve route
        // (`PlanqueRoutesTests`), so a planque one can't slip in beside it.
        let path = "/v1/me/card-exceptions/\(CloudClient.escaped(call.id))/\(answer.rawValue)"
        let (status, reply) = try await transport.send(HTTPRequest(method: "POST", path: path, headers: headers, body: body))
        guard (200..<300).contains(status) else { throw KIFFError(status: status, body: reply) }
    }
}

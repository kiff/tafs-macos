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
    /// Removing one of the account's own passkeys (the iPad's `preparePasskeyRemoval`): `DELETE /v1/me/passkeys/{id}`,
    /// empty body. KIFF takes it as an approval (`PhoneApprovalRules`; its handler wants a critical signature, which a
    /// security key's assertion is), so it's the key's, once.
    case removePasskey(id: String)
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
    /// An API door's new key (the iPad's `DoorsModel.newKey`): tafs cloud's `POST …/doors/{door}/keys` with
    /// `{"name":…}`, on the security key as the door's other acts are. The answer carries the key, shown once.
    case newAPIDoorKey(taf: String, door: String, name: String)
    /// Coach's drafted door approved (the iPad's `approveDoorDraft`): tafs cloud's `POST /v1/tafs/{taf}/doors` with the
    /// draft's `body`, canonical (RFC 8785), these exact bytes, on the security key as the door's other acts. The answer
    /// is the door and its first key, shown once.
    case addDraftedAPIDoor(taf: String, body: Data)
    /// Sends a door's held reply to its writer (tafs cloud's `doorSigned`): `{action: "send", text_sha256}`, the SHA-256
    /// of the exact text the owner read, so only that text goes.
    case sendHeldReply(taf: String, run: String, textSHA256: String)
    /// Answers a writer the taf couldn't help, in the owner's own words (tafs cloud's `unanswered`): the same route as a
    /// held reply, `{action: "send", text, text_sha256}`, the SHA-256 of the text exactly as typed, so only that text goes.
    case sendOwnReply(taf: String, run: String, text: String, textSHA256: String)
    /// Sharing a taf's KIFF agent with a group or one person (the iPad's `KIFFClient.share(agent:with:)`):
    /// `POST /v1/agents/{agent}/grants` with the share, and stopping (`unshare(agent:from:)`): `DELETE` with the group
    /// or the subject in the query and `{}`. KIFF takes each as an approval (`PhoneApprovalRules`), so each is the key's,
    /// one change at a time.
    case share(agent: String, Shares.Share)
    case unshare(agent: String, Shares.Share)
    /// The owner's answer to "Did this happen?" (the iPad's `KIFFClient.answerHappened`): KIFF's
    /// `POST /v1/me/did-this-happen/{proposal}` with `{"happened":true}` or `false`. It's an approval route (kiff/cloud's
    /// `PhoneApprovalRules`: No gives a Card its room back), so it's the security key's, once, for this one call. The
    /// first answer stands.
    case happened(proposal: String, Bool)
    /// Adding someone to a group, or changing their role (`manager` or `member`), as the iPad's `KIFFClient` writes it:
    /// `PUT /v1/groups/{group}/members/{subject}` with `{"role": role}`. It grants access, so it's approved as sharing a
    /// taf is: on the security key, once (group changes step B; KIFF verifies the assertion on this route). Taking someone
    /// out (`DELETE`) stays the device key's, as stopping a share does.
    case setMember(group: String, subject: String, role: String)

    var method: String {
        switch self {
        case .signOutDevice: return "DELETE"
        case .removePasskey: return "DELETE"
        case .timeZone: return "PUT"
        case .resume: return "POST"
        case .removeTaf: return "DELETE"
        case .confirmTrial, .confirmDraft: return "POST"
        case .discardSettingUp: return "POST"
        case .reopenAPIDoor: return "PATCH"
        case .newAPIDoorKey, .addDraftedAPIDoor, .sendHeldReply, .sendOwnReply: return "POST"
        case .revokeAPIDoorKey, .removeAPIDoor: return "DELETE"
        case .share: return "POST"
        case .unshare: return "DELETE"
        case .happened: return "POST"
        case .setMember: return "PUT"
        }
    }

    var path: String {
        switch self {
        case .signOutDevice(let id): return "/v1/me/devices/\(CloudClient.escaped(id))"
        case .removePasskey(let id): return "/v1/me/passkeys/\(CloudClient.escaped(id))"
        case .timeZone: return "/v1/me/time-zone"
        case .resume(let agent): return agent.map { "/v1/agents/\(CloudClient.escaped($0))/resume" } ?? "/v1/resume"
        case .removeTaf(let id): return "/v1/tafs/\(CloudClient.escaped(id))"
        case .confirmTrial(let id, _), .confirmDraft(let id, _): return "/v1/me/agent-drafts/\(CloudClient.escaped(id))/confirm"
        case .discardSettingUp(let agent): return "/v1/home/setting-up/\(CloudClient.escaped(agent))/discard"
        case .reopenAPIDoor(let taf, let door), .removeAPIDoor(let taf, let door):
            return "/v1/tafs/\(CloudClient.escaped(taf))/doors/\(CloudClient.escaped(door))"
        case .addDraftedAPIDoor(let taf, _): return "/v1/tafs/\(CloudClient.escaped(taf))/doors"
        case .sendHeldReply(let taf, let run, _), .sendOwnReply(let taf, let run, _, _): return "/v1/tafs/\(CloudClient.escaped(taf))/doors/replies/\(CloudClient.escaped(run))"
        case .newAPIDoorKey(let taf, let door, _):
            return "/v1/tafs/\(CloudClient.escaped(taf))/doors/\(CloudClient.escaped(door))/keys"
        case .revokeAPIDoorKey(let taf, let door, let key):
            return "/v1/tafs/\(CloudClient.escaped(taf))/doors/\(CloudClient.escaped(door))/keys/\(CloudClient.escaped(key))"
        case .share(let agent, _): return "/v1/agents/\(CloudClient.escaped(agent))/grants"
        case .unshare(let agent, let share):
            // The iPad's `escapedQuery`: letters, digits and -._~ only.
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            func q(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
            let query = share.group.map { "group=\(q($0))" } ?? share.subject.map { "subject=\(q($0))" } ?? ""
            return "/v1/agents/\(CloudClient.escaped(agent))/grants?\(query)"
        case .happened(let proposal, _): return "/v1/me/did-this-happen/\(CloudClient.escaped(proposal))"
        case .setMember(let group, let subject, let role):
            return PeopleChange.setMember(group: group, subject: subject, role: role).path
        }
    }

    var body: Data {
        switch self {
        case .signOutDevice: return Data()
        case .removePasskey: return Data()
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
        case .addDraftedAPIDoor(_, let body): return body
        // `{"action":"send","text_sha256":…}`, sorted keys: the exact bytes that are signed and sent.
        case .sendHeldReply(_, _, let hash):
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return (try? encoder.encode(["action": "send", "text_sha256": hash])) ?? Data()
        // `{"action":"send","text":…,"text_sha256":…}`, sorted keys: the owner's words as typed, signed and sent as is.
        case .sendOwnReply(_, _, let text, let hash):
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return (try? encoder.encode(["action": "send", "text": text, "text_sha256": hash])) ?? Data()
        // `{"name":…}`, as the iPad's `newKeyBody`: the exact bytes that are signed and sent.
        case .newAPIDoorKey(_, _, let name):
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return (try? encoder.encode(["name": name])) ?? Data()
        case .share(_, let share):
            // The share alone, `{"group":…}` or `{"subject":…}`, as the iPad sends it.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return (try? encoder.encode(share)) ?? Data()
        // The iPad sends an empty object with the DELETE.
        case .unshare: return Data("{}".utf8)
        // The iPad's body, `["happened": happened]`, these exact bytes.
        case .happened(_, let happened): return Data(happened ? #"{"happened":true}"#.utf8 : #"{"happened":false}"#.utf8)
        // PeopleChange's body, `{"role":…}`: the same bytes as the device-key route sent.
        case .setMember(let group, let subject, let role): return PeopleChange.setMember(group: group, subject: subject, role: role).body
        }
    }

    /// The act's name in the security key's sheet ("Sign out {device}"), so the person sees what the key approves.
    func title(_ words: Words, device: String = "") -> String {
        switch self {
        case .signOutDevice: return words("settings.devices.sign_out_prompt", ["device": device])
        // The iPad's reason, "Remove the passkey {name} from your account", the passkey's name in `device`'s place.
        case .removePasskey: return words("settings.devices.passkey_remove_prompt", ["name": device])
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
        // The iPad's reason, "New key for {app}", with the door's app in `device`'s place.
        case .newAPIDoorKey: return words("door.api.new_key_reason", ["app": device])
        // The iPad's reason, "{app} will be able to hand {taf} work", with "app|taf" in `device`'s place.
        case .addDraftedAPIDoor:
            let parts = device.split(separator: "|", maxSplits: 1).map(String.init)
            return words("door.api.faceid_body", ["app": parts.first ?? device, "taf": parts.count > 1 ? parts[1] : ""])
        // The iPad's reason for the whole change, "Share {taf}", with the taf in `device`'s place.
        case .share, .unshare: return words("people.share.title", ["taf": device])
        // The iPad's prompts, "Say it happened: {title}" and "Say it didn't happen: {title}", the call's title in
        // `device`'s place.
        case .happened(_, let happened):
            return words(happened ? "needs_you.prompt.happened" : "needs_you.prompt.did_not_happen", ["title": device])
        // The change in the person's words, the line Touch ID asked with ("Add {name} to {group}"), in `device`'s place.
        case .setMember: return device
        // tafs cloud's own prompt for it ("Send this reply to Ben"), in `device`'s place.
        case .sendHeldReply, .sendOwnReply: return device
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
        // A purchase is approved once, never with extra room, and only for the case as read: one this app can't read is
        // refused before the key is asked.
        guard !call.purchaseUnreadable, call.purchase == nil || answer == .approveOnce else {
            throw KIFFError.refused(status: 0, code: "purchase_answer")
        }
        let signedAt = KIFFMessage.time(now)
        let passkey = try await approver.answer(tenant: session.tenant, callID: call.id, answer: answer,
                                                accountingVersion: version, signedAt: signedAt, pin: pin, purchase: call.purchase?.binding)
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

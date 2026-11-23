import Foundation

/// A call KIFF holds for the person's answer (Needs you), as KIFF sends it. Its words are
/// KIFF's and the taf's own, drawn as sent: the app never words a hold itself.
struct HeldCall: Decodable, Identifiable, Equatable {
    let id: String
    /// The agent whose call it is.
    let subject: String
    let action: String
    /// The call's tool, as KIFF names it for people.
    let title: String?
    /// Why it is held, in KIFF's words for people.
    let reasonText: String?
    /// What the call is on and why, in the taf's own words. Unsigned, possibly from a
    /// customer's text: drawn plain, and never used to decide anything.
    let tafAbout: String?
    let tafReason: String?
    /// The Card's next steps a refusal may name ("return first").
    let nextSteps: [String]
    /// Whether approving once can pass this call; true when KIFF doesn't say.
    let canApproveOnce: Bool
    let createdAt: Date
    let expiresAt: Date?
    /// The hold's accounting version: part of what is signed, so an answer counts only for
    /// the hold as it stood when the person saw it.
    let accountingVersion: Int?
    /// What the call moves, from KIFF's numbers: the first of its `parameters` that KIFF names
    /// a unit for (`parameter_units`), as the iPad reads it. Nil when KIFF names none: the
    /// app never guesses an amount's unit.
    let amount: TafCard.Amount?
    /// What the call is on, as KIFF files it (`entity_id`).
    let entityID: String?
    /// Whether KIFF keeps the call's arguments: a gateway call, filed under its tool call's id.
    let hasArguments: Bool
    /// KIFF's id for the call the hold is of (`proposal_id`): what the Record's line is matched by.
    let proposalID: String?
    /// What KIFF holds it as (`kind`): a Card unit request ("card_unit") isn't a held call.
    let kind: String?
    /// The held step fills a field in the owner's Chrome (its `browser` block carries `fill` or `sealed_fill`;
    /// kiff/tafs `docs/chrome.md`, "never an allowing answer without its release"). Only the paired phone's own release
    /// opens a fill, and this Mac holds no approval key to make one: it offers no allowing answer for it, only the phone.
    let fillsInChrome: Bool

    /// The calls KIFF holds, by proposal id (else the hold's own id), as the iPad reads them for the
    /// Record's "no longer waiting" (`AppModel.isWaiting`, AppModel.swift:706-712, 2664): a Card unit
    /// request is left out.
    static func heldProposals(_ calls: [HeldCall]) -> Set<String> {
        Set(calls.filter { $0.kind != "card_unit" }.map { $0.proposalID ?? $0.id })
    }

    /// The call's name for people, as the iPad's `proposed.summary` (`KIFFMapping.held`,
    /// KIFFMapping.swift:283-285): `CallNames.says`, then what it's on for a call without
    /// arguments. A gateway call is filed under its tool call's id, which says nothing.
    var summary: String {
        let name = CallNames.says(action, title: title)
        guard !hasArguments, let entityID, !entityID.isEmpty else { return name }
        return "\(name) \(entityID)"
    }

    enum CodingKeys: String, CodingKey {
        case id, subject, action, title, reasonText = "reason_text", tafAbout = "taf_about", tafReason = "taf_reason"
        case nextSteps = "next_steps", canApproveOnce = "can_approve_once", createdAt = "created_at"
        case expiresAt = "expires_at", accountingVersion = "accounting_version"
        case parameters, parameterUnits = "parameter_units"
        case entityID = "entity_id", arguments
        case proposalID = "proposal_id", kind, browser
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        subject = try c.decode(String.self, forKey: .subject)
        action = try c.decode(String.self, forKey: .action)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        accountingVersion = try c.decodeIfPresent(Int.self, forKey: .accountingVersion)
        // Words that aren't text are left out, never the hold.
        func text(_ key: CodingKeys) -> String? {
            guard let value = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil else { return nil }
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
        }
        title = text(.title)
        reasonText = text(.reasonText)
        tafAbout = text(.tafAbout)
        tafReason = text(.tafReason)
        nextSteps = ((try? c.decodeIfPresent([String].self, forKey: .nextSteps)) ?? nil) ?? []
        canApproveOnce = ((try? c.decodeIfPresent(Bool.self, forKey: .canApproveOnce)) ?? nil) ?? true
        entityID = (try? c.decodeIfPresent(String.self, forKey: .entityID)) ?? nil
        hasArguments = c.contains(.arguments) && !((try? c.decodeNil(forKey: .arguments)) ?? true)
        proposalID = (try? c.decodeIfPresent(String.self, forKey: .proposalID)) ?? nil
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? nil
        // Any value but null counts, so a fill this app can't read is still never allowed here.
        struct Browser: Decodable {
            let fills: Bool
            enum CodingKeys: String, CodingKey { case fill, sealedFill = "sealed_fill" }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                func given(_ key: CodingKeys) -> Bool { c.contains(key) && !((try? c.decodeNil(forKey: key)) ?? false) }
                fills = given(.fill) || given(.sealedFill)
            }
        }
        if c.contains(.browser), !((try? c.decodeNil(forKey: .browser)) ?? false) {
            // A browser block that doesn't read as an object can't be checked: taken as a fill, never allowed here.
            fillsInChrome = (try? c.decode(Browser.self, forKey: .browser))?.fills ?? true
        } else {
            fillsInChrome = false
        }
        struct Unit: Decodable { let unit: String; let scale: Int }
        let parameters = ((try? c.decodeIfPresent([String: Int64].self, forKey: .parameters)) ?? nil) ?? [:]
        let units = ((try? c.decodeIfPresent([String: Unit].self, forKey: .parameterUnits)) ?? nil) ?? [:]
        let byName = Dictionary(units.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        if let named = parameters.sorted(by: { $0.key < $1.key }).first(where: { byName[$0.key.lowercased()] != nil }),
           let unit = byName[named.key.lowercased()] {
            amount = TafCard.Amount(minor: named.value, unit: unit.unit, scale: unit.scale)
        } else {
            amount = nil
        }
    }
}

/// The person's answer to a held call, as KIFF names it.
enum Answer: String {
    case approveOnce = "approve-once"
    case reject
    case changeCard = "change-card"

    /// Whether the answer gives the taf authority it didn't have. Only a refusal doesn't.
    var grants: Bool { self != .reject }
}

extension KIFFMessage {
    /// What is signed to answer a held call: `kiff.answer.v1`, one field per line. An absent
    /// next step or note is an empty line.
    static func answer(tenant: String, callID: String, answer: Answer, nextStep: String?, noteHash: String = "",
                       accountingVersion: Int, signedAt: String) -> String {
        ["kiff.answer.v1", tenant, callID, answer.rawValue, nextStep ?? "", noteHash, String(accountingVersion), signedAt]
            .joined(separator: "\n")
    }
}

/// How an answer that grants authority is signed on this computer.
enum ApprovalRoute: Equatable {
    /// By this Mac's approval key, behind Touch ID.
    case touchID
    /// On the phone, or by a passkey: this Mac has no approval key.
    case phoneOrPasskey
    /// By the person's USB security key, registered through this Mac's pairing, sent as
    /// `KIFF-Passkey-Assertion` (`PasskeyApprover`): macOS 12's route, as these Macs have no Touch ID.
    /// Given by `ApprovalRoute.of(_:securityKey:)` only once `Features.macPasskeyApprovals` is on.
    case passkey

    /// Account › How tafs works: where this Mac's approvals are signed. Only the security key's
    /// route signs them here ("Your answers are signed on this {device}."); every other Mac
    /// approves on the phone ("Your approvals are signed on your phone."), as a computer that only
    /// views.
    var howItWorksKey: String {
        self == .passkey ? "sign_in.every_action_taf_takes_goes" : "sign_in.every_action_taf_takes_goes_view"
    }

    static func of(_ means: ApprovalMeans) -> ApprovalRoute {
        switch means {
        case .key: return .touchID
        case .passkey: return .phoneOrPasskey
        }
    }
}

extension AccountClient {
    /// The calls waiting for the person's answer.
    func heldCalls() async throws -> [HeldCall] {
        struct Answer: Decodable { let exceptions: [HeldCall] }
        let answer: Answer = try read(try await send("GET", "/v1/me/card-exceptions?status=held"))
        return answer.exceptions
    }

    /// Refuses a held call, signed by the device key over the hold as the person saw it.
    /// A refusal takes authority away, so it needs no approval key: any signed-in Mac may
    /// refuse. `nextStep` must be one of the call's own next steps. `confirm` runs just before
    /// the key signs, as the iPad's `signer.sign(_:reason:)` asks for the owner there: when it
    /// throws, nothing is signed or sent, and its error comes back as `Unconfirmed`.
    func refuse(_ call: HeldCall, nextStep: String? = nil, at date: Date = Date(),
                confirm: () async throws -> Void = {}) async throws {
        guard let signMessage else { throw KIFFError.refused(status: 0, code: "no_device_key") }
        guard let version = call.accountingVersion else { throw KIFFError.refused(status: 0, code: "no_accounting_version") }
        if let nextStep, !call.nextSteps.contains(nextStep) { throw KIFFError.refused(status: 0, code: "not_a_next_step") }
        do { try await confirm() } catch { throw Unconfirmed(error: error) }
        let signedAt = KIFFMessage.time(date)
        let message = KIFFMessage.answer(tenant: session.tenant, callID: call.id, answer: .reject, nextStep: nextStep,
                                         accountingVersion: version, signedAt: signedAt)
        struct Signature: Encodable { let signed_at: String; let value: String }
        struct Body: Encodable { let next_step: String?; let signature: Signature }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(Body(next_step: nextStep, signature: Signature(signed_at: signedAt, value: try signMessage(message))))
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        let id = call.id.addingPercentEncoding(withAllowedCharacters: allowed) ?? call.id
        _ = try await send("POST", "/v1/me/card-exceptions/\(id)/reject", body: body)
    }
}

/// The owner didn't confirm an answer before the device key signed it: nothing was signed or
/// sent. `error` is the prompt's own, to tell a closed prompt from a failed one.
struct Unconfirmed: Error {
    let error: Error
}

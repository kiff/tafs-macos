import Foundation

/// Removing a taf for good, as the iPad's `removeTaf` (AppModel.swift:3899-3955): the approval first, before anything
/// changes; then KIFF revokes its Cards, so it can't act whatever happens next; then tafs cloud stops it and deletes its
/// runs, chats, memory and key, and frees its name. On this Mac the approval is the security key's (kiff/cloud#96): one
/// assertion over `DELETE /v1/tafs/{id}` and its empty body, sent to tafs cloud with `KIFF-Passkey-Assertion`, where the
/// iPad sends its approval key's signature.
enum TafRemoval {
    /// What tafs cloud did: each step ("connections", "schedule", "history", "memory", "key", "name") is in `removed` or
    /// `failed`. A second removal finishes what the first left.
    struct Removal: Decodable, Equatable {
        let done: Bool
        let removed: [String]
        let failed: [String]
    }

    /// One step's name, as the iPad's `removalStep`.
    static func step(_ step: String, words: Words) -> String {
        switch step {
        case "connections", "schedule", "history", "memory", "key", "name": return words("taf.remove.step_\(step)")
        default: return step
        }
    }

    /// The confirmation's body: the shared line, then what goes with it in tafs cloud's words, as the iPad's `removeBody`.
    static func body(_ words: Words, goes: String?) -> String {
        guard let goes, !goes.isEmpty else { return words("taf.remove_body") }
        return words("taf.remove_body") + "\n\n" + goes
    }

    /// Removes the taf. `sign` is the security key's approval of the `DELETE` (through its sheet, named "Remove {taf}
    /// for good"); `revoke` revokes one Card in KIFF; `remove` sends the `DELETE` with the assertion. What to tell the
    /// person, as the iPad's; nil when the sheet was closed (nothing changed, nothing said).
    static func remove(taf: String, cloudID: String, cardIDs: [String], words: Words,
                       sign: (KeyAct, String) async throws -> String,
                       revoke: (String) async throws -> Void,
                       remove: (String) async throws -> Removal) async -> String? {
        let act = KeyAct.removeTaf(cloudID)
        let assertion: String
        do { assertion = try await sign(act, act.title(words, device: taf)) } catch is CancellationError {
            return nil
        } catch {
            return words("taf.remove.not_confirmed")
        }
        var cardsLeft = 0
        for id in cardIDs {
            do { try await revoke(id) } catch { cardsLeft += 1 }
        }
        let revoked = cardsLeft == 0 ? words("taf.remove.cards_revoked") : words("card.kiff_did_not_revoke_cards", ["cards_left": words.number(cardsLeft)])
        let removal: Removal
        do { removal = try await remove(assertion) } catch {
            return words("taf.remove.cloud_did_not_answer", ["cards": revoked, "why": CoachStart.why(error, words: words)])
        }
        let cards = revoked + (removal.removed.contains("connections") ? words("connect.connections_disconnected") : "")
        guard removal.done else {
            let failed = removal.failed.map { step($0, words: words) }.joined(separator: ", ")
            return words("taf.remove.not_finished_after", ["cards": cards, "failed": failed])
        }
        return words("connect.schedule_chats_run_reports_memory", ["cards": cards, "taf": taf])
    }
}

extension CloudClient {
    /// What removing the taf takes with it, before the key is asked (`GET /v1/tafs/{id}/removal`, which ends nothing):
    /// tafs cloud's words, or nil when it said none.
    func removalPreview(_ taf: String) async throws -> String? {
        struct Preview: Decodable { let words: String? }
        let preview: Preview = try await get("/v1/tafs/\(Self.escaped(taf))/removal")
        let said = preview.words?.trimmingCharacters(in: .whitespacesAndNewlines)
        return said?.isEmpty == false ? said : nil
    }

    /// Removes the taf, with the security key's assertion over this exact request (`KeyAct.removeTaf`).
    func remove(_ taf: String, assertion: String) async throws -> TafRemoval.Removal {
        let headers = ["Authorization": "Bearer \(session.accessToken)", "Accept": "application/json",
                       "Accept-Language": language, "User-Agent": "tafs-macos", Passkeys.headerName: assertion]
        let (status, body) = try await transport.send(HTTPRequest(method: "DELETE", path: "/v1/tafs/\(Self.escaped(taf))", headers: headers))
        guard (200..<300).contains(status) else { throw CloudRefusal(status: status, body: body) }
        return try decoded(body)
    }
}

extension PasskeySession {
    /// The security key's assertion over one act's request, without sending it: for an act whose request goes after other
    /// steps (a taf's removal), as the iPad signs before it revokes. One assertion, for that request only.
    func assertion(for act: KeyAct, pin: SecurityKeyPIN?) async throws -> String {
        try await approver.approve(tenant: session.tenant, method: act.method, path: act.path, body: act.body, pin: pin)
    }
}

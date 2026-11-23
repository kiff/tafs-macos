import Foundation

/// Ending connections from this Mac: Remove access, Cancel the request, Cancel the sign-in and
/// Clear (the removed tafs' connections), as the iPad's `disconnect(grantID:)` and
/// `clearRemovedConnections` (`AppModel.swift:7501-7598`) and Windows' `AppConnections.EndAsync`.
///
/// The owner's rule (docs/approvals.md › Ending access with Touch ID): on a Mac whose device key
/// is in the Secure Enclave and that can check Touch ID, the person passes Touch ID (biometrics
/// only, never the Mac's password), then the device key signs planque's `DELETE` of each grant.
/// Any other Mac sends nothing and says to approve on the phone. Only ending is done here:
/// connecting, Sign in again, a key and every approval stay the phone's or the security key's.
enum ConnectionEnding {
    /// Where ending a connection is done.
    enum Route: Equatable {
        /// Here: Touch ID, then the device key signs the `DELETE`.
        case touchID
        /// On the phone (`phoneLine`): this Mac sends nothing.
        case phone
    }

    /// What a Mac that ends nothing itself says: approve on another device.
    static let phoneLine = "approval.device_can_not_approve_approve"

    /// Touch ID only with the session's key in the Secure Enclave and biometrics this Mac can
    /// check now; a software key, a Mac without Touch ID, or Touch ID not set up or locked out
    /// goes to the phone. planque would take a software key's `DELETE` too, so this is the rule.
    static func route(enclaveKey: Bool, biometrics: Bool) -> Route {
        enclaveKey && biometrics ? .touchID : .phone
    }

    /// Whether Touch ID's enrolled fingers are still the ones this session first saw
    /// (`LAContext.evaluatedPolicyDomainState`). On a Mac, anyone who knows its password can add a
    /// finger in System Settings, so a finger added since would let the password in: a changed
    /// set ends nothing here until the next sign-in, as the iPad's approval key is renewed when
    /// its biometrics change.
    enum Fingers: Equatable {
        /// The set recorded for this session: Touch ID may end a connection.
        case same
        /// Another set, or none: the phone, until the next sign-in.
        case changed
        /// Nothing recorded for this session yet: `now` is recorded (`fingersRecord`).
        case first
    }

    /// Reads the record kept for `session` (`fingersRecord`) against the set Touch ID has `now`.
    static func fingers(recorded: Data?, session: String, now: Data?) -> Fingers {
        // No set, or an id that can't be told apart from its record: never Touch ID.
        guard let now, !now.isEmpty, !session.utf8.contains(0x0A) else { return .changed }
        guard let recorded, let cut = recorded.firstIndex(of: 0x0A),
              recorded[recorded.startIndex..<cut] == Data(session.utf8) else { return .first }
        return recorded[recorded.index(after: cut)...] == now ? .same : .changed
    }

    /// What is kept for `session`: the session's id, a line break, then the set's opaque state.
    static func fingersRecord(session: String, now: Data) -> Data {
        Data(session.utf8) + Data([0x0A]) + now
    }

    /// How an ending went, as Windows' `EndAsync` answers it.
    struct Outcome: Equatable {
        /// Connections asked to end that weren't.
        var left = 0
        /// planque's refusal, in words (`connect.not_disconnected`); nil when none.
        var why: String?
        /// Touch ID wasn't passed: nothing was sent.
        var unconfirmed = false
        /// The account changed on the way: nothing more was sent, and nothing is said.
        var stopped = false
    }

    /// Asks once (`confirm`, Touch ID with `prompt` as its reason), then ends each connection in
    /// turn (`delete`). Nothing is sent unless the prompt was passed, and nothing more once the
    /// session changed (`current`). A refusal is counted and the next one is still tried.
    static func end(_ ids: [String], prompt: String,
                    confirm: (String) async throws -> Void,
                    delete: (String) async throws -> Void,
                    current: () async -> Bool,
                    _ say: Words) async -> Outcome {
        guard !ids.isEmpty else { return Outcome() }
        do {
            try await confirm(prompt)
        } catch {
            guard await current() else { return Outcome(left: ids.count, stopped: true) }
            return Outcome(left: ids.count, unconfirmed: true)
        }
        guard await current() else { return Outcome(left: ids.count, stopped: true) }
        var out = Outcome()
        for (i, id) in ids.enumerated() {
            do {
                try await delete(id)
            } catch {
                out.left += 1
                out.why = say("connect.not_disconnected", ["why": PlanqueEnrolment.Why(error).words(say)])
            }
            guard await current() else {
                out.left += ids.count - i - 1
                out.stopped = true
                return out
            }
        }
        return out
    }

    /// What Disconnect says afterwards, as the iPad's: nothing for a prompt that was closed or a
    /// session that changed, else planque's refusal.
    static func disconnectNote(_ outcome: Outcome) -> String? {
        outcome.stopped || outcome.unconfirmed ? nil : outcome.why
    }

    /// Which of the removed tafs' connections Clear ends and which it keeps, as the iPad's and
    /// Windows' `ClearPlan`: only those tafs cloud lists as a removed taf's, and one a live taf's
    /// Card still uses (`used_by`) is kept, for those tafs.
    static func clearPlan(_ ids: [String], listed: [String: Apps.RemovedTaf.Grant]) -> (ending: [String], keptFor: [[String]]) {
        let asked = ids.filter { listed[$0] != nil }
        let keptFor = asked.compactMap { id in listed[id].flatMap { $0.usedBy.isEmpty ? nil : $0.usedBy.map(\.name) } }
        return (asked.filter { listed[$0]?.usedBy.isEmpty == true }, keptFor)
    }

    /// What Clear says afterwards, as the iPad's `ConnectionGroupWords.cleared`: "Cleared 2.",
    /// "Kept 1 for Chargebacks, whose Card uses it.", and how many couldn't be, to try again.
    static func cleared(done: Int, kept: Int, keptFor: [String], left: Int, _ say: Words) -> String {
        var parts: [String] = []
        if done > 0 { parts.append(say.count("connect.clear_removed.cleared", done)) }
        if kept > 0 {
            var seen = Set<String>()
            let names = keptFor.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && seen.insert($0).inserted }
            let who = names.isEmpty ? say("connect.kept.another_taf") : say.list(names)
            parts.append(say.count(names.count > 1 ? "connect.kept.for_cards" : "connect.kept.for_card", kept, ["who": who]))
        }
        if left > 0 { parts.append(say("connect.could_not_cleared_try_again", ["left": say.number(left)])) }
        return parts.joined(separator: " ")
    }

    /// What Clear says afterwards: not done when Touch ID wasn't passed, nothing when the session
    /// changed, else how it went.
    static func clearNote(_ outcome: Outcome, ending: Int, keptFor: [[String]], _ say: Words) -> String? {
        if outcome.stopped { return nil }
        if outcome.unconfirmed { return say("common.not_done_unconfirmed") }
        return cleared(done: ending - outcome.left, kept: keptFor.count, keptFor: keptFor.flatMap { $0 }, left: outcome.left, say)
    }
}

import Foundation

/// The paused run asked to go on once KIFF took the answer to its held call, as the iPad's `continueHeld` (kiff/tafs#206) and
/// Windows' `HeldContinue`: tafs cloud's `POST /v1/tafs/{taf}/holds/{hold}/continue`, as the session, by tafs cloud's taf id and
/// KIFF's hold id. A refusal is never swallowed: a run that had already ended says so in tafs cloud's words (`run_ended`, with
/// `hold_run_ended`'s line in the person's language), and another refusal says what didn't go through and why. A run KIFF's
/// alert continued first answers 409 (`not_paused`): it went on, so nothing is said. KIFF's alert and the hold's expiry still
/// continue a run this misses.
enum HeldContinue {
    /// tafs cloud's continue for the taf's hold.
    static func path(taf: String, hold: String) -> String {
        "/v1/tafs/\(CloudClient.escaped(taf))/holds/\(CloudClient.escaped(hold))/continue"
    }

    /// What Needs you says after it: nothing once tafs cloud took it (`error` nil), or when the run already went on (409);
    /// tafs cloud's own words when it sent some (the run had ended, in the person's language); otherwise
    /// "{summary} didn't go through." with why: tafs cloud's refusal, or, when it wasn't reached, that it wasn't.
    static func said(_ words: Words, summary: String, error: Error?) -> String? {
        guard let error else { return nil }
        if let refusal = error as? CloudRefusal {
            if refusal.status == 409 { return nil }
            if let own = refusal.words?.trimmingCharacters(in: .whitespacesAndNewlines), !own.isEmpty { return own }
            return words("common.didnt_go_through", ["what": summary, "why": refusal.why(words)])
        }
        return words("common.didnt_go_through", ["what": summary, "why": words("error.offline")])
    }
}

extension CloudClient {
    /// Asks tafs cloud to continue the taf's run that paused on the hold KIFF just took an answer to (`HeldContinue`).
    func continueHeld(taf: String, hold: String) async throws {
        _ = try await post(HeldContinue.path(taf: taf, hold: hold), [String: String]())
    }
}

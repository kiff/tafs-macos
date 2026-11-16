import Foundation

/// What the PIN sheet says for each of the security key's answers, in the shared words
/// (`approval.security_key.*`). Every failure says nothing was approved; where nothing was
/// refused, the request is kept.
enum SecurityKeyWords {
    /// The line for why the key gave no approval. Authenticator data that KIFF would refuse (no
    /// user verification among them) is the key failing to sign, never the key's own decline.
    static func line(_ error: Error, words: Words) -> String {
        switch error {
        case let failure as SecurityKeyFailure: return line(failure, words: words)
        default: return words("approval.security_key.failed")
        }
    }

    static func line(_ failure: SecurityKeyFailure, words: Words) -> String {
        switch failure {
        case .noKey: return words("approval.security_key.no_key")
        case .severalKeys: return words("approval.security_key.several_keys")
        case .notFIDO2: return words("approval.security_key.not_fido2")
        case .pinTooShort: return words("approval.security_key.pin_too_short")
        case .pinTooLong: return words("approval.security_key.pin_too_long")
        case .pinNotSet: return words("approval.security_key.no_pin_set")
        case .wrongPIN(let left?) where left > 0: return words.count("approval.security_key.wrong_pin", left)
        case .wrongPIN: return words("approval.security_key.wrong_pin_no_count")
        case .pinBlocked: return words("approval.security_key.locked")
        case .pinPaused: return words("approval.security_key.pin_paused")
        case .notThisKey: return words("approval.security_key.not_this_key")
        case .timedOut: return words("approval.security_key.timed_out")
        case .denied: return words("approval.security_key.not_allowed")
        case .removed: return words("approval.security_key.unplugged")
        case .pinMissing, .pinUsed, .failed: return words("approval.security_key.failed")
        }
    }

    /// The tries left before the key locks, read before the PIN is asked, when the key says.
    static func triesLeft(_ count: Int, words: Words) -> String {
        words.count("approval.security_key.tries_left", count)
    }

    /// Whether the sheet stays open for the person to try again: anything but a locked key.
    static func mayTryAgain(_ error: Error) -> Bool {
        if case SecurityKeyFailure.pinBlocked? = error as? SecurityKeyFailure { return false }
        return true
    }
}

extension ApprovalRoute {
    /// This Mac's route: the security key's (`.passkey`) for a passkey session whose security key
    /// goes with this Mac (`SecurityKeyStore`), once passkey approvals are on; otherwise as
    /// `of(_:)`, so a Mac without its key, or with the switch off, approves on the phone.
    static func of(_ means: ApprovalMeans, securityKey: Bool, enabled: Bool = Features.macPasskeyApprovals) -> ApprovalRoute {
        if means == .passkey, securityKey, enabled { return .passkey }
        return of(means)
    }
}

import Foundation

private func words(_ language: String = "en") throws -> Words { try Words(language: language, folder: URL(fileURLWithPath: ".shared/app/strings")) }

let approvalsSecurityKeyWordsTests: [Test] = [
    Test("each of the key's failures says its own shared line") {
        let w = try words()
        let cases: [(SecurityKeyFailure, String)] = [
            (.noKey, "approval.security_key.no_key"), (.severalKeys, "approval.security_key.several_keys"),
            (.notFIDO2, "approval.security_key.not_fido2"), (.pinTooShort, "approval.security_key.pin_too_short"),
            (.pinTooLong, "approval.security_key.pin_too_long"), (.pinNotSet, "approval.security_key.no_pin_set"),
            (.wrongPIN(triesLeft: nil), "approval.security_key.wrong_pin_no_count"), (.pinBlocked, "approval.security_key.locked"),
            (.pinPaused, "approval.security_key.pin_paused"), (.notThisKey, "approval.security_key.not_this_key"),
            (.timedOut, "approval.security_key.timed_out"), (.denied, "approval.security_key.not_allowed"),
            (.removed, "approval.security_key.unplugged"), (.failed(code: -9), "approval.security_key.failed"),
            (.pinMissing, "approval.security_key.failed"), (.pinUsed, "approval.security_key.failed"),
        ]
        for (failure, key) in cases {
            let line = SecurityKeyWords.line(failure, words: w)
            try expectEqual(line, w(key))
            try expect(line != key, "\(key) is in the shared words")
        }
    },
    Test("a wrong PIN says the tries left, in each language's plural") {
        try expectEqual(SecurityKeyWords.line(SecurityKeyFailure.wrongPIN(triesLeft: 1), words: try words()), "Wrong PIN. 1 try left before the key locks.")
        try expectEqual(SecurityKeyWords.line(SecurityKeyFailure.wrongPIN(triesLeft: 5), words: try words()), "Wrong PIN. 5 tries left before the key locks.")
        try expectEqual(SecurityKeyWords.line(SecurityKeyFailure.wrongPIN(triesLeft: 0), words: try words()), try words()("approval.security_key.wrong_pin_no_count"))
        try expectEqual(SecurityKeyWords.triesLeft(3, words: try words("pl")), "Zostały 3 próby, zanim klucz się zablokuje.")
        try expectEqual(SecurityKeyWords.triesLeft(5, words: try words("pl")), "Zostało 5 prób, zanim klucz się zablokuje.")
    },
    Test("authenticator data without user verification is the key failing to sign, never its decline") {
        let w = try words()
        try expectEqual(SecurityKeyWords.line(PasskeyRefusal.notVerified, words: w), w("approval.security_key.failed"))
        try expect(SecurityKeyWords.line(PasskeyRefusal.notVerified, words: w) != w("approval.security_key.not_allowed"), "not the decline")
        for refusal in [PasskeyRefusal.notKIFF, .canLeave, .otherCredential, .unreadable, .off] {
            try expectEqual(SecurityKeyWords.line(refusal, words: w), w("approval.security_key.failed"))
        }
    },
    Test("a locked key closes the sheet; anything else may be tried again") {
        try expectEqual(SecurityKeyWords.mayTryAgain(SecurityKeyFailure.pinBlocked), false)
        try expectEqual(SecurityKeyWords.mayTryAgain(SecurityKeyFailure.wrongPIN(triesLeft: 2)), true)
        try expectEqual(SecurityKeyWords.mayTryAgain(SecurityKeyFailure.noKey), true)
    },
    Test("the security key's route only for a passkey session with its key, and only once switched on") {
        try expectEqual(ApprovalRoute.of(.passkey, securityKey: true, enabled: true), .passkey)
        try expectEqual(ApprovalRoute.of(.passkey, securityKey: false, enabled: true), .phoneOrPasskey)
        try expectEqual(ApprovalRoute.of(.passkey, securityKey: true, enabled: false), .phoneOrPasskey)
        try expectEqual(ApprovalRoute.of(.passkey, securityKey: true), .phoneOrPasskey)
        try expectEqual(ApprovalRoute.of(.key(Data([1])), securityKey: true, enabled: true), .touchID)
    },
    Test("the PIN sheet's purpose picks its words: approving a request, or adding the key while this computer pairs") {
        let w = try words()
        try expectEqual(w(SecurityKeySheetPurpose.approve.titleKey), "Approve with your security key")
        try expectEqual(w(SecurityKeySheetPurpose.addKey.titleKey), "Add your security key to this computer")
        try expectEqual(w(SecurityKeySheetPurpose.addKey.leadKey),
                        "Enter your security key's PIN to add it. tafs asks for it each time and never stores it.")
        try expectEqual(w(SecurityKeySheetPurpose.addKey.actionKey), "Add key")
        try expectEqual(w(SecurityKeySheetPurpose.addKey.closeKey), "Pair without a key")
        try expectEqual(SecurityKeySheetPurpose.approve.leadKey, "approval.security_key.enter_pin")
        try expectEqual(SecurityKeySheetPurpose.approve.actionKey, "approval.approve")
        try expectEqual(SecurityKeySheetPurpose.approve.closeKey, "common.cancel")
        let fr = try words("fr")
        try expectEqual(fr(SecurityKeySheetPurpose.addKey.closeKey), "Associer sans clé")
    },
]

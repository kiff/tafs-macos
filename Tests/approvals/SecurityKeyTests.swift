import Foundation

/// The security key's side that needs no Mac: what is asked of the key, its PIN's one buffer,
/// libfido2's codes as failures, and the attestation object (the app's `FidoKey` uses exactly these).

private func pin(_ text: String) throws -> SecurityKeyPIN {
    var bytes = Array(text.utf8)
    return try SecurityKeyPIN(utf8: &bytes)
}

private func refusedPIN(_ text: String, _ expected: SecurityKeyFailure) throws {
    var bytes = Array(text.utf8)
    do {
        _ = try SecurityKeyPIN(utf8: &bytes)
        throw Failure(description: "\(text.utf8.count) bytes taken, expected \(expected)")
    } catch let failure as SecurityKeyFailure {
        try expectEqual(failure, expected)
    }
    try expect(bytes.allSatisfy { $0 == 0 }, "the refused PIN's bytes are cleared")
}

/// A stand-in that keeps the PIN it was handed, to check it's the one given.
private final class PINKey: PasskeyAuthenticator {
    var handed: SecurityKeyPIN?
    func getAssertion(clientDataHash: Data, credentialID: Data, pin: SecurityKeyPIN?) async throws -> PasskeyAssertion {
        handed = pin
        let authData = testSHA256(Data("kiff.dev".utf8)) + Data([0x05, 0, 0, 0, 1])
        return PasskeyAssertion(authenticatorData: authData, signatureDER: Data("SIG".utf8))
    }
    func makeCredential(clientDataHash: Data, userID: Data, userName: String, pin: SecurityKeyPIN?) async throws -> PasskeyMade {
        PasskeyMade(authenticatorData: Data(), attestationObject: Data())
    }
}

let approvalsSecurityKeyTests: [Test] = [
    Test("libfido2's codes are the key's failures, and a wrong PIN says the tries left") {
        try expectEqual(SecurityKeyFailure.of(0x00), nil)
        try expectEqual(SecurityKeyFailure.of(0x31, triesLeft: 5), .wrongPIN(triesLeft: 5))
        try expectEqual(SecurityKeyFailure.of(0x31), .wrongPIN(triesLeft: nil))
        try expectEqual(SecurityKeyFailure.of(0x31, triesLeft: 0), .pinBlocked)
        try expectEqual(SecurityKeyFailure.of(0x32), .pinBlocked)
        try expectEqual(SecurityKeyFailure.of(0x34), .pinPaused)
        try expectEqual(SecurityKeyFailure.of(0x35), .pinNotSet)
        try expectEqual(SecurityKeyFailure.of(0x2e), .notThisKey)
        try expectEqual(SecurityKeyFailure.of(0x22), .notThisKey)
        try expectEqual(SecurityKeyFailure.of(0x2f), .timedOut)
        try expectEqual(SecurityKeyFailure.of(0x3a), .timedOut)
        try expectEqual(SecurityKeyFailure.of(0x27), .denied)
        try expectEqual(SecurityKeyFailure.of(0x2d), .denied)
        try expectEqual(SecurityKeyFailure.of(-1), .removed)
        try expectEqual(SecurityKeyFailure.of(-2), .removed)
        try expectEqual(SecurityKeyFailure.of(0x2b), .failed(code: 0x2b))
    },
    Test("a PIN is taken from its bytes, which are cleared, and handed over once as a C string") {
        var bytes = Array("1234".utf8)
        let pin = try SecurityKeyPIN(utf8: &bytes)
        try expect(bytes == [0, 0, 0, 0], "the bytes typed are cleared")
        try expectEqual(pin.heldBytesForTests(), Array("1234".utf8))
        let handed = try pin.use { String(cString: $0) }
        try expectEqual(handed, "1234")
        try expect(!pin.isHeld, "released once handed over")
        try expectEqual(pin.heldBytesForTests(), nil)
        do {
            _ = try pin.use { _ in 0 }
            throw Failure(description: "handed over twice")
        } catch let failure as SecurityKeyFailure {
            try expectEqual(failure, .pinUsed)
        }
    },
    Test("a PIN is released even when what it's handed to throws, and when it's let go unused") {
        let thrown = try pin("246810")
        struct Broke: Error {}
        do { _ = try thrown.use { _ in throw Broke() } } catch is Broke {}
        try expect(!thrown.isHeld, "released after a throw")
        let unused = try pin("1357")
        unused.release()
        try expect(!unused.isHeld, "released unused")
    },
    Test("a PIN no key takes is refused, and its bytes cleared: under 4 characters, over 63 bytes, or with a NUL") {
        try refusedPIN("123", .pinTooShort)
        try refusedPIN("", .pinTooShort)
        // Three characters of 4 bytes each: 12 bytes, still 3 characters.
        try refusedPIN("\u{1F511}\u{1F511}\u{1F511}", .pinTooShort)
        try refusedPIN(String(repeating: "7", count: 64), .pinTooLong)
        try refusedPIN("12\u{0}34", .pinTooLong)
        // Four characters of 2 bytes, and 63 bytes: taken.
        try expectEqual(try pin("éééé").heldBytesForTests()?.count, 8)
        try expectEqual(try pin(String(repeating: "7", count: 63)).heldBytesForTests()?.count, 63)
    },
    Test("what's asked of the key is refused before it's asked: a hash that isn't 32 bytes, no credential, or one too long") {
        let hash = Data(repeating: 1, count: 32)
        let ask = try SecurityKeyAssertionAsk(clientDataHash: hash, credentialID: Data([7]))
        try expectEqual(ask.clientDataHash, hash)
        for (h, id) in [(Data(repeating: 1, count: 31), Data([7])), (hash, Data()), (hash, Data(repeating: 7, count: 1024))] {
            do {
                _ = try SecurityKeyAssertionAsk(clientDataHash: h, credentialID: id)
                throw Failure(description: "asked with a \(h.count)-byte hash and a \(id.count)-byte id")
            } catch let refusal as PasskeyRefusal {
                try expectEqual(refusal, .unreadable)
            }
        }
        _ = try SecurityKeyCredentialAsk(clientDataHash: hash, userID: Data(repeating: 2, count: 64), userName: "rae@example.com")
        for id in [Data(), Data(repeating: 2, count: 65)] {
            do {
                _ = try SecurityKeyCredentialAsk(clientDataHash: hash, userID: id, userName: "rae@example.com")
                throw Failure(description: "made with a \(id.count)-byte user id")
            } catch let refusal as PasskeyRefusal {
                try expectEqual(refusal, .unreadable)
            }
        }
        try expectEqual(SecurityKeyCredentialAsk.es256, -7)
        try expectEqual(SecurityKeyCredentialAsk.rpName, "KIFF")
        try expectEqual(SecurityKeyWait.milliseconds, 120_000)
    },
    Test("with the PIN, the uv option is left out (some CTAP2.0 keys refuse both), presence is asked, and the credential isn't discoverable") {
        let assertion = try SecurityKeyAssertionAsk(clientDataHash: Data(repeating: 1, count: 32), credentialID: Data([7]))
        try expectEqual(assertion.userVerification, .omit)
        try expectEqual(assertion.userPresence, .yes)
        let credential = try SecurityKeyCredentialAsk(clientDataHash: Data(repeating: 1, count: 32), userID: Data([2]), userName: "rae@example.com")
        try expectEqual(credential.userVerification, .omit)
        try expectEqual(credential.residentKey, .no)
    },
    Test("authenticator data without the UV flag is still refused, though uv isn't asked for", awaiting: {
        final class NoUV: PasskeyAuthenticator {
            func getAssertion(clientDataHash: Data, credentialID: Data, pin: SecurityKeyPIN?) async throws -> PasskeyAssertion {
                PasskeyAssertion(authenticatorData: testSHA256(Data("kiff.dev".utf8)) + Data([0x01, 0, 0, 0, 1]), signatureDER: Data("SIG".utf8))
            }
            func makeCredential(clientDataHash: Data, userID: Data, userName: String, pin: SecurityKeyPIN?) async throws -> PasskeyMade {
                PasskeyMade(authenticatorData: Data(), attestationObject: Data())
            }
        }
        let approver = PasskeyApprover(authenticator: NoUV(), credentialID: Data("c".utf8), sha256: testSHA256, enabled: true)
        do {
            _ = try await approver.approve(tenant: "t1", method: "POST", path: "/v1/cards", body: Data("{}".utf8), pin: try pin("1234"))
            throw Failure(description: "taken without UV")
        } catch let refusal as PasskeyRefusal {
            try expectEqual(refusal, .notVerified)
        }
    }),
    Test("the attestation object is fmt, attStmt and authData, in CTAP2's canonical order") {
        let authData = Data(repeating: 0xab, count: 37)
        let object = AttestationObject.make(format: "none", statement: Data([0xa0]), authenticatorData: authData)
        var want = Data([0xa3, 0x63]) + Data("fmt".utf8) + Data([0x64]) + Data("none".utf8)
        want += Data([0x67]) + Data("attStmt".utf8) + Data([0xa0])
        want += Data([0x68]) + Data("authData".utf8) + Data([0x58, 37]) + authData
        try expectEqual(object, want)
        try expectEqual(AttestationObject.head(major: 2, count: 23), Data([0x57]))
        try expectEqual(AttestationObject.head(major: 2, count: 300), Data([0x59, 0x01, 0x2c]))
        try expectEqual(AttestationObject.head(major: 2, count: 70_000), Data([0x5a, 0x00, 0x01, 0x11, 0x70]))
    },
    Test("the approver hands the key the PIN it was given", awaiting: {
        let key = PINKey()
        let approver = PasskeyApprover(authenticator: key, credentialID: Data("c".utf8), sha256: testSHA256, enabled: true)
        let given = try pin("1234")
        _ = try await approver.approve(tenant: "t1", method: "POST", path: "/v1/cards", body: Data("{}".utf8), pin: given)
        try expect(key.handed === given, "the same PIN")
    }),
]

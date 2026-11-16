import Foundation

/// Registering this Mac's security key through pairing, with Windows' values (tafs-windows
/// `PairingTests`, `PairingAttemptTests`) and a stand-in for the key.

private let up: UInt8 = 0x01, uv: UInt8 = 0x04, bs: UInt8 = 0x10, at: UInt8 = 0x40

private func bytes(_ hex: String) -> Data {
    var out = Data()
    var i = hex.startIndex
    while i < hex.endIndex { let n = hex.index(i, offsetBy: 2); out.append(UInt8(hex[i..<n], radix: 16)!); i = n }
    return out
}

/// The public keys of private keys 1 and 2 (P-256's generator, and twice it), the vector the phones,
/// Windows and KIFF pin the check code on.
private let g = (x: bytes("6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296"),
                 y: bytes("4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5"))
private let g2 = (x: bytes("7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc47669978"),
                  y: bytes("07775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1"))
private let deviceKey = PasskeyRegistration.spki(x: g.x, y: g.y)
private let keyOnKey = PasskeyRegistration.spki(x: g2.x, y: g2.y)
private let credentialID = Data("the-key-that-goes-with-this-mac".utf8)

/// A new credential's authenticator data: the head, an empty AAGUID, the id, an ES256 COSE key.
private func made(flags: UInt8 = up | uv | at, rp: String = "kiff.dev", x: Data = g2.x, y: Data = g2.y) -> Data {
    var cose = Data([0xa5, 0x01, 0x02, 0x03, 0x26, 0x20, 0x01])
    cose += Data([0x21, 0x58, 32]) + x
    cose += Data([0x22, 0x58, 32]) + y
    return testSHA256(Data(rp.utf8)) + Data([flags, 0, 0, 0, 0]) + Data(repeating: 0, count: 16)
        + Data([UInt8(credentialID.count >> 8), UInt8(credentialID.count & 0xff)]) + credentialID + cose
}

/// The security key's stand-in: answers `authData`, or throws `failure`, and says what it was asked.
private final class NewKey: PasskeyAuthenticator {
    var authData: Data
    var failure: Error?
    var asked: [(hash: Data, userID: Data, name: String)] = []

    init(authData: Data = made(), failure: Error? = nil) { self.authData = authData; self.failure = failure }

    /// A packed statement's start: `{"alg": -7`.
    static let statement: Data = Data([0xa1, 0x63, 0x61, 0x6c, 0x67, 0x26])

    func getAssertion(clientDataHash: Data, credentialID: Data, pin: SecurityKeyPIN?) async throws -> PasskeyAssertion {
        throw Failure(description: "a pairing asks for no assertion")
    }

    func makeCredential(clientDataHash: Data, userID: Data, userName: String, pin: SecurityKeyPIN?) async throws -> PasskeyMade {
        asked.append((clientDataHash, userID, userName))
        pin?.release()
        if let failure { throw failure }
        // The key's own attestation, which this app never sends.
        return PasskeyMade(authenticatorData: authData,
                           attestationObject: AttestationObject.make(format: "packed", statement: Self.statement, authenticatorData: authData))
    }
}

private func pin() throws -> SecurityKeyPIN {
    var typed = Array("2468".utf8)
    return try SecurityKeyPIN(utf8: &typed)
}

private func make(_ key: NewKey, challenge: String = "CHALLENGE", pin given: SecurityKeyPIN? = nil, enabled: Bool = true) async throws -> PairingPasskey {
    try await SecurityKeyPairing.make(challenge: challenge, deviceKeyDER: deviceKey, name: "tafs on this Mac", authenticator: key,
                                      pin: given ?? (try pin()), sha256: testSHA256, isOnCurve: P256Curve.contains, enabled: enabled)
}

private func refused(_ expected: PasskeyRefusal, _ run: () async throws -> Any) async throws {
    do { _ = try await run(); throw Failure(description: "not refused, expected \(expected)") } catch let refusal as PasskeyRefusal {
        try expectEqual(refusal, expected)
    }
}

private func object(_ data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure(description: "not an object") }
    return object
}

let pairingSecurityKeyTests: [Test] = [
    Test("the credential's client data is Windows' bytes: webauthn.create, the challenge, kiff.dev, not cross-origin") {
        try expectEqual(String(decoding: SecurityKeyPairing.clientDataJSON(challenge: "abc_-"), as: UTF8.self),
                        #"{"type":"webauthn.create","challenge":"abc_-","origin":"https://kiff.dev","crossOrigin":false}"#)
    },
    Test("the credential's user id is sha256 of the device key, the same on every attempt") {
        try expectEqual(SecurityKeyPairing.userID(deviceKeyDER: deviceKey, sha256: testSHA256), testSHA256(deviceKey))
    },
    Test("the pairing's challenge holds the nonce and the device key as the QR writes them; without the proof it's random") {
        let pairing = SecurityKeyPairing.challenge(proving: true, nonce: "NONCE", deviceKeyDER: deviceKey, sha256: testSHA256, random: { Data([1]) })
        let message = "kiff.passkey.pair.v1\nNONCE\n" + Encoding.base64URL(deviceKey)
        try expectEqual(pairing, Encoding.base64URL(testSHA256(Data(message.utf8))))
        try expectEqual(SecurityKeyPairing.challenge(proving: false, nonce: "NONCE", deviceKeyDER: deviceKey, sha256: testSHA256,
                                                     random: { Data(repeating: 0xff, count: 32) }),
                        Encoding.base64URL(Data(repeating: 0xff, count: 32)))
    },
    Test("switched off, the key isn't asked, and the PIN is cleared", awaiting: {
        let key = NewKey()
        let given = try pin()
        try await refused(.off) { try await make(key, pin: given, enabled: false) }
        try expectEqual(key.asked.count, 0)
        try expect(!given.isHeld, "the PIN is let go")
    }),
    Test("the key is given the client data's hash, the user id and this Mac's name, and its credential is read for the QR", awaiting: {
        let key = NewKey()
        let got = try await make(key, challenge: "CH")
        let clientData = SecurityKeyPairing.clientDataJSON(challenge: "CH")
        try expectEqual(key.asked.count, 1)
        try expectEqual(key.asked[0].hash, testSHA256(clientData))
        try expectEqual(key.asked[0].userID, testSHA256(deviceKey))
        try expectEqual(key.asked[0].name, "tafs on this Mac")
        try expectEqual(got.passkey, NewPasskey(credentialID: credentialID, publicKeyDER: keyOnKey))
        try expectEqual(got.credential, PairingPayload.Credential(id: Encoding.base64URL(credentialID), publicKey: Encoding.base64URL(keyOnKey)))
        try expectEqual(got.proof?.clientDataJSON, clientData)
        try expectEqual(got.proof.flatMap(SecurityKeyPairing.proofChallenge), "CH")
    }),
    Test("the attestation sent is none: the key's own statement and certificate never leave this Mac", awaiting: {
        let got = try await make(NewKey())
        guard let attestation = got.proof?.attestationObject else { throw Failure(description: "no proof") }
        try expectEqual(attestation, AttestationObject.make(format: "none", statement: Data([0xa0]), authenticatorData: made()))
        var head: [UInt8] = [0xa3, 0x63]
        head += Array("fmt".utf8)
        head.append(0x64)
        head += Array("none".utf8)
        head.append(0x67)
        head += Array("att".utf8)
        try expectEqual(Array(attestation.prefix(head.count)), head)
        try expect(!attestation.contains(Data("packed".utf8)), "not the key's own format")
    }),
    Test("a credential is refused when it couldn't approve: no verification, synced, another RP, or the device key itself", awaiting: {
        try await refused(.notVerified) { try await make(NewKey(authData: made(flags: up | at))) }
        try await refused(.canLeave) { try await make(NewKey(authData: made(flags: up | uv | bs | at))) }
        try await refused(.notKIFF) { try await make(NewKey(authData: made(rp: "evil.example"))) }
        try await refused(.notES256) { try await make(NewKey(authData: made(y: g.y))) }
        try await refused(.unreadable) { try await make(NewKey(authData: made(x: g.x, y: g.y))) }
    }),
    Test("a key's failure reaches the caller as it is: a wrong PIN, or no key", awaiting: {
        do { _ = try await make(NewKey(failure: SecurityKeyFailure.wrongPIN(triesLeft: 5))); throw Failure(description: "not thrown") }
        catch let failure as SecurityKeyFailure { try expectEqual(failure, .wrongPIN(triesLeft: 5)) }
        do { _ = try await make(NewKey(failure: SecurityKeyFailure.noKey)); throw Failure(description: "not thrown") }
        catch let failure as SecurityKeyFailure { try expectEqual(failure, .noKey) }
    }),
    Test("without the proof, a new code keeps the last credential and asks the key nothing", awaiting: {
        let kept = try await make(NewKey())
        var asked = 0
        let got = try await SecurityKeyPairing.credential(kept: kept, proving: false, nonce: "N", deviceKeyDER: deviceKey,
                                                          make: { _ in asked += 1; return kept }, sha256: testSHA256, random: { Data([1]) })
        try expectEqual(got, kept)
        try expectEqual(asked, 0)
    }),
    Test("with the proof, each attempt makes it again with the pairing's challenge, and one made for another is refused", awaiting: {
        let key = NewKey()
        let kept = try await make(key)
        let pairing = PasskeyRegistration.pairingChallenge(nonce: "N", deviceKeyDER: deviceKey, sha256: testSHA256)
        var challenges: [String] = []
        let got = try await SecurityKeyPairing.credential(kept: kept, proving: true, nonce: "N", deviceKeyDER: deviceKey,
                                                          make: { challenges.append($0); return try await make(key, challenge: $0) },
                                                          sha256: testSHA256, random: { Data([1]) })
        try expectEqual(challenges, [pairing])
        try expectEqual(got.flatMap { $0.proof }.flatMap(SecurityKeyPairing.proofChallenge), pairing)
        try await refused(.unreadable) {
            try await SecurityKeyPairing.credential(kept: nil, proving: true, nonce: "N", deviceKeyDER: deviceKey,
                                                    make: { _ in try await make(key, challenge: "ANOTHER") }, sha256: testSHA256, random: { Data([1]) }) as Any
        }
    }),
    Test("a refused credential, or a key not touched or declined, pairs without one; a wrong PIN doesn't", awaiting: {
        let failures: [Error] = [PasskeyRefusal.notVerified, PasskeyRefusal.off, SecurityKeyFailure.timedOut, SecurityKeyFailure.denied]
        for failure in failures {
            let got = try await SecurityKeyPairing.credential(kept: nil, proving: false, nonce: "N", deviceKeyDER: deviceKey,
                                                              make: { _ in throw failure }, sha256: testSHA256, random: { Data([1]) })
            try expectEqual(got, nil)
        }
        do {
            _ = try await SecurityKeyPairing.credential(kept: nil, proving: false, nonce: "N", deviceKeyDER: deviceKey,
                                                        make: { _ in throw SecurityKeyFailure.wrongPIN(triesLeft: 2) }, sha256: testSHA256, random: { Data([1]) })
            throw Failure(description: "not thrown")
        } catch let failure as SecurityKeyFailure { try expectEqual(failure, .wrongPIN(triesLeft: 2)) }
    }),
    Test("the QR names the credential as {id, public_key}, only with passkey, never with a software key or an approval key") {
        let credential = PairingPayload.Credential(id: "SUQ", publicKey: Encoding.base64URL(keyOnKey))
        let payload = PairingPayload(deviceKey: deviceKey, keyStore: "enclave", approvalKey: nil, name: "A Mac", nonce: "N", exp: "E",
                                     credential: credential)
        try expectEqual(payload.kind, .passkey)
        try expectEqual(payload.credential, credential)
        let qr = try object(Data(try payload.text().utf8))
        try expectEqual(qr["credential"] as? [String: String], ["id": "SUQ", "public_key": Encoding.base64URL(keyOnKey)])
        try expectEqual(qr["approval_pub"] == nil, true)
        let software = PairingPayload(deviceKey: deviceKey, keyStore: "software", approvalKey: nil, name: "A Mac", nonce: "N", exp: "E",
                                      credential: credential)
        try expectEqual(software.credential, nil)
        try expectEqual(software.keyStore, "software")
        let enclave = PairingPayload(deviceKey: deviceKey, keyStore: "enclave", approvalKey: keyOnKey, name: "A Mac", nonce: "N", exp: "E",
                                     credential: credential)
        try expectEqual(enclave.credential, nil)
        try expectEqual(enclave.kind, .enclave)
        let none = PairingPayload(deviceKey: deviceKey, keyStore: "enclave", approvalKey: nil, name: "A Mac", nonce: "N", exp: "E")
        try expect(!(try none.text()).contains("credential"), "no credential, no field")
    },
    Test("the check code covers the credential's key in the approval key's place: the phones' vector") {
        func code(_ payload: PairingPayload) -> String {
            String(Encoding.base32(testSHA256(deviceKey + (payload.checkedKeyDER ?? Data()))).prefix(6))
        }
        try expect(P256Curve.contains(g2.x, g2.y), "twice the generator is on the curve")
        let credential = PairingPayload.Credential(id: "SUQ", publicKey: Encoding.base64URL(keyOnKey))
        let withKey = PairingPayload(deviceKey: deviceKey, keyStore: "enclave", approvalKey: nil, name: "A Mac", nonce: "N", exp: "E", credential: credential)
        let withApproval = PairingPayload(deviceKey: deviceKey, keyStore: "enclave", approvalKey: keyOnKey, name: "A Mac", nonce: "N", exp: "E")
        let alone = PairingPayload(deviceKey: deviceKey, keyStore: "enclave", approvalKey: nil, name: "A Mac", nonce: "N", exp: "E")
        try expectEqual(withKey.checkedKeyDER, keyOnKey)
        try expectEqual(code(withKey), "H6SJNU")
        try expectEqual(code(withApproval), "H6SJNU")
        try expectEqual(code(alone), "LTJFF6")
    },
    Test("with a proof, the claim carries credential_proof, each part base64url; without one, it has no such field", awaiting: {
        let paired = #"{"access_token":"tok","token_type":"Bearer","expires_in":1,"tenant":"t1","subject":"u1","device_id":"dev_1"}"#
        let transport = CannedTransport([(200, paired), (200, paired)])
        let proof = CredentialProof(clientDataJSON: Data("{}".utf8), attestationObject: Data([0xa3, 0xff]))
        _ = try await KIFFClient(transport: transport).claimPairing(nonce: "n", publicKey: "PUB", proof: "PROOF", credentialProof: proof)
        let sent = try object(transport.sent[0].body)
        try expectEqual(sent["nonce"] as? String, "n")
        try expectEqual(sent["pub"] as? String, "PUB")
        try expectEqual(sent["proof"] as? String, "PROOF")
        try expectEqual(sent["credential_proof"] as? [String: String], ["client_data_json": "e30", "attestation_object": "o_8"])
        _ = try await KIFFClient(transport: transport).claimPairing(nonce: "n", publicKey: "PUB", proof: "PROOF")
        try expectEqual(String(decoding: transport.sent[1].body, as: UTF8.self), #"{"nonce":"n","proof":"PROOF","pub":"PUB"}"#)
    }),
]

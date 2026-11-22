import Foundation

/// The passkey approval, checked the way the public spec (`docs/secure-connection.md`) says KIFF
/// checks it, with Windows' values (tafs-windows `PasskeyApprovalTests`, `PasskeyPairContractTests`,
/// `PasskeyRegistrationTests`). An authenticator stand-in returns what a security key would.

private let up: UInt8 = 0x01, uv: UInt8 = 0x04, be: UInt8 = 0x08, bs: UInt8 = 0x10, at: UInt8 = 0x40
private let credential = Data("this-computer-credential".utf8)

/// A security key's stand-in: its authenticator data for an RP, the flags given, and a fixed
/// "signature" (the Mac test checks a real one).
private final class FakeKey: PasskeyAuthenticator {
    let flags: UInt8
    let rp: String
    var usedCredential: Data?
    var asked: [Data] = []

    init(flags: UInt8 = up | uv, rp: String = "kiff.dev", usedCredential: Data? = nil) {
        self.flags = flags
        self.rp = rp
        self.usedCredential = usedCredential
    }

    func getAssertion(clientDataHash: Data, credentialID: Data, pin: SecurityKeyPIN?) async throws -> PasskeyAssertion {
        asked.append(clientDataHash)
        let authData = testSHA256(Data(rp.utf8)) + Data([flags, 0, 0, 0, 7])
        return PasskeyAssertion(authenticatorData: authData, signatureDER: Data("SIG".utf8), credentialID: usedCredential)
    }

    func makeCredential(clientDataHash: Data, userID: Data, userName: String, pin: SecurityKeyPIN?) async throws -> PasskeyMade {
        PasskeyMade(authenticatorData: Data(), attestationObject: Data())
    }
}

/// An approver switched on for the test: approvals are off by default (`Features.macPasskeyApprovals`).
private func approver(_ key: FakeKey, enabled: Bool = true) -> PasskeyApprover {
    PasskeyApprover(authenticator: key, credentialID: credential, sha256: testSHA256, enabled: enabled)
}

/// What a new credential's authenticator data holds: the head, an empty AAGUID, the id, then an
/// ES256 COSE key (a map of five: kty 2, alg -7, crv 1, x, y), each as given.
private func made(flags: UInt8 = up | uv | at, rp: String = "kiff.dev", id: Data = credential,
                  alg: UInt8 = 0x26, crv: UInt8 = 0x01, x: Data = Data(repeating: 1, count: 32), y: Data = Data(repeating: 2, count: 32)) -> Data {
    var cose = Data([0xa5, 0x01, 0x02, 0x03, alg, 0x20, crv])
    cose += Data([0x21, 0x58, UInt8(x.count)]) + x
    cose += Data([0x22, 0x58, UInt8(y.count)]) + y
    return testSHA256(Data(rp.utf8)) + Data([flags, 0, 0, 0, 0]) + Data(repeating: 0, count: 16)
        + Data([UInt8(id.count >> 8), UInt8(id.count & 0xff)]) + id + cose
}

private func refused(_ expected: PasskeyRefusal, _ run: () async throws -> Any) async throws {
    do { _ = try await run(); throw Failure(description: "not refused, expected \(expected)") } catch let refusal as PasskeyRefusal {
        try expectEqual(refusal, expected)
    }
}

let approvalsPasskeyTests: [Test] = [
    Test("a point is on P-256 only by the curve's equation, with both coordinates below p") {
        func bytes(_ hex: String) -> Data {
            var out = Data()
            var i = hex.startIndex
            while i < hex.endIndex { let n = hex.index(i, offsetBy: 2); out.append(UInt8(hex[i..<n], radix: 16)!); i = n }
            return out
        }
        // NIST's generator, and RFC 6979 A.2.5's public key: both on the curve.
        let gx = bytes("6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296")
        let gy = bytes("4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5")
        try expect(P256Curve.contains(gx, gy), "the generator")
        try expect(P256Curve.contains(bytes("60fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb6"),
                                      bytes("7903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299")), "RFC 6979's key")
        // The generator's y with its low bit flipped: off the curve.
        var flipped = gy
        flipped[31] ^= 1
        try expect(!P256Curve.contains(gx, flipped), "a flipped bit")
        // A coordinate of p or more, the point at zero, and a short coordinate: refused.
        let p = bytes("ffffffff00000001000000000000000000000000ffffffffffffffffffffffff")
        try expect(!P256Curve.contains(p, gy), "x = p")
        try expect(!P256Curve.contains(gx, p), "y = p")
        try expect(!P256Curve.contains(Data(count: 32), Data(count: 32)), "zero")
        try expect(!P256Curve.contains(gx.dropLast(), gy), "short")
    },
    Test("the tests' SHA-256 is FIPS 180-4's") {
        try expectEqual(Encoding.hex(testSHA256(Data("abc".utf8))), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        try expectEqual(Encoding.hex(testSHA256(Data())), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    },
    Test("an approval is KIFF's kiff.request.v1 under clientDataJSON in Windows' bytes, and the key gets its hash", awaiting: {
        let key = FakeKey()
        let body = Data(#"{"card":"c1"}"#.utf8)
        let header = try await approver(key).approve(tenant: "t1", method: "POST", path: "/v1/cards", body: body, signedAt: "2026-11-14T20:00:00Z")
        let message = "kiff.request.v1\nt1\nPOST\n/v1/cards\n\(Encoding.hex(testSHA256(body)))\n2026-11-14T20:00:00Z"
        let challenge = Encoding.base64URL(testSHA256(Data(message.utf8)))
        // The literal, so this can't drift with its own construction.
        try expectEqual(challenge, "mF0bsTI8LEyXFt2V4qAUPBNkqSoAFmqqWdFy5VdjMcA")
        let client = #"{"type":"webauthn.get","challenge":"\#(challenge)","origin":"https://kiff.dev","crossOrigin":false}"#
        try expectEqual(PasskeyApprover.clientDataJSON(Data(message.utf8), sha256: testSHA256), Data(client.utf8))
        // CTAP2 takes the hash of the JSON this app built, never the JSON.
        try expectEqual(key.asked, [testSHA256(Data(client.utf8))])
        // The header, field by field, as KIFF reads it.
        try expect(header.hasPrefix("t=2026-11-14T20:00:00Z,a="), "t= first, then a=")
        guard let a = Encoding.fromBase64URL(String(header.dropFirst("t=2026-11-14T20:00:00Z,a=".count))),
              let fields = try JSONSerialization.jsonObject(with: a) as? [String: String] else { throw Failure(description: "no a=") }
        try expectEqual(Set(fields.keys), ["credential_id", "client_data_json", "authenticator_data", "signature"])
        try expectEqual(fields["credential_id"].flatMap(Encoding.fromBase64URL), credential)
        try expectEqual(fields["client_data_json"].flatMap(Encoding.fromBase64URL), Data(client.utf8))
        try expectEqual(fields["authenticator_data"].flatMap(Encoding.fromBase64URL), testSHA256(Data("kiff.dev".utf8)) + Data([up | uv, 0, 0, 0, 7]))
        try expectEqual(fields["signature"].flatMap(Encoding.fromBase64URL), Data("SIG".utf8))
        // Windows' order, so the bytes match too.
        try expect(String(decoding: a, as: UTF8.self).hasPrefix(#"{"credential_id":"#), "Windows' field order")
    }),
    Test("the challenge binds one request: another time or another body is another challenge", awaiting: {
        let key = FakeKey()
        let body = Data(#"{"card":"c1"}"#.utf8)
        _ = try await approver(key).approve(tenant: "t1", method: "POST", path: "/v1/cards", body: body, signedAt: "2026-11-14T20:00:00Z")
        _ = try await approver(key).approve(tenant: "t1", method: "POST", path: "/v1/cards", body: body, signedAt: "2026-11-14T20:00:01Z")
        _ = try await approver(key).approve(tenant: "t1", method: "POST", path: "/v1/cards", body: Data("{}".utf8), signedAt: "2026-11-14T20:00:00Z")
        try expectEqual(Set(key.asked).count, 3)
    }),
    Test("a signing time is never the same twice, in milliseconds, when none is given", awaiting: {
        let key = FakeKey()
        let one = try await approver(key).approve(tenant: "t1", method: "POST", path: "/v1/x", body: Data())
        let two = try await approver(key).approve(tenant: "t1", method: "POST", path: "/v1/x", body: Data())
        let time = { (h: String) in String(h.dropFirst(2).prefix { $0 != "," }) }
        try expect(time(one) != time(two), "two times")
        try expect(time(one).contains("."), "milliseconds")
    }),
    Test("what KIFF would refuse is never sent: no presence, no verification, a key that can leave, another RP or credential", awaiting: {
        let send = { (key: FakeKey) in try await approver(key).approve(tenant: "t1", method: "POST", path: "/v1/cards", body: Data(), signedAt: "t") }
        try await refused(.notVerified) { try await send(FakeKey(flags: up)) }
        try await refused(.notVerified) { try await send(FakeKey(flags: uv)) }
        try await refused(.canLeave) { try await send(FakeKey(flags: up | uv | be)) }
        try await refused(.canLeave) { try await send(FakeKey(flags: up | uv | bs)) }
        try await refused(.notKIFF) { try await send(FakeKey(rp: "evil.example")) }
        try await refused(.otherCredential) { try await send(FakeKey(usedCredential: Data("another".utf8))) }
        // The credential asked for, named back, is fine.
        _ = try await send(FakeKey(usedCredential: credential))
        try await refused(.unreadable) { try AuthenticatorData(Data(repeating: 0, count: 36)) }
    }),
    Test("the pair is KIFF's kiff.requests.v1, sorted, under one assertion, each header with the other's hash (Windows' contract)", awaiting: {
        let tenant = "01exampletenant0000000000", signedAt = "2026-11-12T18:00:00.250Z"
        // The tools batch goes to the gateway's path, as Start sends it.
        let connect = RequestsTogether.Request(method: "POST", path: "/v1/connections/batch", body: Data(#"{"tools":[{"name":"tafs_state"}]}"#.utf8))
        let draft = RequestsTogether.Request(method: "POST", path: "/v1/me/agent-drafts", body: Data(#"{"agent_id":"coach","label":"Coach"}"#.utf8))
        let key = FakeKey()
        let (batch, cards) = try await RequestsTogether.approve(approver(key), tenant: tenant, connect, draft, signedAt: signedAt)
        try expectEqual(key.asked.count, 1)
        func own(_ r: RequestsTogether.Request) -> String {
            let message = ["kiff.request.v1", tenant, r.method, r.path, Encoding.hex(testSHA256(r.body)), signedAt].joined(separator: "\n")
            return Encoding.hex(testSHA256(Data(message.utf8)))
        }
        for (header, mine, other) in [(batch, own(connect), own(draft)), (cards, own(draft), own(connect))] {
            let parts = header.split(separator: ",").map(String.init)
            try expectEqual(parts.count, 3)
            try expectEqual(parts[0], "t=\(signedAt)")
            try expect(parts[1].hasPrefix("a=") && !parts[1].dropFirst(2).contains("="), "a= then the assertion, unpadded")
            try expectEqual(parts[2], "with=sha256:\(other)")
            try expect(mine != other, "never its own hash")
            let lo = min(mine, other), hi = max(mine, other)
            let message = "kiff.requests.v1\n\(tenant)\n\(signedAt)\n\(lo)\n\(hi)"
            guard let a = Encoding.fromBase64URL(String(parts[1].dropFirst(2))),
                  let fields = try JSONSerialization.jsonObject(with: a) as? [String: String],
                  let client = fields["client_data_json"].flatMap(Encoding.fromBase64URL),
                  let clientFields = try JSONSerialization.jsonObject(with: client) as? [String: Any] else { throw Failure(description: "no assertion") }
            try expectEqual(clientFields["challenge"] as? String, Encoding.base64URL(testSHA256(Data(message.utf8))))
        }
        try expectEqual(batch.split(separator: ",")[1], cards.split(separator: ",")[1])
        // The literals: each header names the other's request hash, and the one challenge.
        try expect(batch.hasSuffix(",with=sha256:3cc16020d315b4eb9a8afac14484dd7047044a4c5385e74c065e6dde0d23deff"), "the draft's hash")
        try expect(cards.hasSuffix(",with=sha256:644f3b501cf306af2c63c032848fd13d2056bdd8ef04cafe891f9c718041efad"), "the batch's hash")
        try expectEqual(key.asked, [testSHA256(PasskeyApprover.clientDataJSON(RequestsTogether.message(tenant: tenant, signedAt: signedAt,
            "644f3b501cf306af2c63c032848fd13d2056bdd8ef04cafe891f9c718041efad", "3cc16020d315b4eb9a8afac14484dd7047044a4c5385e74c065e6dde0d23deff"), sha256: testSHA256))])
        try expectEqual(PasskeyApprover.challenge(RequestsTogether.message(tenant: tenant, signedAt: signedAt,
            "644f3b501cf306af2c63c032848fd13d2056bdd8ef04cafe891f9c718041efad", "3cc16020d315b4eb9a8afac14484dd7047044a4c5385e74c065e6dde0d23deff"), sha256: testSHA256),
            "7UWb8NtnHMqAVlenob3dXQXSWSVUwZC3NoYVsDtim2A")
    }),
    Test("one act on the security key alone: one fresh assertion over its own request, sent with only the passkey header (kiff/cloud#96)", awaiting: {
        let key = FakeKey(usedCredential: credential)
        let transport = CannedTransport([(204, ""), (403, #"{"error":"passkey_required"}"#)])
        let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1", approvalMode: "passkey")
        let passkey = PasskeySession(transport: transport, session: session, language: "fr", approver: approver(key))
        let act = KeyAct.signOutDevice(id: "dev/2")
        try expectEqual(act.method + " " + act.path, "DELETE /v1/me/devices/dev%2F2")
        _ = try await passkey.approved(method: act.method, path: act.path, body: act.body, pin: nil)
        let sent = transport.sent[0]
        try expectEqual(sent.method + " " + sent.path, "DELETE /v1/me/devices/dev%2F2")
        try expectEqual(sent.body, Data())
        try expectEqual(sent.headers["Authorization"], "Bearer tok")
        try expect(sent.headers[Passkeys.headerName]?.hasPrefix("t=") == true, "the assertion")
        try expect(sent.headers[Passkeys.headerName]?.contains("with=") == false, "one request, never a pair")
        try expectEqual(sent.headers["KIFF-Device-Signature"], nil)
        try expectEqual(sent.headers["Content-Type"], nil)
        try expectEqual(key.asked.count, 1)
        // A second act asks the key again: never a window, never a kept assertion. KIFF's refusal is its own.
        do { _ = try await passkey.approved(method: act.method, path: act.path, body: act.body, pin: nil); throw Failure(description: "taken") }
        catch KIFFError.refused(status: 403, code: let code) { try expectEqual(code, "passkey_required") }
        try expectEqual(key.asked.count, 2)
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        try expectEqual(act.title(words, device: "MacBook"), "Sign MacBook out of your account")
    }),
    Test("switched off, nothing is asked of the security key: one request or the pair; on by default since kiff/cloud#96", awaiting: {
        try expectEqual(Features.macPasskeyApprovals, true)
        let key = FakeKey()
        let off = PasskeyApprover(authenticator: key, credentialID: credential, sha256: testSHA256, enabled: false)
        try await refused(.off) { try await off.approve(tenant: "t1", method: "POST", path: "/v1/cards", body: Data(), signedAt: "t") }
        let pair = RequestsTogether.Request(method: "POST", path: "/v1/x", body: Data())
        try await refused(.off) { try await RequestsTogether.approve(off, tenant: "t1", pair, pair, signedAt: "t") }
        try expectEqual(key.asked, [])
    }),
    Test("the pair's message is KIFF's, sorted however the hashes come") {
        let lo = String(repeating: "a", count: 64), hi = String(repeating: "b", count: 64)
        let expected = "kiff.requests.v1\n01exampletenant0000000000\n2026-11-12T18:00:00.250Z\n\(lo)\n\(hi)"
        try expectEqual(String(decoding: RequestsTogether.message(tenant: "01exampletenant0000000000", signedAt: "2026-11-12T18:00:00.250Z", hi, lo), as: UTF8.self), expected)
        try expectEqual(String(decoding: RequestsTogether.message(tenant: "01exampletenant0000000000", signedAt: "2026-11-12T18:00:00.250Z", lo, hi), as: UTF8.self), expected)
    },
    Test("a new credential reads as its id and its P-256 key, SPKI DER, as KIFF registers it") {
        let x = Data(repeating: 1, count: 32), y = Data(repeating: 2, count: 32)
        let key = try PasskeyRegistration.read(made(x: x, y: y), sha256: testSHA256, isOnCurve: { _, _ in true })
        try expectEqual(key.credentialID, credential)
        try expectEqual(Encoding.hex(key.publicKeyDER), "3059301306072a8648ce3d020106082a8648ce3d030107034200" + "04" + Encoding.hex(x) + Encoding.hex(y))
    },
    Test("a new credential that couldn't approve for this Mac is refused: another algorithm or curve, off the curve, another RP, BE or BS, no verification", awaiting: {
        let read = { (data: Data, onCurve: Bool) in try PasskeyRegistration.read(data, sha256: testSHA256, isOnCurve: { _, _ in onCurve }) }
        try await refused(.notES256) { try read(made(alg: 0x27), true) }     // EdDSA (-8)
        try await refused(.notES256) { try read(made(crv: 0x02), true) }     // P-384
        try await refused(.notES256) { try read(made(x: Data(repeating: 1, count: 31)), true) }
        try await refused(.notES256) { try read(made(), false) }             // off the curve
        try await refused(.notKIFF) { try read(made(rp: "evil.example"), true) }
        try await refused(.canLeave) { try read(made(flags: up | uv | at | be), true) }
        try await refused(.canLeave) { try read(made(flags: up | uv | at | bs), true) }
        try await refused(.notVerified) { try read(made(flags: up | at), true) }
        try await refused(.unreadable) { try read(made(flags: up | uv), true) }   // no credential data
        try await refused(.unreadable) { try read(made(id: Data()), true) }
        // A COSE key that names a label twice is refused, never the last one taken.
        var twice = made()
        twice.append(contentsOf: [0x01, 0x02])
        let headAt = twice.count - 2 - (7 + 35 + 35)
        twice[headAt] = 0xa6
        try await refused(.notES256) { try read(twice, true) }
    }),
    Test("a pairing's passkey is made over KIFF's kiff.passkey.pair.v1 challenge, as Windows' PasskeyChallenge") {
        let pub = Data([0x30, 0x59, 0x01, 0x02])
        let expected = Encoding.base64URL(testSHA256(Data("kiff.passkey.pair.v1\nn0nce\n\(Encoding.base64URL(pub))".utf8)))
        try expectEqual(PasskeyRegistration.pairingChallenge(nonce: "n0nce", deviceKeyDER: pub, sha256: testSHA256), expected)
    },
    Test("the passkey route is its own, and nothing gives it yet: a passkey Mac still approves on the phone") {
        try expect(ApprovalRoute.passkey != .touchID && ApprovalRoute.passkey != .phoneOrPasskey, "its own route")
        try expectEqual(ApprovalRoute.of(.passkey), .phoneOrPasskey)
    },
]

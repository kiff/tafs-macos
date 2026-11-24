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

/// One held call, as KIFF lists it.
private func heldCall(_ json: String) throws -> HeldCall { try AccountClient.decoder.decode(HeldCall.self, from: Data(json.utf8)) }

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
    Test("sharing a taf on the key: one act a change, the iPad's requests (POST the share, DELETE with its query and {}), named Share {taf}") {
        let toGroup = KeyAct.share(agent: "agent 1", Shares.Share(group: "grp_1"))
        try expectEqual(toGroup.method + " " + toGroup.path, "POST /v1/agents/agent%201/grants")
        try expectEqual(String(decoding: toGroup.body, as: UTF8.self), #"{"group":"grp_1"}"#)
        let toPerson = KeyAct.share(agent: "a1", Shares.Share(subject: "u|7"))
        try expectEqual(String(decoding: toPerson.body, as: UTF8.self), #"{"subject":"u|7"}"#)
        let stop = KeyAct.unshare(agent: "a1", Shares.Share(subject: "ana@acme.com"))
        try expectEqual(stop.method + " " + stop.path, "DELETE /v1/agents/a1/grants?subject=ana%40acme.com")
        try expectEqual(String(decoding: stop.body, as: UTF8.self), "{}")
        try expectEqual(KeyAct.unshare(agent: "a1", Shares.Share(group: "g&1")).path, "/v1/agents/a1/grants?group=g%261")
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        try expectEqual(toGroup.title(words, device: "Refunds"), "Share Refunds")
        // Added first, groups before people, then the ones stopped: one approval each.
        let changes = Shares.changes(agent: "a1", had: [Shares.Share(group: "old"), Shares.Share(subject: "u2")],
                                     chosen: [Shares.Share(subject: "u2"), Shares.Share(subject: "u9"), Shares.Share(group: "new")])
        try expectEqual(changes, [.share(agent: "a1", Shares.Share(group: "new")), .share(agent: "a1", Shares.Share(subject: "u9")),
                                  .unshare(agent: "a1", Shares.Share(group: "old"))])
        try expectEqual(Shares.changes(agent: "a1", had: [Shares.Share(group: "g")], chosen: [Shares.Share(group: "g")]), [])
    },
    Test("adding someone to a group, or changing their role, is the key's (group changes step B): the iPad's PUT and {\"role\"}, named as Touch ID's line; taking someone out isn't") {
        let add = KeyAct.setMember(group: "g/1", subject: "u|2", role: "member")
        try expectEqual(add.method + " " + add.path, "PUT /v1/groups/g%2F1/members/u%7C2")
        try expectEqual(String(decoding: add.body, as: UTF8.self), #"{"role":"member"}"#)
        // The same request the device-key route sent, byte for byte.
        let same = PeopleChange.setMember(group: "g/1", subject: "u|2", role: "member")
        try expectEqual(add.path, same.path)
        try expectEqual(add.body, same.body)
        try expectEqual(String(decoding: KeyAct.setMember(group: "g1", subject: "u2", role: "manager").body, as: UTF8.self), #"{"role":"manager"}"#)
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        try expectEqual(add.title(words, device: "Add Ana to Support"), "Add Ana to Support")
        // People: a member change goes to the key, or to the phone without one; never Touch ID and the device key.
        let people = try String(contentsOf: URL(fileURLWithPath: "Sources/App/account/PeopleView.swift"), encoding: .utf8)
        try expect(people.contains("if case .setMember(let group, let subject, let role) = change {\n            return await setMember(KeyAct.setMember("),
                   "a member change is the key's, before Touch ID's route")
        try expect(people.contains("guard let approveWithKey else {\n            problem = Words.app(ConnectionEnding.phoneLine)"), "no key: the phone")
        let window = try String(contentsOf: URL(fileURLWithPath: "Sources/App/shell/SignedInView.swift"), encoding: .utf8)
        try expect(window.contains("people.approveWithKey = approveWithKey"), "the window hands People the key")
    },
    Test("Resume on the key: KIFF's agent or the whole account, with {}, named as the iPad's reason; tafs cloud's release is a DELETE", awaiting: {
        let one = KeyAct.resume(agent: "agent_1"), all = KeyAct.resume(agent: nil)
        try expectEqual(one.method + " " + one.path, "POST /v1/agents/agent_1/resume")
        try expectEqual(all.method + " " + all.path, "POST /v1/resume")
        try expectEqual(String(decoding: one.body, as: UTF8.self), "{}")
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        try expectEqual(one.title(words, device: "Refunds"), "Resume Refunds")
        try expectEqual(all.title(words), "Resume all your tafs")
        let transport = CannedTransport([(200, #"{"halt":{"state":"running"}}"#)])
        let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
        _ = try? await CloudClient(transport: transport, session: session).releaseHalt("taf-1")
        try expectEqual(transport.sent.first.map { $0.method + " " + $0.path }, "DELETE /v1/tafs/taf-1/halt")
        try expectEqual(transport.sent.first?.headers["Authorization"], "Bearer tok")
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
    Test("Approve once on the key: one assertion over the answer's kiff.answer.v1, sent in signature.passkey beside its signed_at", awaiting: {
        let key = FakeKey()
        let transport = CannedTransport([(200, "{}")])
        let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")
        let passkey = PasskeySession(transport: transport, session: session, approver: approver(key))
        let call = try heldCall(#"{"id":"exc/1","subject":"a","action":"b","created_at":"2026-11-14T18:00:00Z","title":"Refund","accounting_version":3}"#)
        let now = Date(timeIntervalSince1970: 1_794_679_800)
        try await passkey.approveOnce(call, pin: nil, now: now)
        let signedAt = KIFFMessage.time(now)
        // The key was asked once, over the clientDataJSON whose challenge is the answer message's hash.
        let message = "kiff.answer.v1\nt1\nexc/1\napprove-once\n\n\n3\n" + signedAt
        try expectEqual(key.asked, [testSHA256(PasskeyApprover.clientDataJSON(Data(message.utf8), sha256: testSHA256))])
        try expectEqual(transport.sent.count, 1)
        let sent = transport.sent[0]
        try expectEqual(sent.method + " " + sent.path, "POST /v1/me/card-exceptions/exc%2F1/approve-once")
        try expectEqual(sent.headers["Authorization"], "Bearer tok")
        // No header assertion and no device key's signature: the answer's body carries the key's approval.
        try expectEqual(sent.headers[Passkeys.headerName], nil)
        struct Body: Decodable {
            struct Signature: Decodable {
                struct Passkey: Decodable { let credential_id: String; let client_data_json: String; let authenticator_data: String; let signature: String }
                let signed_at: String
                let passkey: Passkey
                let value: String?
            }
            let signature: Signature
        }
        let body = try JSONDecoder().decode(Body.self, from: sent.body)
        try expectEqual(body.signature.signed_at, signedAt)
        try expectEqual(body.signature.value, nil)
        try expectEqual(body.signature.passkey.credential_id, Encoding.base64URL(credential))
        try expectEqual(body.signature.passkey.client_data_json, Encoding.base64URL(PasskeyApprover.clientDataJSON(Data(message.utf8), sha256: testSHA256)))
        try expectEqual(body.signature.passkey.signature, Encoding.base64URL(Data("SIG".utf8)))
    }),
    Test("Approve once asks nothing of the key for a hold KIFF can't approve once, one without its version, or a refusal", awaiting: {
        let key = FakeKey()
        let transport = CannedTransport([])
        let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")
        let passkey = PasskeySession(transport: transport, session: session, approver: approver(key))
        let cannot = try heldCall(#"{"id":"e1","subject":"a","action":"b","created_at":"2026-11-14T18:00:00Z","title":"T","accounting_version":3,"can_approve_once":false}"#)
        let unversioned = try heldCall(#"{"id":"e2","subject":"a","action":"b","created_at":"2026-11-14T18:00:00Z","title":"T"}"#)
        for call in [cannot, unversioned] {
            do { try await passkey.approveOnce(call, pin: nil); throw Failure(description: "\(call.id) was sent") } catch is KIFFError {}
        }
        // A fill in Chrome, however it's reached: neither Approve once nor Extra room asks the key.
        let fill = try heldCall(#"{"id":"e3","subject":"a","action":"b","created_at":"2026-11-14T18:00:00Z","title":"T","accounting_version":3,"browser":{"sealed_fill":{"sealed":"h"}}}"#)
        do { try await passkey.approveOnce(fill, pin: nil); throw Failure(description: "the fill was sent") } catch is ApproveOnPhone {}
        do { try await passkey.extraRoom(fill, pin: nil); throw Failure(description: "the fill was sent") } catch is ApproveOnPhone {}
        try await refused(.notAnApproval) {
            try await approver(key).answer(tenant: "t1", callID: "e1", answer: .reject, accountingVersion: 3, signedAt: "t", pin: nil)
        }
        try expectEqual(key.asked, [])
        try expectEqual(transport.sent.count, 0)
    }),
    Test("KIFF's refusal of an Approve once comes back as KIFF's, for the card's line", awaiting: {
        let transport = CannedTransport([(403, #"{"error":"passkey_not_this_device"}"#)])
        let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")
        let passkey = PasskeySession(transport: transport, session: session, approver: approver(FakeKey()))
        let call = try heldCall(#"{"id":"e1","subject":"a","action":"b","created_at":"2026-11-14T18:00:00Z","title":"T","accounting_version":3}"#)
        do { try await passkey.approveOnce(call, pin: nil); throw Failure(description: "taken") } catch KIFFError.refused(status: 403, code: let code) {
            try expectEqual(code, "passkey_not_this_device")
        }
    }),
    Test("Extra room on the key: KIFF's change-card over the same kiff.answer.v1, sent to change-card; never without its version", awaiting: {
        let key = FakeKey()
        let transport = CannedTransport([(200, "{}")])
        let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")
        let passkey = PasskeySession(transport: transport, session: session, approver: approver(key))
        // Over a total: KIFF says it can't be approved once, which Extra room doesn't ask.
        let call = try heldCall(#"{"id":"e1","subject":"a","action":"b","created_at":"2026-11-14T18:00:00Z","title":"T","accounting_version":4,"can_approve_once":false}"#)
        let now = Date(timeIntervalSince1970: 1_794_679_800)
        try await passkey.extraRoom(call, pin: nil, now: now)
        let message = "kiff.answer.v1\nt1\ne1\nchange-card\n\n\n4\n" + KIFFMessage.time(now)
        try expectEqual(key.asked, [testSHA256(PasskeyApprover.clientDataJSON(Data(message.utf8), sha256: testSHA256))])
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["POST /v1/me/card-exceptions/e1/change-card"])
        let unversioned = try heldCall(#"{"id":"e2","subject":"a","action":"b","created_at":"2026-11-14T18:00:00Z","title":"T","can_approve_once":false}"#)
        do { try await passkey.extraRoom(unversioned, pin: nil); throw Failure(description: "sent") } catch is KIFFError {}
        try expectEqual(key.asked.count, 1)
    }),
]

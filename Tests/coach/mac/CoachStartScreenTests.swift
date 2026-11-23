import CryptoKit
import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let none = #"{"setup":null}"#
private let draft = #"{"id":"drf_1","claim_secret":"sec_1"}"#

@MainActor
private func coachModel(_ answers: [(Int, String)], sleep: @escaping (TimeInterval) async throws -> Void = { _ in }) -> (CoachModel, CannedTransport) {
    let transport = CannedTransport(answers)
    return (CoachModel(cloud: CloudClient(transport: transport, session: session), sleep: sleep), transport)
}

private func english() -> Words { Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"]) }

/// A security key with a real P-256 key: kiff.dev's authenticator data, present and verified, and
/// an ES256 signature over `authData ‖ clientDataHash`, as KIFF checks it.
private final class RealKey: PasskeyAuthenticator {
    let key = P256.Signing.PrivateKey()
    var pins: [[UInt8]?] = []
    func getAssertion(clientDataHash: Data, credentialID: Data, pin: SecurityKeyPIN?) async throws -> PasskeyAssertion {
        pins.append(pin?.heldBytesForTests())
        pin?.release()
        let authData = PasskeyCrypto.sha256(Data("kiff.dev".utf8)) + Data([0x05, 0, 0, 0, 1])
        let signature = try key.signature(for: authData + clientDataHash).derRepresentation
        return PasskeyAssertion(authenticatorData: authData, signatureDER: signature)
    }
    func makeCredential(clientDataHash: Data, userID: Data, userName: String, pin: SecurityKeyPIN?) async throws -> PasskeyMade {
        throw PasskeyRefusal.unreadable
    }
}

private func passkeySession(_ transport: Transport, key: RealKey) -> PasskeySession {
    var approver = PasskeyApprover(authenticator: key, credentialID: Data([7, 7]), sha256: PasskeyCrypto.sha256)
    approver.enabled = true
    return PasskeySession(transport: transport, session: session, approver: approver)
}

/// The PIN sheet's stand-in: the PIN typed, handed to the key once.
private func typed(_ passkey: PasskeySession) -> (Data) async throws -> PasskeySession.Signed {
    { body in
        var bytes = Array("4821".utf8)
        return try await passkey.signDraft(body, pin: try SecurityKeyPIN(utf8: &bytes))
    }
}

let coachStartMacTests: [Test] = [
    Test("a Mac that can't approve follows the start made on the phone: Setup is read again until Coach is there", awaiting: { @MainActor in
        var waits: [TimeInterval] = []
        let (model, transport) = coachModel([(200, none), (200, none), (200, setupAnswer), (200, noChats), (200, threadAnswer)],
                                            sleep: { waits.append($0) })
        await model.load()
        try expectEqual(model.state, .notStarted)
        await model.followStart()
        guard case .loaded(let coach, _) = model.state else { throw Failure(description: "not followed") }
        try expectEqual(coach.id, "taf-coach")
        // Two waits, as `Backoff.start`'s: 10 seconds then 20, each with its jitter.
        try expectEqual(waits.count, 2)
        try expect((8...12).contains(waits[0]) && (16...24).contains(waits[1]), "the start backs off from 10 s: \(waits)")
        // Only reads: nothing is started from this Mac.
        try expectEqual(Set(transport.sent.map(\.method)), ["GET"])
    }),
    Test("following stops once the session ends", awaiting: { @MainActor in
        var model: CoachModel?
        let (made, transport) = coachModel([(200, none), (200, none), (200, none)], sleep: { _ in model?.signedOut() })
        model = made
        await made.load()
        await made.followStart()
        try expectEqual(transport.sent.count, 1)
        try expectEqual(made.state, .notStarted)
    }),
    Test("Start with the security key: the draft carries the key's approval, verified as KIFF reads it; then Coach's thread is read", awaiting: { @MainActor in
        let words = english()
        let key = RealKey()
        let kiff = CannedTransport([(201, draft)])
        let passkey = passkeySession(kiff, key: key)
        let device = AccountClient(transport: CannedTransport([]), session: session, sign: { _ in "t=x,v1=DEVICE" })
        let (model, transport) = coachModel([(200, none), (200, none), (201, setupAnswer), (200, setupAnswer), (200, noChats), (200, threadAnswer)])
        await model.load()
        let started = await model.startSetup(account: device, approval: passkey, sign: typed(passkey), confirm: {}, enrol: { _ in nil }, words: words)
        try expectEqual(started, true)
        guard case .loaded(let coach, _) = model.state else { throw Failure(description: "not read") }
        try expectEqual(coach.id, "taf-coach")
        try expectEqual(model.setupError, nil)
        try expectEqual(model.planqueReady, true)
        try expectEqual(Array(transport.sent.map { $0.method + " " + $0.path }.prefix(3)), ["GET /v1/setup", "GET /v1/setup", "POST /v1/setup"])
        try expectEqual(key.pins, [Array("4821".utf8)])
        // KIFF's check: the challenge is the draft's own message, and the signature is the key's.
        let sent = kiff.sent[0]
        try expectEqual(sent.headers["KIFF-Device-Signature"], nil)
        let header = sent.headers["KIFF-Passkey-Assertion"] ?? ""
        let parts = Dictionary(uniqueKeysWithValues: header.split(separator: ",").map { p -> (String, String) in
            let pair = p.split(separator: "=", maxSplits: 1); return (String(pair[0]), String(pair[1]))
        })
        let signedAt = parts["t"] ?? ""
        try expect(signedAt.contains("."), "milliseconds: \(signedAt)")
        guard let fields = try JSONSerialization.jsonObject(with: Encoding.fromBase64URL(parts["a"] ?? "") ?? Data()) as? [String: String],
              let clientData = Encoding.fromBase64URL(fields["client_data_json"] ?? ""),
              let authData = Encoding.fromBase64URL(fields["authenticator_data"] ?? ""),
              let signature = Encoding.fromBase64URL(fields["signature"] ?? "") else { throw Failure(description: "no assertion") }
        let message = KIFFMessage.request(tenant: "t1", method: "POST", path: "/v1/me/agent-drafts", bodyHash: Signing.sha256Hex(sent.body), signedAt: signedAt)
        try expectEqual(clientData, PasskeyApprover.clientDataJSON(Data(message.utf8), sha256: PasskeyCrypto.sha256))
        let ecdsa = try P256.Signing.ECDSASignature(derRepresentation: signature)
        try expect(key.key.publicKey.isValidSignature(ecdsa, for: authData + PasskeyCrypto.sha256(clientData)), "the key's signature over this draft")
    }),
    Test("without the security key's session nothing is asked and Start says to approve on another device; a taf's chat never starts", awaiting: { @MainActor in
        let words = english()
        let device = AccountClient(transport: CannedTransport([]), session: session, sign: { _ in "t=x,v1=DEVICE" })
        let (phone, phoneSent) = coachModel([(200, none)])
        await phone.load()
        var asked = 0
        let tried = await phone.startSetup(account: device, approval: nil, sign: { _ in asked += 1; throw CancellationError() },
                                           confirm: { asked += 1 }, enrol: { _ in asked += 1; return nil }, words: words)
        try expectEqual(tried, false)
        try expectEqual(phone.setupError, words("approval.device_can_not_approve_approve"))
        try expectEqual(asked, 0)
        try expectEqual(phoneSent.sent.count, 1)
        let tafSent = CannedTransport([])
        let taf = CoachModel(cloud: CloudClient(transport: tafSent, session: session), taf: Coach(id: "taf-1", name: "Refunds"))
        let key = RealKey()
        let passkey = passkeySession(CannedTransport([]), key: key)
        let fromTaf = await taf.startSetup(account: device, approval: passkey, sign: typed(passkey), confirm: {}, enrol: { _ in nil }, words: words)
        try expectEqual(fromTaf, false)
        try expectEqual(tafSent.sent.count, 0)
        try expectEqual(key.pins.count, 0)
    }),
    Test("a closed PIN sheet starts nothing and says nothing; Start stays", awaiting: { @MainActor in
        let device = AccountClient(transport: CannedTransport([]), session: session, sign: { _ in "t=x,v1=DEVICE" })
        let kiff = CannedTransport([])
        let passkey = passkeySession(kiff, key: RealKey())
        let (model, _) = coachModel([(200, none), (200, none)])
        await model.load()
        var enrolled = 0
        let started = await model.startSetup(account: device, approval: passkey, sign: { _ in throw CancellationError() }, confirm: {},
                                             enrol: { _ in enrolled += 1; return nil }, words: english())
        try expectEqual(started, false)
        try expectEqual(model.setupError, nil)
        try expectEqual(model.state, .notStarted)
        try expectEqual([enrolled, kiff.sent.count], [0, 0])
    }),
    Test("the screenshots: Coach's start on a Mac that can't approve, and on one whose security key may", awaiting: { @MainActor in
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let (phone, _) = coachModel([(200, none)], sleep: { _ in throw CancellationError() })
        await phone.load()
        let onPhone = CoachView(model: phone).environment(\.words, english())
        guard let bitmap = Snapshot.bitmap(of: onPhone, size: CGSize(width: 980, height: 600)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
        try png.write(to: folder.appendingPathComponent("coach-start-phone-en.png"))
        let (may, _) = coachModel([(200, none)])
        await may.load()
        let withStart = CoachView(model: may, start: {}).environment(\.words, english())
        guard let shot = Snapshot.bitmap(of: withStart, size: CGSize(width: 980, height: 600)), let startPNG = Snapshot.png(shot) else { throw Failure(description: "no PNG") }
        try startPNG.write(to: folder.appendingPathComponent("coach-start-key-en.png"))
    }),
]

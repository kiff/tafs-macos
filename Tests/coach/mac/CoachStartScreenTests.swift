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

/// What the Touch ID answers in these tests: the context the approval key signs under.
private final class Confirmed {}

/// An approval session over `transport`, signing with `key` only under `confirmed`.
private func approvalSession(_ transport: Transport, key: P256.Signing.PrivateKey = .init(), confirmed: AnyObject) -> ApprovalSession {
    ApprovalSession(transport: transport, session: session, bodyHash: Signing.sha256Hex, sign: { message, context in
        guard context === confirmed else { throw Failure(description: "not under the Touch ID") }
        return try key.signature(for: message).derRepresentation.base64EncodedString()
    })
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
        try expectEqual(waits, [10, 10])
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
    Test("Start on a Mac that may: started reads Coach's thread; a first start or a stop says why and keeps Start", awaiting: { @MainActor in
        let words = english()
        let kiff = CannedTransport([(201, draft)])
        let touch = Confirmed()
        let approval = approvalSession(kiff, confirmed: touch)
        let device = AccountClient(transport: CannedTransport([]), session: session, sign: { _ in "t=x,v1=DEVICE" })
        let (model, transport) = coachModel([(200, none), (200, none), (201, setupAnswer), (200, setupAnswer), (200, noChats), (200, threadAnswer)])
        await model.load()
        let started = await model.startSetup(account: device, approval: approval, enrol: { _ in nil }, confirm: { touch }, words: words)
        try expectEqual(started, true)
        guard case .loaded(let coach, _) = model.state else { throw Failure(description: "not read") }
        try expectEqual(coach.id, "taf-coach")
        try expectEqual(model.setupError, nil)
        try expectEqual(model.planqueReady, true)
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }.prefix(3), ["GET /v1/setup", "GET /v1/setup", "POST /v1/setup"])
        // Without an approval key the draft isn't sent, and Start says to approve on another device.
        let (phone, _) = coachModel([(200, none), (200, none)])
        await phone.load()
        var asked = 0
        let tried = await phone.startSetup(account: device, approval: nil, enrol: { _ in nil }, confirm: { asked += 1; return touch }, words: words)
        try expectEqual(tried, false)
        try expectEqual(phone.setupError, words("approval.device_can_not_approve_approve"))
        try expectEqual(phone.state, .notStarted)
        try expectEqual(asked, 0)
        // A taf's own chat never starts Coach.
        let tafSent = CannedTransport([])
        let taf = CoachModel(cloud: CloudClient(transport: tafSent, session: session), taf: Coach(id: "taf-1", name: "Refunds"))
        let fromTaf = await taf.startSetup(account: device, approval: approval, enrol: { _ in nil }, confirm: { touch }, words: words)
        try expectEqual(fromTaf, false)
        try expectEqual(tafSent.sent.count, 0)
    }),
    Test("the mint and Setup's draft are signed at two different times, in milliseconds, each verified as KIFF reads it", awaiting: { @MainActor in
        let deviceKey = SoftwareKey(key: .init())
        let approvalKey = P256.Signing.PrivateKey()
        let kiff = CannedTransport([(201, #"{"id":"key_c","plaintext":"kiff_live_connector","roles":["connector"]}"#)])
        let account = AccountClient(session: session, key: deviceKey, language: "en", transport: kiff)
        let planqueSent = CannedTransport([(409, #"{"code":"needs_key"}"#), (201, #"{"tenant":"t1","device":"ab12","kept":true}"#)])
        let planque = PlanqueClient(baseURL: "https://planque.test")
        planque.tenant = "t1"
        planque.deviceID = "dev_9"
        planque.transport = planqueSent
        planque.bodyHash = Signing.sha256Hex
        planque.signer = { try deviceKey.sign(Data($0.utf8)).base64EncodedString() }
        let approvalKIFF = CannedTransport([(201, draft)])
        let touch = Confirmed()
        let cloud = CannedTransport([(200, none), (201, setupAnswer)])
        let (outcome, _) = await CoachStart.start(
            coach: nil, planqueReady: false, cloud: CloudClient(transport: cloud, session: session), account: account,
            approval: approvalSession(approvalKIFF, key: approvalKey, confirmed: touch), confirm: { touch },
            enrol: { ended in await PlanqueEnrolment.enrol(planque: planque, account: account, deviceKey: deviceKey.publicKeyDER, ended: ended) },
            ended: { false }, words: english())
        guard case .started = outcome else { throw Failure(description: "\(outcome)") }
        func fields(_ header: String?) -> [String: String] {
            Dictionary(uniqueKeysWithValues: (header ?? "").split(separator: ",").compactMap { part -> (String, String)? in
                let pair = part.split(separator: "=", maxSplits: 1)
                return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
            })
        }
        let mint = kiff.sent[0], draftSent = approvalKIFF.sent[0]
        let mintFields = fields(mint.headers["KIFF-Device-Signature"]), draftFields = fields(draftSent.headers["KIFF-Device-Signature"])
        let mintAt = mintFields["t"] ?? "", draftAt = draftFields["t"] ?? ""
        try expect(mintAt.contains(".") && draftAt.contains("."), "milliseconds: \(mintAt), \(draftAt)")
        try expect(mintAt != draftAt, "two times: \(mintAt)")
        let mintMessage = KIFFMessage.request(tenant: "t1", method: "POST", path: "/v1/keys", bodyHash: Signing.sha256Hex(mint.body), signedAt: mintAt)
        try expect(Signing.verifies(mintFields["v1"] ?? "", over: mintMessage, publicKeyDER: deviceKey.publicKeyDER), "the mint is the device key's")
        let draftMessage = KIFFMessage.request(tenant: "t1", method: "POST", path: "/v1/me/agent-drafts", bodyHash: Signing.sha256Hex(draftSent.body), signedAt: draftAt)
        try expect(Signing.verifies(draftFields["v1"] ?? "", over: draftMessage, publicKeyDER: approvalKey.publicKey.derRepresentation), "the draft is the approval key's")
        try expect(!Signing.verifies(draftFields["v1"] ?? "", over: draftMessage, publicKeyDER: deviceKey.publicKeyDER), "never the device key's")
    }),
    Test("the screenshots: Coach's start on a Mac that can't approve, and on one that may", awaiting: { @MainActor in
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
        try startPNG.write(to: folder.appendingPathComponent("coach-start-touchid-en.png"))
    }),
]

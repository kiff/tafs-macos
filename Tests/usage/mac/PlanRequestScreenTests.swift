import Foundation
import LocalAuthentication
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")
private let teamUsage = #"{"plan":"team","requests":[{"id":"req_5","asked_by":"u1","kind":"raise","reason":"","status":"open","created_at":"2026-11-15T10:00:00Z","expires_at":"2026-11-30T23:59:59Z"}]}"#

/// A model whose tafs cloud answers the balance and the credits, and whose KIFF answers `kiff`.
@MainActor
private func model(_ kiff: [(Int, String)], signed: Bool = true,
                   confirm: @escaping (String) async throws -> Void = { _ in }) -> (UsageModel, CannedTransport) {
    let cloud = CannedTransport([(200, balanceAnswer), (200, creditsAnswer), (200, balanceAnswer), (200, creditsAnswer)])
    let transport = CannedTransport(kiff)
    let account = AccountClient(transport: transport, session: session, sign: signed ? { _ in "t=x,v1=SIG" } : nil)
    return (UsageModel(cloud: CloudClient(transport: cloud, session: session), account: account, confirm: confirm), transport)
}

let usageRequestScreenTests: [Test] = [
    Test("Raise the limit asks the owner first, every time; closed, nothing is built or sent; then a signed PUT and the balance read again", awaiting: { @MainActor in
        let offered = #"{"balance":{"state":"ok","words":"820 credits left","raise":{"words":"Raise the spend limit to €2,000","from_cents":100000}}}"#
        let raised = #"{"balance":{"state":"ok","words":"1,820 credits left","raise":{"words":"Raise the spend limit to €3,000","from_cents":200000}}}"#
        let cloud = CannedTransport([(200, offered), (200, creditsAnswer), (200, raised), (200, creditsAnswer), (200, raised), (200, creditsAnswer)])
        let kiff = CannedTransport([(200, teamUsage), (200, "{}"), (200, teamUsage), (200, teamUsage)])
        var asked: [String] = []
        var allow = false
        let account = AccountClient(transport: kiff, session: session, sign: { _ in "t=x,v1=SIG" })
        let model = UsageModel(cloud: CloudClient(transport: cloud, session: session), account: account, confirm: { prompt in
            asked.append(prompt)
            if !allow { throw LAError(.userCancel) }
        })
        await model.load()
        // Not someone who manages billing: nothing is asked or sent.
        await model.raiseLimit(managesBilling: false)
        try expectEqual(asked.count, 0)
        // The prompt closed: no request is built.
        await model.raiseLimit(managesBilling: true)
        try expectEqual(asked, [Words.app("usage.raise_limit.prompt") + ": Raise the spend limit to €2,000"])
        try expect(!kiff.sent.contains { $0.method == "PUT" }, "nothing sent without the owner's yes")
        try expectEqual(model.raiseWhy, nil)
        // Confirmed: one signed PUT from the limit seen, then the balance read again, offering the next raise.
        allow = true
        await model.raiseLimit(managesBilling: true)
        let puts = kiff.sent.filter { $0.method == "PUT" }
        try expectEqual(puts.map(\.path), ["/v1/me/usage/limit"])
        try expectEqual(String(decoding: puts[0].body, as: UTF8.self), #"{"from_cents":100000,"raise":true}"#)
        try expect(puts[0].headers["KIFF-Device-Signature"] != nil, "signed by the device key")
        try expectEqual(asked.count, 2)
        try expectEqual(model.balanceStale, false)
        guard case .loaded(let now) = model.balance else { throw Failure(description: "not read") }
        try expectEqual(now.raise?.fromCents, 200000)
    }),
    Test("a raise KIFF refuses as changed reads the balance again and says so; at the ceiling it says to contact KIFF", awaiting: { @MainActor in
        let offered = #"{"balance":{"state":"ok","words":"820 credits left","raise":{"words":"Raise the spend limit to €2,000","from_cents":100000}}}"#
        let cloud = CannedTransport([(200, offered), (200, creditsAnswer), (200, offered), (200, creditsAnswer)])
        let kiff = CannedTransport([(200, teamUsage), (409, #"{"error":"limit_changed"}"#), (200, teamUsage), (409, #"{"error":"limit_ceiling"}"#)])
        let account = AccountClient(transport: kiff, session: session, sign: { _ in "t=x,v1=SIG" })
        let model = UsageModel(cloud: CloudClient(transport: cloud, session: session), account: account, confirm: { _ in })
        await model.load()
        await model.raiseLimit(managesBilling: true)
        try expectEqual(model.raiseWhy, Words.app("usage.limit_changed"))
        await model.raiseLimit(managesBilling: true)
        try expectEqual(model.raiseWhy, Words.app("usage.limit_ceiling"))
    }),
    Test("KIFF's usage is read with each read; one that fails keeps what was read and says why", awaiting: { @MainActor in
        let (model, transport) = model([(200, kiffUsageAnswer), (503, "")])
        await model.load()
        try expectEqual(model.usage?.plan, "solo")
        try expectEqual(model.usageError, nil)
        await model.load()
        try expectEqual(model.usage?.plan, "solo")
        try expectEqual(model.usageError, Words.app("billing.plan_could_not_read_kiff", ["why": Words.app("error.down")]))
        try expectEqual(transport.sent.map(\.path), ["/v1/me/usage", "/v1/me/usage"])
        // The First month pack isn't ready in this balance: Rayo alone is offered.
        try expectEqual(model.offeredPacks.map(\.id), ["rayo"])
    }),
    Test("asking an admin reads everything again once sent; one KIFF doesn't take says why and stays", awaiting: { @MainActor in
        let (model, transport) = model([(200, packRequestAnswer), (200, teamUsage), (409, #"{"error":"request_open"}"#)])
        let got1 = await model.askAdmin(raise: true, reason: "  For refunds  ")
        try expectEqual(got1, true)
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["POST /v1/me/pack-requests", "GET /v1/me/usage"])
        try expectEqual(String(decoding: transport.sent[0].body, as: UTF8.self), #"{"kind":"raise","reason":"For refunds"}"#)
        try expectEqual(model.usage?.plan, "team")
        let got2 = await model.askAdmin(raise: true, reason: "")
        try expectEqual(got2, false)
        try expectEqual(model.planMessage, Words.app("billing.request.not_sent", ["why": Words.app("error.changed")]))
    }),
    Test("withdrawing reads everything again, taken or not, as the iPad's withdrawRequest", awaiting: { @MainActor in
        let (model, transport) = model([(200, teamUsage), (404, #"{"error":"not_found"}"#), (200, teamUsage)])
        await model.load()
        guard let mine = model.usage?.requests?.first else { throw Failure(description: "no request") }
        await model.withdrawRequest(mine)
        try expectEqual(model.planMessage, Words.app("billing.request.not_withdrawn", ["why": Words.app("error.ours")]))
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["GET /v1/me/usage", "POST /v1/me/pack-requests/req_5/withdraw", "GET /v1/me/usage"])
    }),
    Test("a decline asks for Touch ID or the Mac's password, then is signed; closed, nothing is sent and it says \"Cancelled. Nothing changed.\"", awaiting: { @MainActor in
        var asked: [String] = []
        let (admin, transport) = model([(200, teamUsage), (200, packRequestAnswer), (200, teamUsage)], confirm: { asked.append($0) })
        await admin.load()
        guard let request = admin.usage?.requests?.first else { throw Failure(description: "no request") }
        let got3 = await admin.declineRequest(request, note: " Not now ")
        try expectEqual(got3, true)
        try expectEqual(asked, [Words.app("billing.request.decline_prompt")])
        try expectEqual(transport.sent[1].path, "/v1/me/pack-requests/req_5/decline")
        try expectEqual(transport.sent[1].headers["KIFF-Device-Signature"], "t=x,v1=SIG")
        try expectEqual(String(decoding: transport.sent[1].body, as: UTF8.self), #"{"note":"Not now"}"#)
        try expectEqual(transport.sent.count, 3)
        // The prompt closed: nothing sent, and it says so, as every app does where nothing is
        // pending after it.
        let (closed, quiet) = model([(200, teamUsage)], confirm: { _ in throw LAError(.userCancel) })
        await closed.load()
        let got4 = await closed.declineRequest(request, note: "")
        try expectEqual(got4, false)
        try expectEqual(quiet.sent.map(\.method), ["GET"])
        try expectEqual(closed.planMessage, Words.app("approval.cancelled"))
        try expectEqual(closed.planMessage, "Cancelled. Nothing changed.")
        // A prompt that failed, not closed: nothing sent, and it wasn't confirmed.
        let (failed, quieter) = model([(200, teamUsage)], confirm: { _ in throw LAError(.authenticationFailed) })
        await failed.load()
        let got5 = await failed.declineRequest(request, note: "")
        try expectEqual(got5, false)
        try expectEqual(quieter.sent.map(\.method), ["GET"])
        try expectEqual(failed.planMessage, Words.app("common.not_sent_unconfirmed"))
    }),
    Test("a decline without a device key says to sign in again; one KIFF refuses says why and reads again", awaiting: { @MainActor in
        let (keyless, quiet) = model([(200, teamUsage)], signed: false)
        await keyless.load()
        guard let request = keyless.usage?.requests?.first else { throw Failure(description: "no request") }
        let got5 = await keyless.declineRequest(request, note: "")
        try expectEqual(got5, false)
        try expectEqual(keyless.planMessage, Words.app("sign_in.again_to_sign"))
        try expectEqual(quiet.sent.count, 1)
        let (refused, transport) = model([(200, teamUsage), (409, #"{"error":"request_closed"}"#), (200, teamUsage)])
        await refused.load()
        let got6 = await refused.declineRequest(request, note: "")
        try expectEqual(got6, false)
        try expectEqual(refused.planMessage, Words.app("billing.request.not_declined", ["why": Words.app("error.changed")]))
        try expectEqual(transport.sent.map(\.method), ["GET", "POST", "GET"])
    }),
    Test("KIFF's refusal reads as the app's plain line, never its code; a 401 is signed out, as the iPad's KIFFError", awaiting: { @MainActor in
        try expectEqual(UsageModel.plainWhy(KIFFError.refused(status: 409, code: "request_open")), Words.app("error.changed"))
        try expectEqual(UsageModel.plainWhy(KIFFError.refused(status: 401, code: "token_expired")), Words.app("error.signed_out"))
        try expectEqual(UsageModel.plainWhy(KIFFError.refused(status: 503, code: "")), Words.app("error.down"))
        try expectEqual(UsageModel.plainWhy(KIFFError.unreadable), Words.app("error.ours"))
    }),
    Test("a decline whose session ends while the prompt is up sends nothing and says nothing, as the iPad's accountGeneration", awaiting: { @MainActor in
        var release: CheckedContinuation<Void, Never>?
        let (admin, transport) = model([(200, teamUsage), (200, packRequestAnswer), (200, teamUsage)], confirm: { _ in
            await withCheckedContinuation { release = $0 }
        })
        await admin.load()
        guard let request = admin.usage?.requests?.first else { throw Failure(description: "no request") }
        var heard: Bool?
        admin.startDecline(request, note: "") { heard = $0 }
        for _ in 0..<1_000 where release == nil { await Task.yield() }
        // Signed out while the prompt is up; then the person confirms.
        admin.cancelAnswers()
        release?.resume()
        for _ in 0..<1_000 { await Task.yield() }
        try expectEqual(transport.sent.map(\.method), ["GET"])
        try expectEqual(admin.planMessage, nil)
        try expectEqual(heard, nil)
    }),
    Test("who asks what, and the lines both apps share, as the iPad's UsageView helpers", awaiting: { @MainActor in
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        let (model, _) = model([(200, kiffUsageAnswer)])
        await model.load()
        guard let solo = model.usage else { throw Failure(description: "no usage") }
        let team = try AccountClient.decoder.decode(KIFFUsage.self, from: Data(teamUsage.utf8))
        let none = try AccountClient.decoder.decode(KIFFUsage.self, from: Data(#"{"plan":"company"}"#.utf8))
        try expectEqual([UsageView.asks(team), UsageView.asks(solo), UsageView.asks(none)], [true, false, nil])
        // A member's own: the open one waits; an admin has none of their own.
        try expectEqual(UsageView.waiting(solo, managesBilling: false)?.id, "req_1")
        try expectEqual(UsageView.waiting(solo, managesBilling: true)?.id, nil)
        try expectEqual(UsageView.openRequests(solo, managesBilling: true).map(\.id), ["req_1"])
        try expectEqual(UsageView.openRequests(solo, managesBilling: false).map(\.id), [])
        try expectEqual(UsageView.requestLine(solo.requests![0], in: solo, words: words), "Someone asks for Rayo · 5,000 credits.")
        try expectEqual(UsageView.requestLine(team.requests![0], in: team, words: words), "Someone asks to raise the spend limit.")
        try expectEqual(UsageView.packLine(nil, in: solo, words: words), "a pack of credits")
        try expectEqual(UsageView.packLine("gone", in: solo, words: words), "Gone")
        try expectEqual(UsageView.declineQuestion(team.requests![0], in: team, words: words), "Decline the request to raise the spend limit?")
        try expectEqual(UsageView.askedLine(team.requests![0], words: words), "You asked an admin to raise the spend limit.")
        let declined = try AccountClient.decoder.decode(KIFFUsage.self, from: Data(#"{"plan":"team","requests":[{"id":"r","asked_by":"u1","kind":"raise","status":"declined","note":"Not this month.","created_at":"2026-11-15T10:00:00Z","expires_at":"2026-11-30T23:59:59Z"}]}"#.utf8))
        try expectEqual(UsageView.lastAnswer(declined, managesBilling: false, words: words), "An admin declined: Not this month.")
        try expectEqual(UsageView.lastAnswer(declined, managesBilling: true, words: words), nil)
    }),
    Test("the screenshots: a member's waiting request, an admin's requests, and asking", awaiting: { @MainActor in
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let (member, _) = model([(200, teamUsage)])
        await member.load()
        let (admin, _) = model([(200, kiffUsageAnswer)])
        await admin.load()
        let shots: [(String, AnyView, CGSize)] = [
            ("usage-request-member-en", AnyView(UsageView(model: member, managesBilling: false)), CGSize(width: 980, height: 900)),
            ("usage-requests-admin-en", AnyView(UsageView(model: admin, managesBilling: true)), CGSize(width: 980, height: 900)),
            ("usage-ask-admin-en", AnyView(AskAdminView(model: admin, raise: false)), CGSize(width: 440, height: 360)),
            ("usage-decline-en", AnyView(DeclineRequestView(model: admin, request: admin.usage!.requests![0])), CGSize(width: 440, height: 240)),
        ]
        for (name, view, size) in shots {
            guard let bitmap = Snapshot.bitmap(of: view.environment(\.words, words), size: size), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG for \(name)") }
            try png.write(to: folder.appendingPathComponent(name + ".png"))
        }
    }),
]

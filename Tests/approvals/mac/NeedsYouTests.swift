import CryptoKit
import Foundation
import LocalAuthentication
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")
private let one = #"{"exceptions":[{"id":"exc_1","subject":"a","action":"stripe.refund","title":"Refund a payment","reason_text":"€640 is over its €500 limit.","taf_about":"Dispute #4825","taf_reason":"The customer was charged twice.","created_at":"2026-11-14T18:00:00Z","expires_at":"2026-11-14T18:42:00Z","accounting_version":3,"parameters":{"amount":64000},"parameter_units":{"amount":{"unit":"EUR","scale":2}}}]}"#
private let none = #"{"exceptions":[]}"#

@MainActor
private func model(_ answers: [(Int, String)], route: ApprovalRoute = .phoneOrPasskey,
                   confirm: @escaping (String) async throws -> Void = { _ in }) -> (NeedsYouModel, CannedTransport) {
    let transport = CannedTransport(answers)
    let account = AccountClient(transport: transport, session: session, signMessage: { _ in "SIG" })
    return (NeedsYouModel(account: account, route: route, confirm: confirm), transport)
}

private let stepJSON = #"{"handoff":"h1","what":"Approve the transfer","words":{"done":"Done","skip":"Skip it"}}"#

let approvalsScreenTests: [Test] = [
    Test("a call's time left counts down as a clock, m:ss or h:mm:ss, in the shared words, and says when it expired") {
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        let at = Date(timeIntervalSince1970: 1_794_679_800)
        try expectEqual(NeedsYouView.left(until: at.addingTimeInterval(486), at: at, words: words), "8:06 left")
        try expectEqual(NeedsYouView.left(until: at.addingTimeInterval(59), at: at, words: words), "0:59 left")
        try expectEqual(NeedsYouView.left(until: at.addingTimeInterval(3_725), at: at, words: words), "1:02:05 left")
        try expectEqual(NeedsYouView.left(until: at, at: at, words: words), "expired")
    },
    Test("the list is KIFF's: loaded, counted, and read again after a refusal", awaiting: { @MainActor in
        let (model, transport) = model([(200, one), (200, "{}"), (200, none)])
        await model.load()
        try expectEqual(model.count, 1)
        guard case .loaded(let calls) = model.state else { throw Failure(description: "not loaded") }
        await model.refuse(calls[0])
        try expectEqual(transport.sent.map(\.path), ["/v1/me/card-exceptions?status=held", "/v1/me/card-exceptions/exc_1/reject", "/v1/me/card-exceptions?status=held"])
        try expectEqual(model.state, .loaded([]))
        try expectEqual(model.answering, nil)
    }),
    Test("a refusal KIFF doesn't take stays on screen with its reason, and the call stays listed", awaiting: { @MainActor in
        let (model, _) = model([(200, one), (403, #"{"error":"approver_only"}"#)])
        await model.load()
        guard case .loaded(let calls) = model.state else { throw Failure(description: "not loaded") }
        await model.refuse(calls[0])
        try expectEqual(NeedsYouView.notTakenLine(model, calls[0]), Words.app("needs_you.refused.other", ["why": "approver_only"]))
        try expectEqual(model.count, 1)
    }),
    Test("Refuse asks for Touch ID or the Mac's password first, as the iPad's sign(_:reason:): closed, or failed, nothing is sent", awaiting: { @MainActor in
        var asked: [String] = []
        let (confirmed, confirmedTransport) = model([(200, one), (200, "{}"), (200, none)], confirm: { asked.append($0) })
        await confirmed.load()
        guard case .loaded(let calls) = confirmed.state else { throw Failure(description: "not loaded") }
        await confirmed.refuse(calls[0])
        try expectEqual(asked, [Words.app("needs_you.prompt.answer", ["summary": "Refund a payment"])])
        try expectEqual(confirmedTransport.sent.map(\.method), ["GET", "POST", "GET"])
        // Closed by the person: the call is kept, nothing is signed or sent.
        let (cancelled, cancelledTransport) = model([(200, one)], confirm: { _ in throw LAError(.userCancel) })
        await cancelled.load()
        await cancelled.refuse(calls[0])
        try expectEqual(cancelledTransport.sent.map(\.method), ["GET"])
        // The line the card shows is the prompt's own words, never "KIFF didn't take the answer".
        try expectEqual(NeedsYouView.notTakenLine(cancelled, calls[0]), Words.app("approval.cancelled_nothing_approved_request_kept"))
        try expectEqual(cancelled.count, 1)
        // Any other failure: not sent, for want of a confirmation.
        let (failed, failedTransport) = model([(200, one)], confirm: { _ in throw LAError(.authenticationFailed) })
        await failed.load()
        await failed.refuse(calls[0])
        try expectEqual(failedTransport.sent.map(\.method), ["GET"])
        try expectEqual(NeedsYouView.notTakenLine(failed, calls[0]), Words.app("common.not_sent_unconfirmed"))
        try expectEqual(failed.answering, nil)
    }),
    Test("a list that can't be read says so, and is never shown as empty", awaiting: { @MainActor in
        let (model, _) = model([(500, "")])
        await model.load()
        try expectEqual(model.state, .unread(why: "500"))
    }),
    Test("Did this happen?'s amount reads as the iPad's Money, and its line shows only where the Mac approves elsewhere") {
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        try expectEqual(NeedsYouView.amount(TafCard.Amount(minor: 725, unit: nil, scale: 0), words: words), "725 (no currency)")
        try expectEqual(NeedsYouView.amount(TafCard.Amount(minor: 4000, unit: "EUR", scale: 2), words: words), "€40")
        try expectEqual(NeedsYouView.saysCantApprove(answersHolds: true, route: .phoneOrPasskey), true)
        try expectEqual(NeedsYouView.saysCantApprove(answersHolds: true, route: .touchID), false)
        try expectEqual(NeedsYouView.saysCantApprove(answersHolds: false, route: .phoneOrPasskey), false)
    },
    Test("Did this happen? is read only for someone who answers held calls, and a failed read keeps the list", awaiting: { @MainActor in
        let list = #"{"calls":[{"proposal":"p1","title":"Refund a payment","words":"Refund a payment: 40.00 EUR."}]}"#
        let (model, transport) = model([(200, list), (500, "")])
        await model.loadUnproven(answersHolds: false)
        try expectEqual(transport.sent.count, 0)
        await model.loadUnproven(answersHolds: true)
        try expectEqual(model.unproven.map(\.proposal), ["p1"])
        await model.loadUnproven(answersHolds: true)
        try expectEqual(model.unproven.map(\.proposal), ["p1"])
    }),
    Test("a step is answered as the iPad's: its hand-off read first, the device key signs kiff.handoff.v1, then it leaves the list", awaiting: { @MainActor in
        let step = try JSONDecoder().decode(YourStep.self, from: Data(#"{"handoff":"h1","what":"Approve the transfer","words":{"done":"Done","skip":"Skip it"}}"#.utf8))
        var signed: [String] = []
        let transport = CannedTransport([(200, #"{"id":"h1","version":2,"status":"waiting"}"#), (200, "{}")])
        let account = AccountClient(transport: transport, session: session, signMessage: { signed.append($0); return "SIG" })
        var asked: [String] = []
        let model = NeedsYouModel(account: account, route: .phoneOrPasskey, confirm: { asked.append($0) })
        model.showSteps([step])
        try expectEqual(model.canAnswerSteps(answersHolds: true), true)
        var reread = 0
        await model.answer(step, done: true, now: Date(timeIntervalSince1970: 1_894_000_000), answered: { reread += 1 })
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["GET /v1/me/handoffs/h1", "POST /v1/me/handoffs/h1/answer"])
        try expectEqual(signed.count, 1)
        // The person confirmed first, in tafs cloud's words for the answer and the step.
        try expectEqual(asked, ["Done · Approve the transfer"])
        try expect(signed[0].hasPrefix("kiff.handoff.v1\nt1\nh1\ndone\n2\n"), signed[0])
        try expectEqual(model.steps, [])
        try expectEqual(reread, 1)
        // Home still lists it until its run hears the answer: it stays off; once Home drops it, it's forgotten.
        model.showSteps([step])
        try expectEqual(model.steps, [])
        model.showSteps([])
        model.showSteps([step])
        try expectEqual(model.steps.map(\.handoff), ["h1"])
    }),
    Test("a step KIFF no longer waits on is never sent, and a 409 says it ended; both leave the list", awaiting: { @MainActor in
        let step = try JSONDecoder().decode(YourStep.self, from: Data(#"{"handoff":"h1"}"#.utf8))
        let (ended, endedTransport) = model([(200, #"{"id":"h1","status":"answered"}"#)])
        ended.showSteps([step])
        await ended.answer(step, done: false)
        try expectEqual(endedTransport.sent.map(\.method), ["GET"])
        try expectEqual(ended.stepNotAnswered, "This step was already answered or has ended.")
        try expectEqual(ended.steps, [])
        let (late, _) = model([(200, #"{"id":"h1"}"#), (409, #"{"error":"handoff_answered"}"#)])
        late.showSteps([step])
        await late.answer(step, done: true)
        try expectEqual(late.stepNotAnswered, "This step was already answered or has ended.")
        try expectEqual(late.steps, [])
        let (refused, _) = model([(200, #"{"id":"h1"}"#), (403, #"{"error":"role_forbidden"}"#)])
        refused.showSteps([step])
        await refused.answer(step, done: true)
        try expectEqual(refused.stepNotAnswered, "Your answer didn't go through. Your role on this account doesn't answer held calls. Someone who approves on it does.")
        try expectEqual(refused.steps.map(\.handoff), ["h1"])
    }),
    Test("the screenshot: a taf's step first on Needs you", awaiting: { @MainActor in
        let step = try JSONDecoder().decode(YourStep.self, from: Data(#"{"handoff":"h1","taf":{"id":"t1","name":"Refunds"},"what":"Approve the transfer to Acme in Qonto","why":"Qonto asks the account's owner to approve transfers over €1,000.","link":"https://app.qonto.com/transfers/1","link_host":"app.qonto.com","words":{"title":"Your step","done":"Done","skip":"Skip it","open":"Open Qonto"}}"#.utf8))
        let (model, _) = model([(200, none)])
        await model.load()
        model.showSteps([step])
        let view = NeedsYouView(model: model, now: Date(timeIntervalSince1970: 1_794_679_800))
            .environment(\.words, Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"]))
        guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 600)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: "build/screenshots"), withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: "build/screenshots/needs-you-step-en.png"))
    }),
    Test("the screenshot: Did this happen? above the calls, said to be answered on the phone", awaiting: { @MainActor in
        let list = #"{"calls":[{"proposal":"p1","title":"Refund a payment","words":"Refund a payment: 40.00 EUR.","status_words":"Its answer was lost, so KIFF can't tell whether it went through."}]}"#
        let (model, _) = model([(200, none), (200, list)])
        await model.load()
        await model.loadUnproven(answersHolds: true)
        let view = NeedsYouView(model: model, now: Date(timeIntervalSince1970: 1_794_679_800))
            .environment(\.words, Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"]))
        guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 600)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: "build/screenshots"), withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: "build/screenshots/needs-you-happened-en.png"))
    }),
    Test("the screenshots: Needs you with a call, and with none, in three languages", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr", "pt"] {
            for (name, body) in [("call", one), ("empty", none)] {
                let (model, _) = model([(200, body)])
                await model.load()
                let tafs = (try? JSONDecoder().decode(Home.Page.self, from: Data(#"{"tafs":[{"name":"Refunds","kiff_agent":"a","color":1,"state":"waiting"}]}"#.utf8)))?.tafs ?? []
                let view = NeedsYouView(model: model, tafs: tafs, now: Date(timeIntervalSince1970: 1_794_679_800))
                    .environment(\.words, Words.load(folder: strings, preferred: [language]))
                guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 800)), let png = Snapshot.png(bitmap) else {
                    throw Failure(description: "no PNG")
                }
                try png.write(to: folder.appendingPathComponent("needs-you-\(name)-\(language).png"))
            }
        }
    }),
    Test("a step isn't signed until the person confirms: a closed prompt keeps it, with the iPad's words", awaiting: { @MainActor in
        let step = try JSONDecoder().decode(YourStep.self, from: Data(stepJSON.utf8))
        let (cancelled, cancelledTransport) = model([(200, #"{"id":"h1"}"#)], confirm: { _ in throw LAError(.userCancel) })
        cancelled.showSteps([step])
        await cancelled.answer(step, done: true)
        try expectEqual(cancelledTransport.sent.map(\.method), ["GET"])
        try expectEqual(cancelled.stepNotAnswered, Words.app("approval.cancelled_nothing_approved_request_kept"))
        try expectEqual(cancelled.steps.map(\.handoff), ["h1"])
        let (failed, failedTransport) = model([(200, #"{"id":"h1"}"#)], confirm: { _ in throw LAError(.authenticationFailed) })
        failed.showSteps([step])
        await failed.answer(step, done: false)
        try expectEqual(failedTransport.sent.map(\.method), ["GET"])
        try expectEqual(failed.stepNotAnswered, Words.app("needs_you.your_step.not_answered_unconfirmed"))
        try expectEqual(failed.steps.map(\.handoff), ["h1"])
    }),
    Test("someone who doesn't answer held calls has no Done or Skip, and an answer sends nothing", awaiting: { @MainActor in
        let step = try JSONDecoder().decode(YourStep.self, from: Data(stepJSON.utf8))
        let viewer = try AccountClient.decoder.decode(Me.self, from: Data(#"{"capabilities":["taf.use"]}"#.utf8))
        let (model, transport) = model([])
        model.showSteps([step])
        try expectEqual(model.canAnswerSteps(answersHolds: viewer.answersHolds), false)
        await model.answer(step, done: true, answersHolds: viewer.answersHolds)
        try expectEqual(transport.sent.count, 0)
        try expectEqual(model.stepNotAnswered, Words.app("needs_you.answer_in_kiff"))
        let keyless = NeedsYouModel(account: AccountClient(transport: CannedTransport([]), session: session), route: .phoneOrPasskey, confirm: { _ in })
        try expectEqual(keyless.canAnswerSteps(answersHolds: true), false)
        await keyless.answer(step, done: true)
        try expectEqual(keyless.stepNotAnswered, Words.app("needs_you.sign_in_again_to_answer"))
    }),
    Test("an answer started before sign-out stops there: nothing is signed or posted after", awaiting: { @MainActor in
        let step = try JSONDecoder().decode(YourStep.self, from: Data(stepJSON.utf8))
        var holder: NeedsYouModel?
        var confirmed = false
        let (model, transport) = model([(200, #"{"id":"h1"}"#), (200, "{}")], confirm: { _ in confirmed = true; await holder?.cancelAnswers() })
        holder = model
        model.showSteps([step])
        model.startAnswer(step, done: true, answersHolds: true)
        for _ in 0..<200 where !confirmed { await Task.yield() }
        for _ in 0..<50 { await Task.yield() }
        try expectEqual(confirmed, true)
        try expectEqual(transport.sent.map(\.method), ["GET"])
        try expectEqual(model.steps.map(\.handoff), ["h1"])
    }),
    Test("KIFF's code is never the why: its error, else its reason, in the iPad's words, else the status's line", awaiting: { @MainActor in
        let step = try JSONDecoder().decode(YourStep.self, from: Data(stepJSON.utf8))
        let (expired, _) = model([(200, #"{"id":"h1"}"#), (403, #"{"error":"handoff_expired"}"#)])
        expired.showSteps([step])
        await expired.answer(step, done: true)
        try expectEqual(expired.stepNotAnswered, "Your answer didn't go through. KIFF didn't take the answer: Your role on this account doesn't allow this.")
        let (reasoned, _) = model([(200, #"{"id":"h1"}"#), (403, #"{"error":"forbidden","reason":"role_forbidden"}"#)])
        reasoned.showSteps([step])
        await reasoned.answer(step, done: true)
        try expectEqual(reasoned.stepNotAnswered, "Your answer didn't go through. Your role on this account doesn't answer held calls. Someone who approves on it does.")
        // KIFF's 401 is "signed out of KIFF", as the iPad's `KIFFError.unauthorized`.
        let (signedOut, _) = model([(200, #"{"id":"h1"}"#), (401, #"{"error":"unauthorized"}"#)])
        signedOut.showSteps([step])
        await signedOut.answer(step, done: true)
        try expectEqual(signedOut.stepNotAnswered, "Your answer didn't go through. KIFF didn't take the answer: Signed out of KIFF. Sign in again.")
    }),
    Test("the answer's message is KIFF's vector byte for byte, and KIFF's signature over it verifies; never for skipped", {
        let message = KIFFMessage.handoff(tenant: "t_vector", handoffID: "ho_0123456789abcdef01234567", answer: "done", signedAt: "2026-11-11T17:00:00Z")
        try expectEqual(message, "kiff.handoff.v1\nt_vector\nho_0123456789abcdef01234567\ndone\n1\n2026-11-11T17:00:00Z")
        try expectEqual(Signing.sha256Hex(Data(message.utf8)), "1b9f7f923489891b736af1fbc494c9348690494d4ae4901844aeb9a0b6df3b6f")
        let key = try P256.Signing.PrivateKey(rawRepresentation: Data(SHA256.hash(data: Data("kiff.handoff.v1 test vector".utf8))))
        try expectEqual(Signing.sha256Hex(key.publicKey.derRepresentation), "85c559569edf864d4b3186426f3541f8bbf8c424d96de17f707b919b2c593970")
        let theirs = "MEUCIQDJLYymcVMzMDhv+kRXK1BS2DhZvJROyBCjJLzzTy5NDgIgXe7a2OeeShmHHI5HazLS+/BzMjLVBYpjX7JT0Uy67RA="
        try expect(Signing.verifies(theirs, over: message, publicKeyDER: key.publicKey.derRepresentation), "KIFF's signature verifies over the app's message")
        let ours = try key.signature(for: Data(message.utf8)).derRepresentation.base64EncodedString()
        try expect(Signing.verifies(ours, over: message, publicKeyDER: key.publicKey.derRepresentation), "one the app makes verifies too")
        let skipped = KIFFMessage.handoff(tenant: "t_vector", handoffID: "ho_0123456789abcdef01234567", answer: "skipped", signedAt: "2026-11-11T17:00:00Z")
        try expect(!Signing.verifies(theirs, over: skipped, publicKeyDER: key.publicKey.derRepresentation), "a signed done never stands for skipped")
        let hold = KIFFMessage.answer(tenant: "t_vector", callID: "ho_0123456789abcdef01234567", answer: .approveOnce, nextStep: nil, accountingVersion: 1, signedAt: "2026-11-11T17:00:00Z")
        try expect(hold != message, "a hold's answer is never a hand-off's")
    }),
    Test("Approve once is offered only with this Mac's key and a call KIFF can approve once; it goes through the key, then the list is read again", awaiting: { @MainActor in
        let (model, transport) = model([(200, one), (200, none)], route: .passkey)
        await model.load()
        guard case .loaded(let calls) = model.state else { throw Failure(description: "not loaded") }
        try expect(!model.offersApproveOnce(calls[0]), "no key, no Approve once")
        var approved: [String] = []
        model.answerWithKey = { call, answer in approved.append(call.id + " " + answer.rawValue) }
        try expect(model.offersApproveOnce(calls[0]), "with the key")
        await model.approveOnce(calls[0])
        try expectEqual(approved, ["exc_1 approve-once"])
        // The key's request is its own (PasskeySession.approveOnce); here the list is read again, never the device key's answer.
        try expectEqual(transport.sent.map(\.path), ["/v1/me/card-exceptions?status=held", "/v1/me/card-exceptions?status=held"])
        try expectEqual(model.state, .loaded([]))
        try expectEqual(model.answering, nil)
    }),
    Test("Approve once: a closed sheet says nothing, Approve on your phone instead says so, and KIFF's refusal is the card's line", awaiting: { @MainActor in
        let (model, _) = model([(200, one)], route: .passkey)
        await model.load()
        guard case .loaded(let calls) = model.state else { throw Failure(description: "not loaded") }
        model.answerWithKey = { _, _ in throw CancellationError() }
        await model.approveOnce(calls[0])
        try expectEqual(NeedsYouView.notTakenLine(model, calls[0]), nil)
        model.answerWithKey = { _, _ in throw ApproveOnPhone() }
        await model.approveOnce(calls[0])
        try expectEqual(NeedsYouView.notTakenLine(model, calls[0]), Words.app("approval.device_can_not_approve_approve"))
        model.answerWithKey = { _, _ in throw KIFFError.refused(status: 403, code: "passkey_not_this_device") }
        await model.approveOnce(calls[0])
        try expectEqual(NeedsYouView.notTakenLine(model, calls[0]), Words.app("needs_you.refused.other", ["why": "passkey_not_this_device"]))
        try expectEqual(model.count, 1)
    }),
    Test("a call KIFF says can't be approved once, or without its accounting version, offers no Approve once", awaiting: { @MainActor in
        let cannot = #"{"exceptions":[{"id":"e1","subject":"a","action":"b","title":"T","created_at":"2026-11-14T18:00:00Z","accounting_version":3,"can_approve_once":false},{"id":"e2","subject":"a","action":"b","title":"T","created_at":"2026-11-14T18:00:00Z"}]}"#
        let (model, _) = model([(200, cannot)], route: .passkey)
        model.answerWithKey = { _, _ in }
        await model.load()
        guard case .loaded(let calls) = model.state else { throw Failure(description: "not loaded") }
        try expectEqual(calls.map { model.offersApproveOnce($0) }, [false, false])
    }),
    Test("Extra room goes through the key only over a total, for someone who manages the Cards; a next step refuses with it", awaiting: { @MainActor in
        let over = #"{"exceptions":[{"id":"e1","subject":"a","action":"b","title":"T","created_at":"2026-11-14T18:00:00Z","accounting_version":3,"can_approve_once":false,"next_steps":["Return first"]}]}"#
        let (model, transport) = model([(200, over), (200, none), (200, "{}"), (200, none)], route: .passkey)
        await model.load()
        guard case .loaded(let calls) = model.state else { throw Failure(description: "not loaded") }
        try expect(!model.offersExtraRoom(calls[0], managesCards: true), "no key, no Extra room")
        var asked: [String] = []
        model.answerWithKey = { call, answer in asked.append(call.id + " " + answer.rawValue) }
        try expect(model.offersExtraRoom(calls[0], managesCards: true), "the manager, with the key")
        try expect(!model.offersExtraRoom(calls[0], managesCards: false), "not for someone who doesn't manage the Cards")
        try expect(!model.offersApproveOnce(calls[0]), "approving once can't pass a total")
        await model.extraRoom(calls[0])
        try expectEqual(asked, ["e1 change-card"])
        // A next step is the device key's refusal, with the step: never the security key's.
        await model.refuse(calls[0], nextStep: "Return first")
        try expectEqual(asked, ["e1 change-card"])
        try expectEqual(transport.sent.map(\.path).filter { $0.hasSuffix("/reject") }, ["/v1/me/card-exceptions/e1/reject"])
    }),
    Test("a held step that fills a field in Chrome offers no Approve once and no Extra room on this Mac: the phone's release", awaiting: { @MainActor in
        let fill = #"{"exceptions":[{"id":"f1","subject":"a","action":"browser.act","title":"Fill a saved sign-in","created_at":"2026-11-14T18:00:00Z","accounting_version":3,"browser":{"site":"shop.example","sealed_fill":{"sealed":"h"}}},{"id":"f2","subject":"a","action":"browser.act","title":"T","created_at":"2026-11-14T18:00:00Z","accounting_version":3,"can_approve_once":false,"browser":{"fill":{"field_ref":"x"}}}]}"#
        let (model, transport) = model([(200, fill)], route: .passkey)
        var asked: [String] = []
        model.answerWithKey = { call, answer in asked.append(call.id + " " + answer.rawValue) }
        await model.load()
        guard case .loaded(let calls) = model.state else { throw Failure(description: "not loaded") }
        try expectEqual(calls.map(\.fillsInChrome), [true, true])
        try expect(!model.offersApproveOnce(calls[0]), "no Approve once for a fill")
        try expect(!model.offersExtraRoom(calls[1], managesCards: true), "no Extra room for a fill")
        // Even asked directly, nothing is asked of the key or sent, and the card says to approve on the phone.
        await model.approveOnce(calls[0])
        await model.extraRoom(calls[1])
        try expectEqual(asked, [])
        try expectEqual(transport.sent.count, 1)
        try expectEqual(NeedsYouView.notTakenLine(model, calls[0]), Words.app("approval.device_can_not_approve_approve"))
    }),
    Test("Allow this from now on: offered only when live, read on the tap, one key approval for the Card, then the call's own Approve once", awaiting: { @MainActor in
        let held = #"{"exceptions":[{"id":"ce_9","subject":"refunds-1","action":"create_refund","title":"Refund a payment","created_at":"2026-11-14T18:00:00Z","accounting_version":3,"breaches":[{"outcome":"per_action_exceeded"}]}]}"#
        let cap = #"{"quantity":"amount","max":15000,"unit":"EUR","scale":2}"#
        let draft = #"{"id":"dr_9","agent_id":"refunds-1","status":"draft","version":"v7","cards":[{"revises":"c1","grants":[{"action":"create_refund","per_action_max":[\#(cap.replacingOccurrences(of: "15000", with: "32000"))]}],"current":{"grants":[{"action":"create_refund","per_action_max":[\#(cap)]}]}}]}"#
        let offer = #"{"offer":{"changes":[{"mandate_id":"c1","kind":"per_action","before":15000,"after":32000,"unit":"EUR","words_before":"Refunds up to €150 each","words_after":"Refunds up to €320 each"}],"draft":"dr_9","send_held":true}}"#
        let transport = CannedTransport([(200, held), (200, offer), (200, draft), (200, held), (200, none)])
        let account = AccountClient(transport: transport, session: session, signMessage: { _ in "SIG" })
        let model = NeedsYouModel(account: account, route: .passkey, cloud: CloudClient(transport: transport, session: session))
        await model.load()
        guard case .loaded(let calls) = model.state, let call = calls.first else { throw Failure(description: "not loaded") }
        try expect(!model.offersAllow(call, taf: "taf_1", managesCards: true, allowIsLive: true), "no key, no Allow")
        var signed: [KeyAct] = [], answered: [String] = []
        model.approveWithKey = { act, _ in signed.append(act); return Data() }
        model.answerWithKey = { call, answer in answered.append(call.id + " " + answer.rawValue) }
        try expect(!model.offersAllow(call, taf: "taf_1", managesCards: true, allowIsLive: false), "not live yet")
        try expect(!model.offersAllow(call, taf: "taf_1", managesCards: false, allowIsLive: true), "not someone who manages the Cards")
        try expect(!model.offersAllow(call, taf: nil, managesCards: true, allowIsLive: true), "a taf tafs cloud doesn't hold")
        try expect(model.offersAllow(call, taf: "taf_1", managesCards: true, allowIsLive: true), "offered")
        // The tap: tafs cloud's offer, then KIFF's draft, read here.
        model.allow = AllowSheet(call: call, taf: "taf_1", busy: true)
        let r1 = await model.loadAllow(round: false)
        try expect(r1, "the draft is what was offered")
        try expectEqual(model.allow?.sendHeld, true)
        // One approval on the key: KIFF's plain draft confirm. Then the list again, and the call's own Approve once.
        let r2 = await model.confirmAllow()
        try expect(r2, "confirmed")
        try expectEqual(signed, [.confirmDraft(id: "dr_9", version: "v7")])
        try expectEqual(answered, ["ce_9 approve-once"])
        try expectEqual(model.allow, nil)
        try expectEqual(transport.sent.map { "\($0.method) \($0.path)" },
                        ["GET /v1/me/card-exceptions?status=held", "POST /v1/tafs/taf_1/holds/ce_9/allow", "GET /v1/me/agent-drafts/dr_9",
                         "GET /v1/me/card-exceptions?status=held", "GET /v1/me/card-exceptions?status=held"])
    }),
    Test("Allow this from now on signs nothing for a draft that isn't what was offered, and with the switch off the call still waits", awaiting: { @MainActor in
        let held = #"{"exceptions":[{"id":"ce_9","subject":"refunds-1","action":"create_refund","title":"T","created_at":"2026-11-14T18:00:00Z","accounting_version":3,"breaches":[{"outcome":"per_action_exceeded"}]}]}"#
        let cap = #"{"quantity":"amount","max":15000,"unit":"EUR","scale":2}"#
        let offer = #"{"offer":{"changes":[{"mandate_id":"c1","kind":"per_action","before":15000,"after":32000,"unit":"EUR"}],"draft":"dr_9"}}"#
        func draft(_ max: Int) -> String {
            #"{"id":"dr_9","agent_id":"refunds-1","status":"draft","version":"v7","cards":[{"revises":"c1","grants":[{"action":"create_refund","per_action_max":[\#(cap.replacingOccurrences(of: "15000", with: String(max)))]}],"current":{"grants":[{"action":"create_refund","per_action_max":[\#(cap)]}]}}]}"#
        }
        let transport = CannedTransport([(200, held), (200, offer), (200, draft(50000)), (200, offer), (200, draft(32000)), (200, held)])
        let account = AccountClient(transport: transport, session: session, signMessage: { _ in "SIG" })
        let model = NeedsYouModel(account: account, route: .passkey, cloud: CloudClient(transport: transport, session: session))
        var signed: [KeyAct] = [], answered: [String] = []
        model.approveWithKey = { act, _ in signed.append(act); return Data() }
        model.answerWithKey = { call, answer in answered.append(call.id + " " + answer.rawValue) }
        await model.load()
        guard case .loaded(let calls) = model.state, let call = calls.first else { throw Failure(description: "not loaded") }
        model.allow = AllowSheet(call: call, taf: "taf_1", busy: true)
        let r3 = await model.loadAllow(round: false)
        try expect(!r3, "another figure isn't what was offered")
        let r4 = await model.confirmAllow()
        try expect(!r4, "nothing to sign")
        try expectEqual(signed, [])
        // Rounded and read again: now it matches. The switch off: the Card changes, and the call keeps waiting.
        let r5 = await model.loadAllow(round: true)
        try expect(r5, "the rounded draft")
        try expectEqual(model.allow?.rounded, true)
        model.allow?.sendHeld = false
        let r6 = await model.confirmAllow()
        try expect(r6, "confirmed")
        try expectEqual(signed, [.confirmDraft(id: "dr_9", version: "v7")])
        try expectEqual(answered, [])
    }),
]

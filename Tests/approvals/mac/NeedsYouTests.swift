import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")
private let one = #"{"exceptions":[{"id":"exc_1","subject":"a","action":"stripe.refund","title":"Refund a payment","reason_text":"€640 is over its €500 limit.","taf_about":"Dispute #4825","taf_reason":"The customer was charged twice.","created_at":"2026-11-14T18:00:00Z","expires_at":"2026-11-14T18:42:00Z","accounting_version":3,"parameters":{"amount":64000},"parameter_units":{"amount":{"unit":"EUR","scale":2}}}]}"#
private let none = #"{"exceptions":[]}"#

@MainActor
private func model(_ answers: [(Int, String)], route: ApprovalRoute = .phoneOrPasskey) -> (NeedsYouModel, CannedTransport) {
    let transport = CannedTransport(answers)
    let account = AccountClient(transport: transport, session: session, signMessage: { _ in "SIG" })
    return (NeedsYouModel(account: account, route: route), transport)
}

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
        try expectEqual(model.notTaken["exc_1"], "approver_only")
        try expectEqual(model.count, 1)
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
        let model = NeedsYouModel(account: account, route: .phoneOrPasskey)
        model.showSteps([step])
        try expectEqual(model.canAnswerSteps, true)
        var reread = 0
        await model.answer(step, done: true, now: Date(timeIntervalSince1970: 1_894_000_000), answered: { reread += 1 })
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["GET /v1/me/handoffs/h1", "POST /v1/me/handoffs/h1/answer"])
        try expectEqual(signed.count, 1)
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
]

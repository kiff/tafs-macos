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

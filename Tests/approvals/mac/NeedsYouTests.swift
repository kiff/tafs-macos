import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")
private let one = #"{"exceptions":[{"id":"exc_1","subject":"a","action":"stripe.refund","title":"Refund a payment","reason_text":"€640 is over its €500 limit.","taf_about":"Dispute #4825","taf_reason":"The customer was charged twice.","created_at":"2026-11-14T18:00:00Z","expires_at":"2026-11-14T18:42:00Z","accounting_version":3}]}"#
private let none = #"{"exceptions":[]}"#

@MainActor
private func model(_ answers: [(Int, String)], route: ApprovalRoute = .phoneOrPasskey) -> (NeedsYouModel, CannedTransport) {
    let transport = CannedTransport(answers)
    let account = AccountClient(transport: transport, session: session, signMessage: { _ in "SIG" })
    return (NeedsYouModel(account: account, route: route), transport)
}

let approvalsScreenTests: [Test] = [
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
    Test("the screenshots: Needs you with a call, and with none, in three languages", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr", "pt"] {
            for (name, body) in [("call", one), ("empty", none)] {
                let (model, _) = model([(200, body)])
                await model.load()
                let view = NeedsYouView(model: model, now: Date(timeIntervalSince1970: 1_794_679_800))
                    .environment(\.words, Words.load(folder: strings, preferred: [language]))
                guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 800)), let png = Snapshot.png(bitmap) else {
                    throw Failure(description: "no PNG")
                }
                try png.write(to: folder.appendingPathComponent("needs-you-\(name)-\(language).png"))
            }
        }
    }),
]

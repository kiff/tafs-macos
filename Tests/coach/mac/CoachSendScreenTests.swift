import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let before = #"{"working":false,"items":[{"type":"message","message":{"id":"m1","from":"taf","text":"What should your taf do?"}}]}"#
private let working = #"{"working":true,"items":[{"type":"message","message":{"id":"m1","from":"taf","text":"What should your taf do?"}},{"type":"message","message":{"id":"m9","from":"owner","text":"Connect Qonto"}}]}"#
private let answered = #"{"working":false,"items":[{"type":"message","message":{"id":"m1","from":"taf","text":"What should your taf do?"}},{"type":"message","message":{"id":"m9","from":"owner","text":"Connect Qonto"}},{"type":"message","message":{"id":"m10","from":"taf","text":"Done."}}]}"#

/// 2026-11-14T18:00:00Z, when the tests' person sends.
private let sendTime = Date(timeIntervalSince1970: 1_794_679_200)

@MainActor
private func make(_ answers: [(Int, String)]) async -> (CoachModel, CannedTransport, () -> [TimeInterval]) {
    let transport = CannedTransport([(200, setupAnswer), (200, before)] + answers)
    var slept: [TimeInterval] = []
    let model = CoachModel(cloud: CloudClient(transport: transport, session: session), sleep: { slept.append($0) }, now: { sendTime })
    await model.load()
    return (model, transport, { slept })
}

let coachSendMacTests: [Test] = [
    Test("a sent message stays in view until the thread has it, and the thread is followed until Coach is done", awaiting: { @MainActor in
        let (model, transport, slept) = await make([(200, sentAnswer), (200, working), (200, answered)])
        model.draft = "  Connect Qonto "
        try expectEqual(model.canSend, true)
        await model.send()
        try expectEqual(model.draft, "")
        try expectEqual(model.pending, nil)
        try expectEqual(transport.sent.map(\.method), ["GET", "GET", "POST", "GET", "GET"])
        try expectEqual(slept(), [4])
        guard case .loaded(_, let page) = model.state else { throw Failure(description: "not loaded") }
        try expectEqual(page.items.count, 3)
        try expectEqual(page.working, false)
    }),
    Test("following stops after 30 reads when no answer comes", awaiting: { @MainActor in
        let (model, transport, slept) = await make([(200, sentAnswer)] + Array(repeating: (200, working), count: 40))
        model.draft = "Connect Qonto"
        await model.send()
        try expectEqual(transport.sent.filter { $0.path.hasSuffix("/conversation") }.count, 1 + CoachModel.followAtMost)
        try expectEqual(slept().count, CoachModel.followAtMost)
    }),
    Test("nothing is sent for an empty box, or while the last message is still going", awaiting: { @MainActor in
        let (model, transport, _) = await make([])
        for text in ["", "   "] {
            model.draft = text
            try expectEqual(model.canSend, false)
            await model.send()
        }
        try expectEqual(transport.sent.filter { $0.method == "POST" }.count, 0)
    }),
    Test("a message that didn't go stays with tafs cloud's reason, and Retry sends the same words", awaiting: { @MainActor in
        let (model, transport, _) = await make([(409, #"{"error":"halted","words":"Halted: nothing runs until it's resumed."}"#), (200, before), (200, sentAnswer), (200, answered)])
        model.draft = "Connect Qonto"
        await model.send()
        try expectEqual(model.pending, CoachModel.Pending(text: "Connect Qonto", at: sendTime, failed: "Halted: nothing runs until it's resumed.", id: nil))
        await model.retry()
        try expectEqual(model.pending, nil)
        let posts = transport.sent.filter { $0.method == "POST" }
        try expectEqual(posts.count, 2)
        try expectEqual(posts[0].body, posts[1].body)
    }),
    Test("AI use is asked for in tafs cloud's words; Allow sends the version read, then the message", awaiting: { @MainActor in
        let (model, transport, _) = await make([(403, consentRefusal), (200, "{}"), (200, sentAnswer), (200, answered)])
        model.draft = "Connect Qonto"
        await model.send()
        try expectEqual(model.consent?.words.title, "Your data and the AI")
        try expectEqual(transport.sent.filter { $0.method == "POST" }.map(\.path), ["/v1/tafs/taf-coach/messages"])
        await model.allowAI()
        try expectEqual(model.consent, nil)
        try expectEqual(transport.sent.filter { $0.method == "POST" }.map(\.path),
                        ["/v1/tafs/taf-coach/messages", "/v1/me/ai-consent", "/v1/tafs/taf-coach/messages"])
        try expectEqual(try JSONDecoder().decode([String: String].self, from: transport.sent[3].body), ["version": "3"])
        try expectEqual(model.pending, nil)
    }),
    Test("no key gives the AI consent: Return answers nothing, and Esc is Not now") {
        try expect(ConsentKeys.allow == nil, "Allow has no key")
        try expect(ConsentKeys.notNow == .cancelAction, "Esc is Not now")
        try expect(ConsentKeys.notNow != .defaultAction, "Return is not Not now either")
    },
    Test("a sheet that closes late after Allow doesn't mark the message in flight as failed", awaiting: { @MainActor in
        // After Allow the message is taken, but the thread doesn't have it yet.
        let (model, transport, _) = await make([(403, consentRefusal), (200, "{}"), (200, sentAnswer)] + Array(repeating: (200, before), count: 31))
        model.draft = "Connect Qonto"
        await model.send()
        await model.allowAI()
        try expectEqual(model.pending?.failed, nil)
        try expectEqual(model.pending?.id, "m9")
        model.declineAI()
        try expectEqual(model.pending?.failed, nil)
        try expectEqual(transport.sent.filter { $0.method == "POST" }.count, 3)
        await model.retry()
        try expectEqual(transport.sent.filter { $0.method == "POST" }.count, 3)
    }),
    Test("Retry after a lost answer sends nothing twice: the thread already has the message", awaiting: { @MainActor in
        let arrived = #"{"working":false,"items":[{"type":"message","message":{"id":"m9","at":"2026-11-14T18:00:02Z","from":"owner","text":"Connect Qonto"}},{"type":"message","message":{"id":"m10","at":"2026-11-14T18:00:30Z","from":"taf","text":"Done."}}]}"#
        let (model, transport, _) = await make([(504, ""), (200, arrived)])
        model.draft = "Connect Qonto"
        await model.send()
        // tafs cloud sent no words or error: its status line, as the iPad's CloudError.
        try expectEqual(model.pending?.failed, "tafs cloud answered 504")
        await model.retry()
        try expectEqual(model.pending, nil)
        try expectEqual(transport.sent.filter { $0.method == "POST" }.count, 1)
        guard case .loaded(_, let page) = model.state else { throw Failure(description: "not loaded") }
        try expectEqual(page.items.count, 2)
    }),
    Test("the same words sent before this try, or by Coach, don't stop a Retry", awaiting: { @MainActor in
        let old = #"{"working":false,"items":[{"type":"message","message":{"id":"m0","at":"2026-11-14T17:00:00Z","from":"owner","text":"Connect Qonto"}}]}"#
        let (model, transport, _) = await make([(504, ""), (200, old), (200, sentAnswer), (200, answered)])
        model.draft = "Connect Qonto"
        await model.send()
        await model.retry()
        try expectEqual(transport.sent.filter { $0.method == "POST" }.count, 2)
        let page = try JSONDecoder().decode(Thread.Page.self, from: Data(#"{"items":[{"type":"message","message":{"at":"2026-11-14T18:00:05Z","from":"taf","text":"Connect Qonto"}}]}"#.utf8))
        try expectEqual(page.hasPersonsLast("Connect Qonto", since: sendTime), false)
    }),
    Test("Not now allows nothing and sends nothing more; the message stays unsent", awaiting: { @MainActor in
        let (model, transport, _) = await make([(403, consentRefusal)])
        model.draft = "Connect Qonto"
        await model.send()
        model.declineAI()
        try expectEqual(model.consent, nil)
        try expectEqual(model.pending?.failed, "")
        try expectEqual(transport.sent.filter { $0.method == "POST" }.count, 1)
        try expect(!transport.sent.contains { $0.path == "/v1/me/ai-consent" }, "no consent was sent")
    }),
]

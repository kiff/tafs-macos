import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let before = #"{"working":false,"items":[{"type":"message","message":{"id":"m1","from":"taf","text":"What should your taf do?"}}]}"#
private let after = #"{"working":false,"items":[{"type":"message","message":{"id":"m1","from":"taf","text":"What should your taf do?"}},{"type":"message","message":{"id":"m9","at":"2026-11-14T18:00:01Z","from":"owner","text":"Connect Qonto"}},{"type":"message","message":{"id":"m10","from":"taf","text":"I can connect Qonto with its key."}}]}"#
private let sendTime = Date(timeIntervalSince1970: 1_794_679_200)

/// Gives canned lines, or fails to open, and keeps what it was asked.
private final class CannedStream: LineStream, @unchecked Sendable {
    enum Plan { case lines([String]), refuse(Int, String), cannotOpen, breaksAfter([String]) }
    let plan: Plan
    private(set) var asked: [HTTPRequest] = []
    init(_ plan: Plan) { self.plan = plan }

    func lines(_ request: HTTPRequest) async throws -> AsyncThrowingStream<String, Error> {
        asked.append(request)
        switch plan {
        case .refuse(let status, let body): throw CloudRefusal(status: status, body: Data(body.utf8))
        case .cannotOpen: throw URLError(.cannotConnectToHost)
        case .lines(let lines):
            return AsyncThrowingStream { c in lines.forEach { c.yield($0) }; c.finish() }
        case .breaksAfter(let lines):
            return AsyncThrowingStream { c in lines.forEach { c.yield($0) }; c.finish(throwing: URLError(.networkConnectionLost)) }
        }
    }
}

/// Streams that stay open until the test ends them, one per message, as a slow answer does.
private final class HeldStream: LineStream, @unchecked Sendable {
    private(set) var asked: [HTTPRequest] = []
    private(set) var open: [AsyncThrowingStream<String, Error>.Continuation] = []

    func lines(_ request: HTTPRequest) async throws -> AsyncThrowingStream<String, Error> {
        asked.append(request)
        return AsyncThrowingStream { self.open.append($0) }
    }
}

/// A wait that lasts until the test lets it go, as a follow's pause does.
private final class HeldSleep: @unchecked Sendable {
    private(set) var waiting: [CheckedContinuation<Void, Never>] = []
    func sleep(_ seconds: TimeInterval) async { await withCheckedContinuation { waiting.append($0) } }
}

@MainActor
private func make(_ plan: CannedStream.Plan, _ answers: [(Int, String)]) async -> (CoachModel, CannedTransport, CannedStream) {
    let transport = CannedTransport([(200, setupAnswer), (200, noChats), (200, before)] + answers)
    let stream = CannedStream(plan)
    let model = CoachModel(cloud: CloudClient(transport: transport, session: session), streamer: stream, sleep: { _ in }, now: { sendTime })
    await model.load()
    model.draft = "Connect Qonto"
    return (model, transport, stream)
}

private func posts(_ transport: CannedTransport) -> Int { transport.sent.filter { $0.method == "POST" }.count }

let coachStreamMacTests: [Test] = [
    Test("the answer is written as it comes, then the thread has it and nothing is sent plainly", awaiting: { @MainActor in
        // One read for the held call the stream names, one when it ends.
        let (model, transport, stream) = await make(.lines(streamLines), [(200, after), (200, after)])
        var seen: [String] = []
        let watching = model.$live.sink { if let text = $0?.text, !text.isEmpty, seen.last != text { seen.append(text) } }
        await model.send()
        watching.cancel()
        try expectEqual(seen, ["I can connect ", "I can connect Qonto with its key."])
        try expectEqual(stream.asked.count, 1)
        try expectEqual(stream.asked[0].path, "/v1/tafs/taf-coach/messages/stream")
        try expectEqual(posts(transport), 0)
        try expectEqual(model.live, nil)
        try expectEqual(model.pending, nil)
        guard case .loaded(_, let page) = model.state else { throw Failure(description: "not loaded") }
        try expectEqual(page.items.count, 3)
    }),
    Test("a stream that can't open sends the message plainly, once", awaiting: { @MainActor in
        let (model, transport, _) = await make(.cannotOpen, [(200, before), (200, sentAnswer), (200, after)])
        await model.send()
        try expectEqual(posts(transport), 1)
        try expectEqual(model.pending, nil)
    }),
    Test("if the stream couldn't open but tafs cloud has the message, nothing is sent again", awaiting: { @MainActor in
        let (model, transport, _) = await make(.cannotOpen, [(200, after), (200, after)])
        await model.send()
        try expectEqual(posts(transport), 0)
        try expectEqual(model.pending, nil)
    }),
    Test("a stream that breaks after tafs cloud took the message is never sent again", awaiting: { @MainActor in
        let (model, transport, _) = await make(.breaksAfter(Array(streamLines.prefix(8))), [(200, after)])
        await model.send()
        try expectEqual(posts(transport), 0)
        try expectEqual(model.live, nil)
        try expectEqual(model.pending, nil)
    }),
    Test("a stream that opened, then dropped before its first event, is never sent plainly", awaiting: { @MainActor in
        // A 200, a keep-alive comment and a blank line, then the connection is lost; the
        // thread doesn't show the message yet.
        let (model, transport, _) = await make(.breaksAfter([": keep-alive", ""]), Array(repeating: (200, before), count: 31))
        await model.send()
        try expectEqual(posts(transport), 0)
        try expectEqual(model.live, nil)
        // And it isn't left as unsent with a Retry: a Retry now sends nothing either.
        try expectEqual(model.pending, nil)
        await model.retry()
        try expectEqual(posts(transport), 0)
        let (empty, sent, _) = await make(.breaksAfter([]), [(200, after)])
        await empty.send()
        try expectEqual(posts(sent), 0)
    }),
    Test("a refusal on the stream is the same as on the plain route: consent is asked, and nothing else is sent", awaiting: { @MainActor in
        let (model, transport, _) = await make(.refuse(403, consentRefusal), [])
        await model.send()
        try expectEqual(model.consent?.version, "3")
        try expectEqual(posts(transport), 0)
        let (halted, sent, _) = await make(.refuse(409, #"{"error":"halted","words":"Halted: nothing runs until it's resumed."}"#), [])
        await halted.send()
        try expectEqual(halted.pending?.failed, "Halted: nothing runs until it's resumed.")
        try expectEqual(posts(sent), 0)
    }),
    Test("a run that stops with a reason shows tafs cloud's words for it", awaiting: { @MainActor in
        let lines = ["event: session", #"data: {"session":"s1","message":{"id":"m9"}}"#,
                     "event: end", #"data: {"status":"ERROR","code":"ai_unavailable","words":"The AI isn't answering just now. None of your credits were used."}"#]
        let (model, _, _) = await make(.lines(lines), [(200, after)])
        await model.send()
        try expectEqual(model.stopped, "The AI isn't answering just now. None of your credits were used.")
    }),
    Test("a new conversation cancels the answer streaming in the one before, which then touches nothing of the new one", awaiting: { @MainActor in
        let transport = CannedTransport([(200, setupAnswer), (200, noChats), (200, before)])
        let stream = HeldStream()
        let model = CoachModel(cloud: CloudClient(transport: transport, session: session), streamer: stream, sleep: { _ in }, now: { sendTime })
        await model.load()
        model.draft = "Connect Qonto"
        let first = Task { await model.send() }
        while stream.open.isEmpty { await Task.yield() }
        for line in ["event: session", #"data: {"session":"s1","new_session":false,"message":{"id":"m9"}}"#, "", "event: text", #"data: {"text":"I can "}"#, ""] {
            stream.open[0].yield(line)
        }
        for _ in 0..<20 { await Task.yield() }
        try expectEqual(model.live?.text, "I can ")
        model.newChat()
        // The stream before was cancelled: its send ends without reading anything more.
        await first.value
        try expectEqual(model.live, nil)
        let read = transport.sent.count
        model.draft = "And Gmail"
        let second = Task { await model.send() }
        while stream.open.count < 2 { await Task.yield() }
        // The old stream's end, late: nothing of the new conversation is touched.
        stream.open[0].finish()
        for _ in 0..<20 { await Task.yield() }
        try expectEqual(model.pending?.text, "And Gmail")
        try expectEqual(model.pending?.failed, nil)
        try expectEqual(transport.sent.count, read)
        let body = try JSONSerialization.jsonObject(with: stream.asked[1].body) as? NSDictionary
        try expectEqual(body, ["text": "And Gmail", "new_chat": true, "new_chat_after_handover": true])
        stream.open[1].finish()
        await second.value
    }),
    Test("an answer followed past its end leaves the next conversation's message alone, as the iPad's followSetupStream", awaiting: { @MainActor in
        let working = #"{"working":true,"items":[{"type":"message","message":{"id":"m9","from":"owner","text":"Connect Qonto"}}]}"#
        let transport = CannedTransport([(200, setupAnswer), (200, noChats), (200, before), (200, working)])
        let stream = HeldStream()
        let held = HeldSleep()
        let model = CoachModel(cloud: CloudClient(transport: transport, session: session), streamer: stream, sleep: { await held.sleep($0) }, now: { sendTime })
        await model.load()
        model.draft = "Connect Qonto"
        let first = Task { await model.send() }
        while stream.open.isEmpty { await Task.yield() }
        for line in ["event: session", #"data: {"session":"s1","new_session":false,"message":{"id":"m9"}}"#, ""] { stream.open[0].yield(line) }
        // The stream ends while the thread still says Coach is at work: the answer is followed,
        // and its follow waits.
        stream.open[0].finish()
        while held.waiting.isEmpty { await Task.yield() }
        model.newChat()
        model.draft = "And Gmail"
        let second = Task { await model.send() }
        while stream.open.count < 2 { await Task.yield() }
        try expectEqual(model.pending?.text, "And Gmail")
        // The old follow goes on: it touches nothing of the new conversation.
        held.waiting.forEach { $0.resume() }
        await first.value
        try expectEqual(model.pending?.text, "And Gmail")
        try expectEqual(model.pending?.failed, nil)
        stream.open[1].finish()
        for _ in 0..<50 { await Task.yield() }
        held.waiting.dropFirst().forEach { $0.resume() }
        await second.value
    }),
]

import Foundation

/// One event of a run as tafs cloud streams it (kiff/tafs's docs/chat.md, "The answer as it
/// comes"). tafs cloud trims the stream to what an app shows: tool inputs and results never
/// come, and the model's thinking is never drawn.
enum StreamEvent: Equatable {
    /// First: the person's message as the thread names it, to match the send by id.
    case session(message: String?)
    /// More of the answer.
    case text(String)
    /// tafs cloud's word for where the run is ("Working…" lines), when it sends one.
    case state(words: String?)
    /// A step begins, in tafs cloud's words ("Asking KIFF: List payments…"), by its call.
    case activity(words: String?, call: String?)
    /// A step ended, by its call: `done`, `error` or `not_made` (refused back unmade); with
    /// tafs cloud's one line of why when it failed.
    case step(call: String?, status: String, why: String?)
    /// Something the thread now has that the stream doesn't carry: a held call, a card, a
    /// message the run read, a run that went on. The thread is read again.
    case threadChanged
    /// The run stopped; with tafs cloud's words when it stopped with a code.
    case end(words: String?)
    /// The stream broke: the thread has the rest.
    case broke

    /// An event from its name and its line of JSON; nil for one this app doesn't draw.
    static func read(_ name: String, _ json: String) -> StreamEvent? {
        let o = ((try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]) ?? [:]
        func line(_ key: String) -> String? {
            guard let value = o[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        switch name {
        case "session": return .session(message: (o["message"] as? [String: Any])?["id"] as? String)
        case "text": return (o["text"] as? String).map(StreamEvent.text)
        case "state": return .state(words: line("words"))
        case "activity": return .activity(words: line("step"), call: line("call_id"))
        case "step":
            // An older tafs cloud says only `failed`.
            let status = line("status") ?? ((o["failed"] as? Bool ?? false) ? "error" : "done")
            return .step(call: line("call_id"), status: status, why: line("why"))
        case "held", "taken", "component", "part": return .threadChanged
        case "end": return .end(words: line("words"))
        case "error": return .broke
        default: return nil
        }
    }
}

/// Reads a server-sent stream line by line: `event:` names what the next `data:` line is.
struct EventReader {
    private var name = "message"

    mutating func read(_ line: String) -> StreamEvent? {
        if line.hasPrefix("event:") {
            name = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            return nil
        }
        guard line.hasPrefix("data:") else { return nil }
        return StreamEvent.read(name, String(line.dropFirst(5)))
    }
}

/// The answer being written, for the chat to draw under the person's message.
struct LiveAnswer: Equatable {
    /// Coach's words so far.
    private(set) var text = ""
    /// The one line of where the run is: tafs cloud's state words, else the step at work.
    /// Nil before either: the chat then says "Thinking…".
    private(set) var line: String?
    /// The latest step that failed, in tafs cloud's one line.
    private(set) var trouble: String?
    /// The steps so far, in tafs cloud's words: the list under the live line.
    private(set) var steps: [Step] = []

    struct Step: Equatable {
        let words: String
        /// The call it is, as tafs cloud names it: what its end is matched by.
        var call: String? = nil
        var done = false
        var failed = false
        /// Refused back unmade: nothing reached KIFF or the app. Not a failure, and not done.
        var notMade = false
    }
    /// The longest answer kept while it is written; the thread has it whole.
    static let longest = 200_000

    /// A live step's words as the finished list has them: without the trailing "…".
    static func plain(_ words: String) -> String {
        var out = words.trimmingCharacters(in: .whitespacesAndNewlines)
        while out.hasSuffix("…") || out.hasSuffix(".") && out.hasSuffix("...") { out = String(out.dropLast(out.hasSuffix("…") ? 1 : 3)) }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Takes one event. Answers whether the thread must be read again now.
    mutating func take(_ event: StreamEvent) -> Bool {
        switch event {
        case .text(let more):
            if text.count < Self.longest { text += more }
        case .state(let words):
            if let words { line = words }
        case .activity(let words, let call):
            line = words
            // A step with no words has no line, and isn't listed.
            if let words, steps.count < 200 { steps.append(Step(words: Self.plain(words), call: call)) }
        case .step(let call, let status, let why):
            let failed = status == "error"
            if failed { trouble = why }
            // The step that ended is the one with its call: calls may overlap, and a step with no
            // words ends without touching a listed one. With no call named, the last open one.
            let open: Int?
            if let call {
                open = steps.lastIndex { $0.call == call && !$0.done && !$0.notMade }
            } else {
                open = steps.lastIndex { !$0.done && !$0.notMade }
            }
            if let open {
                if status == "not_made" {
                    steps[open].notMade = true
                } else {
                    steps[open].done = true
                    steps[open].failed = failed
                }
            }
        case .threadChanged:
            return true
        case .session, .end, .broke:
            break
        }
        return false
    }
}

/// What opens a stream to tafs cloud: the network in the app, canned lines in tests. It
/// throws `CloudRefusal` when tafs cloud answers anything but 200.
protocol LineStream {
    func lines(_ request: HTTPRequest) async throws -> AsyncThrowingStream<String, Error>
}

extension CloudClient {
    /// The request that sends a message with its answer streamed. Nil when what was typed
    /// isn't a message.
    func streamRequest(_ typed: String, to taf: String) -> HTTPRequest? {
        guard let text = Outgoing.text(typed) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let body = try? encoder.encode(["text": text]) else { return nil }
        return HTTPRequest(method: "POST", path: "/v1/tafs/\(Self.escaped(taf))/messages/stream", headers: [
            "Authorization": "Bearer \(session.accessToken)", "Accept": "text/event-stream", "Content-Type": "application/json",
            "Accept-Language": language, "User-Agent": "tafs-macos",
        ], body: body)
    }
}

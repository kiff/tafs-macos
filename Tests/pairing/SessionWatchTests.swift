import Foundation

private final class Count: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func add() { lock.lock(); value += 1; lock.unlock() }
    var times: Int { lock.lock(); defer { lock.unlock() }; return value }
}

private let bearer = ["Authorization": "Bearer tok"]

let pairingSessionWatchTests: [Test] = [
    Test("a read with the session that's refused with 401 ends it, once", awaiting: {
        let count = Count()
        let watch = SessionWatch(token: "tok") { count.add() }
        let transport = WatchedTransport(inner: CannedTransport([(401, #"{"error":"unauthorized"}"#), (401, "{}"), (401, "{}")]), watch: watch)
        let first = try await transport.send(HTTPRequest(method: "GET", path: "/v1/me", headers: bearer))
        try expectEqual(first.status, 401) // the answer goes on as it came
        _ = try await transport.send(HTTPRequest(method: "GET", path: "/v1/home", headers: bearer))
        _ = try await transport.exchange(HTTPRequest(method: "GET", path: "/v1/me/card-exceptions", headers: bearer))
        try expectEqual(count.times, 1) // sign-in opens once, however many reads are refused
        try expect(watch.hasEnded)
    }),
    Test("anything else leaves the session as it is", awaiting: {
        let count = Count()
        let watch = SessionWatch(token: "tok") { count.add() }
        let transport = WatchedTransport(inner: CannedTransport([(200, "{}"), (403, "{}"), (503, "{}"), (401, "{}"), (401, "{}")]), watch: watch)
        _ = try await transport.send(HTTPRequest(method: "GET", path: "/v1/me", headers: bearer))
        _ = try await transport.send(HTTPRequest(method: "GET", path: "/v1/me", headers: bearer))
        _ = try await transport.send(HTTPRequest(method: "GET", path: "/v1/home", headers: bearer))
        // A request that changes something can be refused for its signature, not the session.
        _ = try await transport.send(HTTPRequest(method: "POST", path: "/v1/me/card-exceptions/x/approve", headers: bearer))
        // Another session's read (a view-only session a pairing replaced) isn't this one's.
        _ = try await transport.send(HTTPRequest(method: "GET", path: "/v1/me", headers: ["Authorization": "Bearer old"]))
        try expectEqual(count.times, 0)
        try expect(!watch.hasEnded)
    }),
]

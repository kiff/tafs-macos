import Foundation

/// Watches the signed-in window's reads for the end of its session (docs/pairing.md, "A sign-in
/// KIFF no longer accepts"). A read sent with the stored session that KIFF or tafs cloud refuse
/// with 401 means KIFF no longer accepts that sign-in, signed out elsewhere or from an older
/// build. The window then ends once: the session is forgotten and sign-in opens, as on the
/// iPad (tafs#1307), rather than every screen saying it can't load.
///
/// Only reads (`GET`) count. A request that changes something can be refused for its own
/// signature, which says nothing about the session.
final class SessionWatch: @unchecked Sendable {
    private let lock = NSLock()
    private var ended = false
    /// The session's token: only its reads are watched.
    let token: String
    private let refused: @Sendable () -> Void

    /// `refused` runs once, the first time a read with `token` is refused with 401.
    init(token: String, refused: @escaping @Sendable () -> Void) {
        self.token = token
        self.refused = refused
    }

    /// Whether the session was refused.
    var hasEnded: Bool {
        lock.lock(); defer { lock.unlock() }
        return ended
    }

    /// Notes one answer to `request`.
    func saw(_ request: HTTPRequest, status: Int) {
        guard status == 401, request.method == "GET", request.headers["Authorization"] == "Bearer \(token)" else { return }
        lock.lock()
        let first = !ended
        ended = true
        lock.unlock()
        if first { refused() }
    }
}

/// A transport whose answers the session's watch sees.
struct WatchedTransport: Transport {
    let inner: Transport
    let watch: SessionWatch

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        let answer = try await inner.send(request)
        watch.saw(request, status: answer.status)
        return answer
    }

    func exchange(_ request: HTTPRequest) async throws -> (status: Int, body: Data, etag: String?) {
        let answer = try await inner.exchange(request)
        watch.saw(request, status: answer.status)
        return answer
    }
}

/// An object held weakly, as a constant a `@Sendable` closure can capture. Swift 5.7 refuses a weak
/// `self` captured by one ("reference to captured var 'self' in concurrently-executing code"),
/// since a weak capture is a var. The box is read on the object's own actor.
final class WeakBox<Object: AnyObject>: @unchecked Sendable {
    weak var object: Object?
    init(_ object: Object) { self.object = object }
}

import Foundation

/// Answers each request with the next canned answer, and keeps what was sent. Safe across
/// threads: a screen drawn more than once reads from several tasks at a time, and each takes
/// its own answer.
final class CannedTransport: Transport, @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [(Int, String)]
    private var made: [HTTPRequest] = []
    init(_ answers: [(Int, String)]) { queued = answers }

    /// The answers still to give; a test can add to them.
    var answers: [(Int, String)] {
        get { lock.lock(); defer { lock.unlock() }; return queued }
        set { lock.lock(); defer { lock.unlock() }; queued = newValue }
    }

    /// What was sent, in order.
    var sent: [HTTPRequest] {
        lock.lock(); defer { lock.unlock() }
        return made
    }

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        let (status, body) = take(request)
        return (status, Data(body.utf8))
    }

    private func take(_ request: HTTPRequest) -> (Int, String) {
        lock.lock(); defer { lock.unlock() }
        made.append(request)
        return queued.isEmpty ? (500, "") : queued.removeFirst()
    }
}

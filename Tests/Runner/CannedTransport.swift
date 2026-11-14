import Foundation

/// Answers each request with the next canned answer, and keeps what was sent.
final class CannedTransport: Transport, @unchecked Sendable {
    var answers: [(Int, String)]
    private(set) var sent: [HTTPRequest] = []
    init(_ answers: [(Int, String)]) { self.answers = answers }

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        sent.append(request)
        let (status, body) = answers.isEmpty ? (500, "") : answers.removeFirst()
        return (status, Data(body.utf8))
    }
}

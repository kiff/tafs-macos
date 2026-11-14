import Foundation

/// Opens a stream to tafs cloud's streaming address over HTTPS, and gives its lines. A run
/// streams for minutes, longer than the address the other routes use waits between bytes,
/// so the phones and this app use the function's own address for it.
struct NetworkLineStream: LineStream {
    /// tafs cloud's streaming address, the same the phones use.
    static let base = URL(string: "https://ghjfunc5ppretjo22bl5izlnya0zrocm.lambda-url.eu-west-1.on.aws")!

    var base = NetworkLineStream.base
    var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        // A run can think for minutes between two words.
        configuration.timeoutIntervalForRequest = 900
        return URLSession(configuration: configuration)
    }()

    func lines(_ request: HTTPRequest) async throws -> AsyncThrowingStream<String, Error> {
        guard let url = URL(string: request.path, relativeTo: base), url.host == base.host, url.scheme == "https" else { throw KIFFError.unreadable }
        var out = URLRequest(url: url)
        out.httpMethod = request.method
        request.headers.forEach { out.setValue($1, forHTTPHeaderField: $0) }
        out.httpBody = request.body
        let (bytes, response) = try await session.bytes(for: out)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var body = Data()
            for try await byte in bytes where body.count < 65_536 { body.append(byte) }
            throw CloudRefusal(status: status, body: body)
        }
        return AsyncThrowingStream { continuation in
            let reading = Task {
                do {
                    for try await line in bytes.lines { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in reading.cancel() }
        }
    }
}

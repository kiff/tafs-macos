import Foundation

/// Carries a request to KIFF over HTTPS. Nothing of a request or an answer is logged.
struct NetworkTransport: Transport {
    var base = URL(string: "https://api.kiff.dev")!
    var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        let (status, body, _) = try await exchange(request)
        return (status, body)
    }

    func exchange(_ request: HTTPRequest) async throws -> (status: Int, body: Data, etag: String?) {
        guard let url = URL(string: request.path, relativeTo: base), url.host == base.host, url.scheme == "https" else {
            throw KIFFError.unreadable
        }
        // The app asks itself whether anything changed (`If-None-Match`): never a cached copy.
        var out = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        out.httpMethod = request.method
        request.headers.forEach { out.setValue($1, forHTTPHeaderField: $0) }
        if !request.body.isEmpty { out.httpBody = request.body }
        let (body, response) = try await session.data(for: out)
        guard let http = response as? HTTPURLResponse else { throw KIFFError.unreadable }
        return (http.statusCode, body, http.value(forHTTPHeaderField: "ETag"))
    }
}

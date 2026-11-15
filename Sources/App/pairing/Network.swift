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
        let (status, body, _) = try await perform(try urlRequest(request, ignoringCache: false))
        return (status, body)
    }

    /// A read asked again with `If-None-Match`, as the iPad's `representation`: the answer's
    /// `ETag` with it, and never a cached copy, since the app asks itself whether anything
    /// changed. Every other request keeps the session's own cache policy, as on the iPad.
    func exchange(_ request: HTTPRequest) async throws -> (status: Int, body: Data, etag: String?) {
        try await perform(try urlRequest(request, ignoringCache: true))
    }

    /// The request for `request`, to KIFF's own host over HTTPS only.
    func urlRequest(_ request: HTTPRequest, ignoringCache: Bool) throws -> URLRequest {
        guard let url = URL(string: request.path, relativeTo: base), url.host == base.host, url.scheme == "https" else {
            throw KIFFError.unreadable
        }
        var out = ignoringCache ? URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData) : URLRequest(url: url)
        out.httpMethod = request.method
        request.headers.forEach { out.setValue($1, forHTTPHeaderField: $0) }
        if !request.body.isEmpty { out.httpBody = request.body }
        return out
    }

    private func perform(_ out: URLRequest) async throws -> (status: Int, body: Data, etag: String?) {
        let (body, response) = try await session.data(for: out)
        guard let http = response as? HTTPURLResponse else { throw KIFFError.unreadable }
        return (http.statusCode, body, http.value(forHTTPHeaderField: "ETag"))
    }
}

import Foundation

/// An API door's instructions, as the iPad's `APIDoorText.endpoint` and `example` (kiff/tafs
/// `ios/Tafs/Views/APIDoorViews.swift`): where to send work, and an example request. Everything a
/// developer needs but the key, which is never here: the example reads it from the caller's own
/// secret, `$TAFS_API_KEY`.
enum APIInstructions {
    /// tafs cloud's own address, which every endpoint is on.
    static let cloud = URL(string: CloudClient.base)!

    /// A door's address on tafs cloud, whole. Only ever on tafs cloud's own host, over HTTPS (as the iPad's since
    /// `9fa9d97`, Windows' and Linux's): a whole address elsewhere, or one whose scheme has no host of its own
    /// (`foo:x@evil.example/…`), becomes its path on tafs cloud, so the example, which sends the developer's key,
    /// never names another host.
    static func endpoint(_ address: String, base: URL = cloud) -> String {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = URLComponents(string: address)
        if let parts, parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
           host.lowercased() == base.host?.lowercased(), parts.port == nil, parts.user == nil, parts.password == nil {
            return address
        }
        // The path alone, set on tafs cloud's own address: whatever it holds stays in the path, never the host.
        var path = parts?.path ?? address
        while path.hasPrefix("/") || path.hasPrefix("\\") { path.removeFirst() }
        guard var on = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base.absoluteString }
        on.path = "/" + path
        on.query = nil
        on.fragment = nil
        guard let url = on.url, url.scheme == "https", url.host?.lowercased() == base.host?.lowercased(),
              url.port == base.port, url.user == nil else { return base.absoluteString }
        return url.absoluteString
    }

    /// An example request, as the iPad's. It reads the key from the caller's own secret: the key is never written in it.
    static func example(endpoint: String) -> String {
        "curl -X POST \(endpoint) \\\n  -H \"Authorization: Bearer $TAFS_API_KEY\" \\\n  -H \"Idempotency-Key: <your request id>\" \\\n  -H \"Content-Type: application/json\" \\\n  -d '{\"input\": {}}'"
    }
}

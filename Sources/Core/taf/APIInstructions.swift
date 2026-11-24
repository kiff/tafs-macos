import Foundation

/// An API door's instructions, as the iPad's `APIDoorText.endpoint` and `example` (kiff/tafs
/// `ios/Tafs/Views/APIDoorViews.swift`): where to send work, and an example request. Everything a
/// developer needs but the key, which is never here: the example reads it from the caller's own
/// secret, `$TAFS_API_KEY`.
enum APIInstructions {
    /// tafs cloud's own address, which every endpoint is on.
    static let cloud = URL(string: CloudClient.base)!

    /// A door's address on tafs cloud: **always rebuilt on tafs cloud's own address**, keeping only the address's path,
    /// and only when that path is plain (`^/[A-Za-z0-9/_.~-]*$`, unreserved characters); never a query or a fragment.
    /// Anything else is tafs cloud's address alone, with its slash. It's every app's shared rule
    /// (`vectors/api-door-endpoint.json` in kiff/tafs), which hardens the iPad's `APIDoorText.endpoint`. The example is a shell
    /// line a developer pastes, with their key, so it never names another host, and a path can't carry `$ ( ) ; & '`.
    /// tafs cloud's own door paths (`/v1/doors/api/api-…/requests`) are always plain.
    static func endpoint(_ address: String, base: URL = cloud) -> String {
        let root = base.absoluteString.hasSuffix("/") ? base.absoluteString : base.absoluteString + "/"
        guard let parts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else { return root }
        // Escaped as sent, so `%24` is never read back as `$`; a relative path is from the root.
        var path = parts.percentEncodedPath
        if !path.hasPrefix("/") { path = "/" + path }
        guard isPlainPath(path) else { return root }
        return root + path.dropFirst()
    }

    /// Whether a path holds only unreserved characters and slashes: nothing a shell reads, nothing escaped.
    static func isPlainPath(_ path: String) -> Bool {
        path.range(of: #"^/[A-Za-z0-9/_.~-]*$"#, options: .regularExpression) != nil
    }

    /// The longest key name the field takes (tafs cloud takes 80; 60, as the iPad and Android).
    static let maxKeyName = 60

    /// A new key's name, as the iPad's `APIDoorText.keyName`: what the owner typed, trimmed, else the door's own name.
    static func keyName(_ typed: String, door label: String) -> String {
        let name = String(typed.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxKeyName))
        return name.isEmpty ? String(label.prefix(maxKeyName)) : name
    }

    /// An example request, as the iPad's. It reads the key from the caller's own secret: the key is never written in it.
    /// The endpoint is single-quoted, so whatever slipped past the plain path stays inert in a shell.
    static func example(endpoint: String) -> String {
        // A quote in it would close the quoting: it's dropped (a plain endpoint never has one).
        let quoted = endpoint.replacingOccurrences(of: "'", with: "")
        return "curl -X POST '\(quoted)' \\\n  -H \"Authorization: Bearer $TAFS_API_KEY\" \\\n  -H \"Idempotency-Key: <your request id>\" \\\n  -H \"Content-Type: application/json\" \\\n  -d '{\"input\": {}}'"
    }
}

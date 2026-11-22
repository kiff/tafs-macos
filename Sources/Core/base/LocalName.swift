import Foundation

/// A name from a server made safe as one path component under a folder the app owns, so a file never lands outside it
/// (an id or a file name like "../x", "/etc/x", "..", or one made only of dots or separators). What reads normally stays
/// as it is: letters of any script, digits, spaces, dots inside a name, "-" and "_".
enum LocalName {
    /// One component: "/" and ":" become "_", control characters go, and an empty or all-dots result becomes `fallback`.
    static func component(_ name: String, fallback: String = "file") -> String {
        var out = String(String.UnicodeScalarView(name.unicodeScalars.compactMap { s -> Unicode.Scalar? in
            if s == "/" || s == ":" || s == "\\" { return "_" }
            if CharacterSet.controlCharacters.contains(s) { return nil }
            return s
        }))
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty || out.allSatisfy({ $0 == "." }) { return fallback }
        return out
    }

    /// `component` under `folder`, checked to stay inside it once resolved; nil if it wouldn't.
    static func file(_ name: String, in folder: URL, fallback: String = "file") -> URL? {
        let url = folder.appendingPathComponent(component(name, fallback: fallback))
        let base = folder.standardizedFileURL.path
        let resolved = url.standardizedFileURL.path
        return resolved.hasPrefix(base.hasSuffix("/") ? base : base + "/") ? url : nil
    }
}

import Foundation

/// A JSON object's values as written, byte for byte (the iPad's `RawJSON`): KIFF's signed chain is
/// hashed as KIFF wrote it, never decoded and written again.
enum ReceiptJSON {
    /// A top-level value's own bytes in a JSON object; nil when it isn't there or the object doesn't read.
    static func value(of key: String, in data: Data) -> Data? {
        let bytes = [UInt8](data)
        var i = skipSpace(bytes, 0)
        guard i < bytes.count, bytes[i] == UInt8(ascii: "{") else { return nil }
        i += 1
        while true {
            i = skipSpace(bytes, i)
            guard i < bytes.count else { return nil }
            if bytes[i] == UInt8(ascii: "}") { return nil }
            guard bytes[i] == UInt8(ascii: "\""), let keyEnd = endOfString(bytes, i) else { return nil }
            let name = (try? JSONSerialization.jsonObject(with: Data(bytes[i..<keyEnd]), options: .fragmentsAllowed)) as? String
            i = skipSpace(bytes, keyEnd)
            guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { return nil }
            i = skipSpace(bytes, i + 1)
            guard let valueEnd = endOfValue(bytes, i) else { return nil }
            if name == key { return Data(bytes[i..<valueEnd]) }
            i = skipSpace(bytes, valueEnd)
            guard i < bytes.count else { return nil }
            if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
            return nil
        }
    }

    /// An object's own keys, in the order written (not those of objects inside it); nil when `data`
    /// isn't an object that reads to its end.
    static func keys(of data: Data) -> [String]? {
        let bytes = [UInt8](data)
        var i = skipSpace(bytes, 0)
        guard i < bytes.count, bytes[i] == UInt8(ascii: "{") else { return nil }
        i = skipSpace(bytes, i + 1)
        var out: [String] = []
        if i < bytes.count, bytes[i] == UInt8(ascii: "}") { return out }
        while true {
            guard i < bytes.count, bytes[i] == UInt8(ascii: "\""), let keyEnd = endOfString(bytes, i),
                  let name = (try? JSONSerialization.jsonObject(with: Data(bytes[i..<keyEnd]), options: .fragmentsAllowed)) as? String
            else { return nil }
            out.append(name)
            i = skipSpace(bytes, keyEnd)
            guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { return nil }
            i = skipSpace(bytes, i + 1)
            guard let valueEnd = endOfValue(bytes, i) else { return nil }
            i = skipSpace(bytes, valueEnd)
            guard i < bytes.count else { return nil }
            if bytes[i] == UInt8(ascii: "}") { return out }
            guard bytes[i] == UInt8(ascii: ",") else { return nil }
            i = skipSpace(bytes, i + 1)
        }
    }

    /// No key of the object written twice. An object it can't read isn't unique.
    static func keysAreUnique(in data: Data) -> Bool {
        guard let keys = keys(of: data) else { return false }
        return Set(keys).count == keys.count
    }

    private static func skipSpace(_ b: [UInt8], _ from: Int) -> Int {
        var i = from
        while i < b.count, [0x20, 0x09, 0x0A, 0x0D].contains(b[i]) { i += 1 }
        return i
    }

    /// The index after a string's closing quote; `start` is its opening quote.
    private static func endOfString(_ b: [UInt8], _ start: Int) -> Int? {
        var i = start + 1
        while i < b.count {
            if b[i] == UInt8(ascii: "\\") { i += 2; continue }
            if b[i] == UInt8(ascii: "\"") { return i + 1 }
            i += 1
        }
        return nil
    }

    /// The index after a value: a string, an object or array (to its matching close), or a literal or
    /// number (to the next delimiter).
    private static func endOfValue(_ b: [UInt8], _ start: Int) -> Int? {
        guard start < b.count else { return nil }
        switch b[start] {
        case UInt8(ascii: "\""):
            return endOfString(b, start)
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var depth = 0
            var i = start
            while i < b.count {
                switch b[i] {
                case UInt8(ascii: "\""):
                    guard let end = endOfString(b, i) else { return nil }
                    i = end
                    continue
                case UInt8(ascii: "{"), UInt8(ascii: "["):
                    depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"):
                    depth -= 1
                    if depth == 0 { return i + 1 }
                default:
                    break
                }
                i += 1
            }
            return nil
        default:
            var i = start
            while i < b.count, ![UInt8(ascii: ","), UInt8(ascii: "}"), UInt8(ascii: "]"), 0x20, 0x09, 0x0A, 0x0D].contains(b[i]) { i += 1 }
            return i > start ? i : nil
        }
    }
}

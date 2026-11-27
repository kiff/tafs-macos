import Foundation

/// A held call's arguments as every app writes them under Details (kiff/tafs
/// `contracts/held-arguments.json`): one line an argument, nested values below their name, two
/// spaces deeper each level, keys sorted by code point at every level, and nothing ever
/// shortened. A held browser call's steps are shown in full, each field on its own line.
///
/// The arguments are read from KIFF's own bytes by `parse`, never through `Double`: what the
/// person approves shows the digits the taf sent, however long.
enum HeldArguments {
    /// One JSON value as sent, a number kept as its text.
    indirect enum Value: Equatable {
        case text(String), number(String), flag(Bool), null
        case list([Value]), object([String: Value])
    }

    /// The gateway's own arguments, never shown.
    static let gatewayOwn: Set<String> = ["kiff_operation_id", "kiff_reason", "kiff_about"]

    /// The lines under Details, in order. Empty when there's nothing to show.
    static func lines(_ arguments: [String: Value]) -> [String] {
        var out: [String] = []
        for (key, value) in sorted(arguments) where !gatewayOwn.contains(key) {
            if case .text(let text) = value, text.isEmpty { continue }
            write(key, value, depth: 0, into: &out)
        }
        return out
    }

    private static func write(_ name: String, _ value: Value, depth: Int, into out: inout [String]) {
        let lead = String(repeating: "  ", count: depth) + visible(name) + ":"
        switch value {
        case .text(let text): out.append(lead + " " + (text.isEmpty ? "\"\"" : visible(text)))
        case .number(let number): out.append(lead + " " + plain(number))
        case .flag(let flag): out.append(lead + (flag ? " true" : " false"))
        case .null: out.append(lead + " null")
        case .list(let items) where items.isEmpty: out.append(lead + " []")
        case .object(let fields) where fields.isEmpty: out.append(lead + " {}")
        case .list(let items):
            out.append(lead)
            for (i, item) in items.enumerated() { write(String(i + 1), item, depth: depth + 1, into: &out) }
        case .object(let fields):
            out.append(lead)
            for (key, field) in sorted(fields) { write(key, field, depth: depth + 1, into: &out) }
        }
    }

    /// Keys by Unicode code point, as every app sorts them (a dictionary can't keep the order sent).
    private static func sorted(_ fields: [String: Value]) -> [(String, Value)] {
        fields.sorted { $0.key.unicodeScalars.lexicographicallyPrecedes($1.key.unicodeScalars) { $0.value < $1.value } }
            .map { ($0.key, $0.value) }
    }

    /// Direction marks, dropped so a value can't reorder what's drawn around it.
    private static let directionMarks: Set<UInt32> = [0x200E, 0x200F, 0x061C, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]

    /// A key or value on one line: each control character becomes one space, so a value can't draw a
    /// line of its own, and a direction mark is dropped.
    static func visible(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if directionMarks.contains(scalar.value) { continue }
            out.append(scalar.properties.generalCategory == .control ? " " : scalar)
        }
        return String(out)
    }

    /// A JSON number's text written out in full, from its own digits: no exponent (1.5e-05 is
    /// 0.000015) and no trailing zeros after the point (1.50 is 1.5, 2.0 is 2). No digit is
    /// added or rounded away.
    static func plain(_ number: String) -> String {
        var text = Substring(number)
        let negative = text.first == "-"
        if negative { text = text.dropFirst() }
        var exponent = 0
        if let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            guard let value = Int(text[text.index(after: e)...].drop { $0 == "+" }) else { return number }
            exponent = value
            text = text[..<e]
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }) else { return number }
        let whole = String(parts[0]), fraction = parts.count > 1 ? String(parts[1]) : ""
        var digits = whole + fraction
        var point = whole.count + exponent
        if point < 0 { digits = String(repeating: "0", count: -point) + digits; point = 0 }
        if point > digits.count { digits += String(repeating: "0", count: point - digits.count) }
        var head = String(digits.prefix(point)), tail = String(digits.dropFirst(point))
        while tail.hasSuffix("0") { tail.removeLast() }
        while head.hasPrefix("0") { head.removeFirst() }
        if head.isEmpty { head = "0" }
        let zero = head == "0" && tail.isEmpty
        return (negative && !zero ? "-" : "") + head + (tail.isEmpty ? "" : "." + tail)
    }

    /// One JSON document read as sent, its numbers kept as text. Nil when it isn't JSON.
    static func parse(_ data: Data) -> Value? {
        var reader = Reader(bytes: Array(data))
        guard let value = reader.value() else { return nil }
        reader.space()
        return reader.at == reader.bytes.count ? value : nil
    }

    private struct Reader {
        let bytes: [UInt8]
        var at = 0
        var depth = 0

        mutating func space() {
            while at < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[at]) { at += 1 }
        }

        mutating func take(_ word: String) -> Bool {
            let w = Array(word.utf8)
            guard at + w.count <= bytes.count, Array(bytes[at..<at + w.count]) == w else { return false }
            at += w.count
            return true
        }

        mutating func value() -> Value? {
            space()
            guard at < bytes.count, depth < 64 else { return nil }
            switch bytes[at] {
            case UInt8(ascii: "{"):
                at += 1; depth += 1; defer { depth -= 1 }
                var fields: [String: Value] = [:]
                space()
                if at < bytes.count, bytes[at] == UInt8(ascii: "}") { at += 1; return .object(fields) }
                while true {
                    space()
                    guard let key = text() else { return nil }
                    space()
                    guard take(":"), let field = value() else { return nil }
                    fields[key] = field
                    space()
                    if take(",") { continue }
                    return take("}") ? .object(fields) : nil
                }
            case UInt8(ascii: "["):
                at += 1; depth += 1; defer { depth -= 1 }
                var items: [Value] = []
                space()
                if at < bytes.count, bytes[at] == UInt8(ascii: "]") { at += 1; return .list(items) }
                while true {
                    guard let item = value() else { return nil }
                    items.append(item)
                    space()
                    if take(",") { continue }
                    return take("]") ? .list(items) : nil
                }
            case UInt8(ascii: "\""): return text().map(Value.text)
            case UInt8(ascii: "t"): return take("true") ? .flag(true) : nil
            case UInt8(ascii: "f"): return take("false") ? .flag(false) : nil
            case UInt8(ascii: "n"): return take("null") ? .null : nil
            default: return number()
            }
        }

        mutating func number() -> Value? {
            let start = at
            while at < bytes.count, "+-0123456789.eE".utf8.contains(bytes[at]) { at += 1 }
            guard at > start, let written = String(bytes: bytes[start..<at], encoding: .utf8),
                  written.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil
            else { return nil }
            return .number(written)
        }

        mutating func text() -> String? {
            guard at < bytes.count, bytes[at] == UInt8(ascii: "\"") else { return nil }
            at += 1
            var out: [UInt8] = []
            while at < bytes.count {
                let b = bytes[at]
                at += 1
                if b == UInt8(ascii: "\"") { return String(bytes: out, encoding: .utf8) }
                guard b == UInt8(ascii: "\\") else { out.append(b); continue }
                guard at < bytes.count else { return nil }
                let e = bytes[at]
                at += 1
                switch e {
                case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): out.append(e)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    guard var code = hex4() else { return nil }
                    if (0xD800...0xDBFF).contains(code), take("\\u"), let low = hex4(), (0xDC00...0xDFFF).contains(low) {
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    }
                    out.append(contentsOf: Array(String(Character(Unicode.Scalar(code) ?? "\u{FFFD}")).utf8))
                default: return nil
                }
            }
            return nil
        }

        mutating func hex4() -> UInt32? {
            guard at + 4 <= bytes.count, let s = String(bytes: bytes[at..<at + 4], encoding: .utf8), let v = UInt32(s, radix: 16) else { return nil }
            at += 4
            return v
        }
    }
}

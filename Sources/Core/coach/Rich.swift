import Foundation

/// The Markdown that Coach's and a taf's words are drawn with, as the iPad's `MarkdownText`
/// reads it, so no mark shows as written: **bold**, *italic*, `code`, headings, and bulleted
/// and numbered items. A link is drawn as its label only, and an image as its words: nothing
/// here can lead anywhere. HTML, and a mark with no partner, stay as written, so nothing the
/// model writes can look like one of the app's own controls.
enum Rich {
    struct Span: Equatable {
        let text: String
        var bold = false
        var italic = false
        /// Inline code: drawn in the monospaced face, with no marks read inside it.
        var code = false
    }

    enum Block: Equatable {
        case paragraph([Span])
        case bullet([Span])
        /// A numbered item, with its number as written ("1.").
        case numbered(String, [Span])
        /// A heading ("## What I'll do"), drawn a step larger and semibold.
        case heading([Span])
        /// A fenced code block's lines, as written: no mark is read inside it.
        case code(String)
    }

    /// The longest text read for marks; a longer one is drawn plain.
    static let longest = 20_000

    /// An answer still being written, with what it's in the middle of closed, so no Markdown
    /// symbol shows while it streams, as the iPad's `MarkdownBlock.healed` (kiff/tafs#285): bold
    /// or inline code left open, a link whose address isn't in yet (its text shows), a mark just
    /// opened with nothing after it. An open code block needs nothing: `blocks` draws it as code
    /// until it closes.
    static func healed(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let fences = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }.count
        guard fences % 2 == 0, var last = lines.popLast() else { return text }
        last = last.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*$"#, with: "$1", options: .regularExpression)
        last = last.replacingOccurrences(of: #"\[([^\]]*)$"#, with: "$1", options: .regularExpression)
        // A mark just opened, with nothing after it yet ("Refunded **"), goes until its words
        // come. One right after a word closes what it opened, and stays.
        while let end = last.last, end == "*" || end == "_" || end == "`" {
            let before = last.dropLast(last.reversed().prefix { $0 == end }.count)
            guard before.last.map({ $0.isWhitespace }) ?? true else { break }
            last = String(before)
        }
        if last.components(separatedBy: "**").count % 2 == 0 { last += "**" }
        if last.filter({ $0 == "`" }).count % 2 == 1 { last += "`" }
        return (lines + [last]).joined(separator: "\n")
    }

    /// How much of an answer streaming in shows after one more frame (16 ms), as the iPad's
    /// `SteadyMarkdown` paces it: at least two characters, else a sixth of what's left, so it
    /// reads at an even pace rather than in the bursts it arrives in, and catches up in a few
    /// frames.
    static func paced(_ shown: Int, toward target: Int) -> Int {
        guard shown < target else { return target }
        return min(target, shown + max(2, (target - shown + 5) / 6))
    }

    static func blocks(_ text: String) -> [Block] {
        guard text.count <= longest else { return [.paragraph([Span(text: text)])] }
        var out: [Block] = []
        // Lines inside a ``` fence, while one is open. One never closed stays code to the end,
        // as the iPad's `MarkdownText` draws it while an answer streams.
        var code: [String]?
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let lines = code {
                    out.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    code = []
                }
                continue
            }
            if code != nil { code?.append(line); continue }
            if trimmed.isEmpty { continue }
            if let words = heading(trimmed) {
                out.append(.heading(spans(words)))
            } else if case let (number, words)? = numbered(trimmed) {
                out.append(.numbered(number, spans(words)))
            } else if let item = bullet(trimmed) {
                out.append(.bullet(spans(item)))
            } else {
                out.append(.paragraph(spans(trimmed)))
            }
        }
        if let lines = code { out.append(.code(lines.joined(separator: "\n"))) }
        return out
    }

    /// A heading's words: one to six "#", then a space.
    private static func heading(_ line: String) -> String? {
        let marks = line.prefix { $0 == "#" }.count
        guard (1...6).contains(marks), line.dropFirst(marks).first == " " else { return nil }
        let rest = line.dropFirst(marks).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }

    /// A numbered item: one to three digits, "." or ")", then a space.
    private static func numbered(_ line: String) -> (String, String)? {
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard (1...3).contains(digits.count) else { return nil }
        let after = line.dropFirst(digits.count)
        guard let mark = after.first, mark == "." || mark == ")", after.dropFirst().first == " " else { return nil }
        let rest = after.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : (String(digits) + ".", rest)
    }

    /// The words of a list item, when the line starts one: "- ", "* " or "• ".
    private static func bullet(_ line: String) -> String? {
        for mark in ["- ", "* ", "• "] where line.hasPrefix(mark) {
            let rest = String(line.dropFirst(mark.count)).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : rest
        }
        return nil
    }

    /// A line's words, with its inline marks read. A mark with no partner stays as written.
    static func spans(_ line: String) -> [Span] {
        var out: [Span] = []
        inline(Array(line), bold: false, italic: false, into: &out)
        // Neighbours drawn the same way are one span.
        var joined: [Span] = []
        for span in out {
            if let last = joined.last, last.bold == span.bold, last.italic == span.italic, last.code == span.code {
                joined[joined.count - 1] = Span(text: last.text + span.text, bold: span.bold, italic: span.italic, code: span.code)
            } else {
                joined.append(span)
            }
        }
        return joined.isEmpty ? [Span(text: line)] : joined
    }

    private static func inline(_ c: [Character], bold: Bool, italic: Bool, into out: inout [Span]) {
        var plain = ""
        func flush() {
            if !plain.isEmpty { out.append(Span(text: plain, bold: bold, italic: italic)) }
            plain = ""
        }
        var i = 0
        while i < c.count {
            let ch = c[i]
            if ch == "`", let end = find(c, "`", from: i + 1), end > i + 1 {
                flush()
                out.append(Span(text: String(c[(i + 1)..<end]), bold: bold, italic: italic, code: true))
                i = end + 1
                continue
            }
            if ch == "*", i + 1 < c.count, c[i + 1] == "*", let end = find(c, "**", from: i + 2), end > i + 2 {
                flush()
                inline(Array(c[(i + 2)..<end]), bold: true, italic: italic, into: &out)
                i = end + 2
                continue
            }
            if ch == "*" || ch == "_", !italic, opens(c, at: i), let end = closes(c, ch, from: i + 1) {
                flush()
                inline(Array(c[(i + 1)..<end]), bold: bold, italic: true, into: &out)
                i = end + 1
                continue
            }
            let at = ch == "!" && i + 1 < c.count && c[i + 1] == "[" ? i + 1 : i
            if c[at] == "[", case let (label, next)? = link(c, at: at) {
                flush()
                inline(label, bold: bold, italic: italic, into: &out)
                i = next
                continue
            }
            plain.append(ch)
            i += 1
        }
        flush()
    }

    /// Where a run of characters starts, at or after `from`.
    private static func find(_ c: [Character], _ pattern: String, from: Int) -> Int? {
        let p = Array(pattern)
        guard from <= c.count - p.count else { return nil }
        for j in from...(c.count - p.count) where Array(c[j..<(j + p.count)]) == p { return j }
        return nil
    }

    /// An emphasis mark opens when a word follows it, and "_" only outside a word (snake_case).
    private static func opens(_ c: [Character], at i: Int) -> Bool {
        guard i + 1 < c.count, !c[i + 1].isWhitespace, c[i + 1] != c[i] else { return false }
        if c[i] == "_", i > 0, c[i - 1].isLetter || c[i - 1].isNumber { return false }
        return true
    }

    /// Its partner: the same mark after a word, and for "_" not inside a word.
    private static func closes(_ c: [Character], _ mark: Character, from: Int) -> Int? {
        var j = from + 1
        while j < c.count {
            if c[j] == mark, !c[j - 1].isWhitespace, j + 1 >= c.count || c[j + 1] != mark {
                if mark == "_", j + 1 < c.count, c[j + 1].isLetter || c[j + 1].isNumber { j += 1; continue }
                return j
            }
            j += 1
        }
        return nil
    }

    /// A link "[label](address)": its label, and where the text goes on after it.
    private static func link(_ c: [Character], at i: Int) -> ([Character], Int)? {
        guard let close = find(c, "]", from: i + 1), close > i + 1, close + 1 < c.count, c[close + 1] == "(",
              let end = find(c, ")", from: close + 2) else { return nil }
        return (Array(c[(i + 1)..<close]), end + 1)
    }
}

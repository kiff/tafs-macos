import Foundation

/// The little of Markdown that Coach's and a taf's words are drawn with: **bold**, and a
/// line that starts a list item. Everything else stays as written. There are no links, no
/// images and no HTML here, so nothing the model writes can lead anywhere or look like one
/// of the app's own controls.
enum Rich {
    struct Span: Equatable {
        let text: String
        let bold: Bool
    }

    enum Block: Equatable {
        case paragraph([Span])
        case bullet([Span])
    }

    /// The longest text read for marks; a longer one is drawn plain.
    static let longest = 20_000

    static func blocks(_ text: String) -> [Block] {
        guard text.count <= longest else { return [.paragraph([Span(text: text, bold: false)])] }
        var out: [Block] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if let item = bullet(trimmed) {
                out.append(.bullet(spans(item)))
            } else {
                out.append(.paragraph(spans(trimmed)))
            }
        }
        return out
    }

    /// The words of a list item, when the line starts one: "- ", "* " or "• ".
    private static func bullet(_ line: String) -> String? {
        for mark in ["- ", "* ", "• "] where line.hasPrefix(mark) {
            let rest = String(line.dropFirst(mark.count)).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : rest
        }
        return nil
    }

    /// Splits a line at `**`. An odd mark with no partner stays in the text as written.
    static func spans(_ line: String) -> [Span] {
        let parts = line.components(separatedBy: "**")
        // An even count of parts means an unpaired mark: keep the whole line as it is.
        guard parts.count >= 3, parts.count % 2 == 1 else { return [Span(text: line, bold: false)] }
        var out: [Span] = []
        for (index, part) in parts.enumerated() where !part.isEmpty {
            out.append(Span(text: part, bold: index % 2 == 1))
        }
        return out.isEmpty ? [Span(text: line, bold: false)] : out
    }
}

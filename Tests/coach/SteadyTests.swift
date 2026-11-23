import Foundation

/// What's drawn of a block, its marks read.
private func drawn(_ text: String) -> String {
    Rich.blocks(text).map { block -> String in
        switch block {
        case .paragraph(let spans), .bullet(let spans), .heading(let spans), .numbered(_, let spans): return spans.map(\.text).joined()
        case .code(let lines): return lines
        }
    }.joined(separator: "\n")
}

/// The answer streaming in, as the iPad's `SteadyMarkdown` (WorkLog.swift) and `MarkdownBlock.healed`
/// (kiff/tafs#285): what it's in the middle of is closed, and it shows at an even pace.
let coachSteadyTests: [Test] = [
    Test("an answer being written has what it's in the middle of closed, as the iPad's healed") {
        let cases: [(String, String)] = [
            ("Refunded **$20", "Refunded **$20**"),
            ("Run `refund", "Run `refund`"),
            ("See [the order](https://shop.te", "See the order"),
            ("See [the ord", "See the ord"),
            ("Refunded **", "Refunded "),
            ("**Done**", "**Done**"),
            ("**a**\nnext", "**a**\nnext"),
            // An open code block needs nothing: it's drawn as code until it closes.
            ("```\nlet x = `", "```\nlet x = `"),
        ]
        for (text, healed) in cases { try expectEqual(Rich.healed(text), healed) }
    },
    Test("no Markdown symbol shows while an answer streams") {
        for text in ["Refunded **$20", "See [the order](https://shop.te", "Run `refund", "Refunded **"] {
            let shown = drawn(Rich.healed(text))
            try expect(!shown.contains("*") && !shown.contains("`") && !shown.contains("["), "\(text) shows a mark: \(shown)")
        }
        // Healed, the words are the ones written.
        try expectEqual(drawn(Rich.healed("Refunded **$20")), "Refunded $20")
        try expectEqual(drawn(Rich.healed("See [the order](https://shop.te")), "See the order")
    },
    Test("an answer is paced as the iPad's: at least two characters a frame, else a sixth of what's left, never past its end") {
        try expectEqual(Rich.paced(0, toward: 1), 1)
        try expectEqual(Rich.paced(0, toward: 6), 2)
        try expectEqual(Rich.paced(0, toward: 60), 10)
        try expectEqual(Rich.paced(100, toward: 160), 110)
        try expectEqual(Rich.paced(10, toward: 10), 10)
        try expectEqual(Rich.paced(12, toward: 10), 10)
        // A burst of 600 characters is caught up within a few dozen frames (well under a second).
        var at = 0, frames = 0
        while at < 600 { at = Rich.paced(at, toward: 600); frames += 1 }
        try expectEqual(at, 600)
        try expect(frames < 40, "\(frames) frames")
    },
]

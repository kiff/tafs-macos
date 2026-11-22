import Foundation

/// What a line's script asks of the app's small capitals headings (`Eyebrow`).
enum Script {
    /// Whether a line is written in Hangul, kana, Han or Arabic script, which a monospaced face and letter-spacing
    /// only pull apart (Arabic's letters join, so spacing them breaks the word). The iPad's `Eyebrow.ideographic`
    /// (kiff/tafs `ios/Tafs/Design/Components.swift`), range for range.
    static func ideographic(_ text: String) -> Bool {
        text.unicodeScalars.contains { s in
            (0x1100...0x11FF).contains(s.value) || (0x3040...0x30FF).contains(s.value) || (0x3130...0x318F).contains(s.value)
                || (0x3400...0x4DBF).contains(s.value) || (0x4E00...0x9FFF).contains(s.value) || (0xAC00...0xD7AF).contains(s.value)
                || (0x0600...0x06FF).contains(s.value) || (0x0750...0x077F).contains(s.value) || (0x08A0...0x08FF).contains(s.value)
                || (0xFB50...0xFDFF).contains(s.value) || (0xFE70...0xFEFF).contains(s.value)
        }
    }
}

import SwiftUI

/// An answer streaming in, as the iPad's `SteadyMarkdown` (WorkLog.swift): drawn as Markdown with
/// what it's in the middle of closed (`Rich.healed`), so no mark shows on the way, and at an even
/// pace rather than in the bursts it arrives in (`Rich.paced`, a frame every 16 ms). The first
/// words show at once; each new piece goes on from where the last stopped. With Reduce Motion,
/// all of it at once. The iPad counts what's drawn and this counts what's written, then heals
/// it, as Windows' (the same words show, at the same pace).
struct SteadyText<Content: View>: View {
    let text: String
    let draw: (String) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How many characters show; nil shows all.
    @State private var shown: Int?

    var body: some View {
        draw(Rich.healed(shown.map { String(text.prefix($0)) } ?? text))
            .task(id: text) {
                let target = text.count
                guard !reduceMotion else { shown = nil; return }
                // Another answer, shorter than what showed, shows whole at once, as the first words do.
                var at = Swift.min(shown ?? target, target)
                shown = at
                while at < target, !Task.isCancelled {
                    at = Rich.paced(at, toward: target)
                    shown = at
                    try? await Task.sleep(nanoseconds: 16_000_000)
                }
            }
    }
}

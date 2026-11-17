import AppKit
import SwiftUI

/// Gives the window its size at first launch and remembers it after (`WindowSize`): macOS 12's
/// SwiftUI has no default size for a window, so the first one opened at its minimum.
struct WindowFrame: NSViewRepresentable {
    /// The name the window's frame is kept under, in this Mac's defaults.
    static let name = "tafs main window"

    func makeNSView(context: Context) -> NSView { Attach() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Sizes its window once it has one.
    final class Attach: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window.frameAutosaveName.isEmpty else { return }
            // The frame kept from before first, so naming the window never saves the frame it opened at
            // over it. None kept: the first launch's size, in the middle of the screen.
            if !window.setFrameUsingName(WindowFrame.name) {
                window.setContentSize(WindowSize.firstLaunch(visible: window.screen?.visibleFrame.size))
                window.center()
            }
            // Kept from now on. A second window, while the first holds the name, isn't kept.
            _ = window.setFrameAutosaveName(WindowFrame.name)
        }
    }
}

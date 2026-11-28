import Foundation

/// Whether a chat follows what arrives, and when it shows its ↓ (the iPad's `SetupChatView`: `atBottom`, `following`
/// and `unseen`). While the thread's end is in view, what arrives scrolls into view. Once the person has read back
/// up, nothing moves under them: the ↓ shows, with its dot when something arrived below, and takes them to the latest.
struct ChatFollow: Equatable {
    /// The thread's end shows (within `slack` of the view's foot).
    private(set) var atBottom = true
    /// Something arrived below while the person read back: the ↓ shows its dot.
    private(set) var unseen = false

    /// How far below the view's foot the end may sit and still count as shown: a line's rounding, never a screen.
    static let slack = 24.0

    /// The ↓ shows whenever the end doesn't.
    var showsJump: Bool { !atBottom }

    /// The view moved: `foot` is where the thread's end sits, from the view's top; `height` is the view's height.
    mutating func scrolled(foot: Double, height: Double) {
        guard height > 0 else { return }
        atBottom = foot <= height + Self.slack
        if atBottom { unseen = false }
    }

    /// Something arrived in the thread. True when the view should follow it to the end; otherwise the ↓ gets its dot.
    mutating func arrived() -> Bool {
        if atBottom { return true }
        unseen = true
        return false
    }

    /// The person took the ↓: to the latest, with nothing unseen.
    mutating func jumped() {
        atBottom = true
        unseen = false
    }
}

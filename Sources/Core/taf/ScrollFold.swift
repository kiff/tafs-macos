import CoreGraphics

/// Folds a taf's header line while its chat scrolls down and brings it back on the way up, as the iPad's
/// `TafDetailView.fold` (its version, Files and who it's shared with give the chat the screen). The thread's
/// top is read as it scrolls; once it has moved 24 points from where it was last marked, the direction is
/// said and that place becomes the new mark, so a small wobble never folds or unfolds.
struct ScrollFold: Equatable {
    /// How far the thread moves before the line folds or comes back: the iPad's drag of 24 points.
    static let step: CGFloat = 24
    /// Where the thread's top was when a direction was last said (or first read).
    private(set) var mark: CGFloat?

    /// The thread's top is now at `top` (lower as it scrolls down): true to fold, false to unfold, nil while
    /// it hasn't moved a step since the mark.
    mutating func moved(to top: CGFloat) -> Bool? {
        guard let mark else { self.mark = top; return nil }
        let moved = top - mark
        guard abs(moved) >= Self.step else { return nil }
        self.mark = top
        return moved < 0
    }
}

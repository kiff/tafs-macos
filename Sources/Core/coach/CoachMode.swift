import Foundation

/// Coach mode's panel on the Mac, as the iPad's `CoachPanel` (CoachMode.swift:34-111): Coach slides
/// in from the right over the screen, which stays in view and usable where the panel doesn't cover
/// it. Its left edge drags it wider or narrower, ⤢ fills the window and brings it back, and the
/// width chosen is kept on this Mac for the next time.
///
/// The iPad keeps a share of its screen, a third at least; a Mac's window is any size, so the Mac
/// keeps points, between `narrowest` and what leaves `behind` of the screen in view.
enum CoachPanelWidth {
    /// Where this Mac keeps the width chosen and whether Coach fills the window, as the iPad's
    /// `@AppStorage("coach.width")` and `("coach.full")`.
    static let widthKey = "coach.width"
    static let fullKey = "coach.full"

    /// The width it opens at, before one is chosen.
    static let opening: Double = 440
    /// Never narrower: Coach's cards and its box stay readable.
    static let narrowest: Double = 380
    /// While it isn't full, this much of the screen behind stays in view.
    static let behind: Double = 240

    /// The widest it is drawn beside the screen, `detail` points wide: the screen keeps `behind`,
    /// and it is never narrower than `narrowest`.
    static func widest(detail: Double) -> Double {
        max(narrowest, detail - behind)
    }

    /// The width drawn for one chosen, in a screen `detail` points wide: between `narrowest` and
    /// `widest`, and never wider than the screen itself.
    static func drawn(_ chosen: Double, detail: Double) -> Double {
        let width = min(widest(detail: detail), max(narrowest, chosen))
        return detail > 0 ? min(detail, width) : width
    }

    /// The width kept on this Mac, as read back: one never chosen, or one that can't be, opens at
    /// `opening`.
    static func remembered(_ stored: Double?) -> Double {
        guard let stored, stored.isFinite, stored >= narrowest else { return opening }
        return stored
    }

    /// The width chosen by a drag of the left edge that ended `moved` points to the right (to the
    /// left, a negative move, widens it), from `from`, in a screen `detail` points wide.
    static func dragged(from: Double, moved: Double, detail: Double) -> Double {
        drawn(from - moved, detail: detail)
    }
}

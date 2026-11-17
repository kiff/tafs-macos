import Foundation

/// The window's size (docs/shell.md, "The window's size"). macOS 12's SwiftUI has no default size
/// for a window (`defaultSize` is macOS 13's), so the first window opened at its minimum, 900 by
/// 600, smaller than the iPad's frame. It opens at the iPad's landscape frame instead, within the
/// screen, and is remembered from then on.
enum WindowSize {
    /// The smallest the window goes: the sidebar and one readable column.
    static let minimum = CGSize(width: 900, height: 600)
    /// The iPad's landscape frame (the 13-inch iPad's points), the window's size at first launch.
    static let first = CGSize(width: 1366, height: 1024)
    /// How much of the screen's visible area the first window takes at most.
    static let screenShare: CGFloat = 0.9

    /// The size the first window opens at, on a screen whose visible area is `visible`: the iPad's
    /// frame, no more than `screenShare` of the screen, and never under the minimum.
    static func firstLaunch(visible: CGSize?) -> CGSize {
        guard let visible, visible.width > 0, visible.height > 0 else { return first }
        return CGSize(width: max(minimum.width, min(first.width, (visible.width * screenShare).rounded(.down))),
                      height: max(minimum.height, min(first.height, (visible.height * screenShare).rounded(.down))))
    }
}

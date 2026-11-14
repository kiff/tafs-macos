import AppKit
import SwiftUI

/// Draws a view to a bitmap with no window on screen, in one appearance: what the screenshots
/// of a pull request and the tests of a screen are made from.
enum Snapshot {
    static func bitmap<V: View>(of view: V, size: CGSize, dark: Bool = false) -> NSBitmapImageRep? {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    /// The colour at a point of `bitmap`, as `0xRRGGBB`, with the point's origin at the top left.
    static func hex(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> UInt32? {
        let scale = bitmap.pixelsWide / max(Int(bitmap.size.width), 1)
        guard let c = bitmap.colorAt(x: x * scale, y: y * scale)?.usingColorSpace(.sRGB) else { return nil }
        func byte(_ v: CGFloat) -> UInt32 { UInt32((v * 255).rounded()) }
        return byte(c.redComponent) << 16 | byte(c.greenComponent) << 8 | byte(c.blueComponent)
    }

    static func png(_ bitmap: NSBitmapImageRep) -> Data? { bitmap.representation(using: .png, properties: [:]) }
}

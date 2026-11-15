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

    /// The same view drawn until `drawn` holds for its bitmap, up to `tries` times, in one host
    /// in a window off screen, the run loop turned between: a screen whose scrolled content is
    /// laid out a turn later (as on a test runner) is seen once it has been. The last drawing is
    /// answered either way, for the caller's check.
    static func settled<V: View>(of view: V, size: CGSize, tries: Int = 20,
                                 until drawn: (NSBitmapImageRep) -> Bool) -> NSBitmapImageRep? {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: .aqua)
        // A window needs the app object, which a test run doesn't start on its own.
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        var last: NSBitmapImageRep?
        for _ in 0..<tries {
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            last = bitmap
            if drawn(bitmap) { return bitmap }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        return last
    }

    /// The colour at a point of `bitmap`, as `0xRRGGBB`, with the point's origin at the top left.
    static func hex(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> UInt32? {
        let scale = bitmap.pixelsWide / max(Int(bitmap.size.width), 1)
        guard let c = bitmap.colorAt(x: x * scale, y: y * scale)?.usingColorSpace(.sRGB) else { return nil }
        func byte(_ v: CGFloat) -> UInt32 { UInt32((v * 255).rounded()) }
        return byte(c.redComponent) << 16 | byte(c.greenComponent) << 8 | byte(c.blueComponent)
    }

    /// The colour at a point both as the bitmap stores it and as sRGB. A Mac at a desk stores
    /// what it drew in its screen's colours, so the sRGB one is the colour drawn; a test runner's
    /// virtual screen stores the drawn numbers under its own profile, so the stored one is. A
    /// check of a colour drawn takes either.
    static func hexes(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> [UInt32] {
        let scale = bitmap.pixelsWide / max(Int(bitmap.size.width), 1)
        guard let c = bitmap.colorAt(x: x * scale, y: y * scale) else { return [] }
        func byte(_ v: CGFloat) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        func hex(_ c: NSColor) -> UInt32 { byte(c.redComponent) << 16 | byte(c.greenComponent) << 8 | byte(c.blueComponent) }
        var out: [UInt32] = []
        if c.colorSpace.colorSpaceModel == .rgb { out.append(hex(c)) }
        if let s = c.usingColorSpace(.sRGB) { out.append(hex(s)) }
        return out
    }

    static func png(_ bitmap: NSBitmapImageRep) -> Data? { bitmap.representation(using: .png, properties: [:]) }
}

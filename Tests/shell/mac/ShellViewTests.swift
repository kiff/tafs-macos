import AppKit
import SwiftUI

/// Whether a drawn colour is the one asked for, within the rounding of the display's colour space.
private func near(_ got: UInt32?, _ want: UInt32) -> Bool {
    guard let got else { return false }
    return [16, 8, 0].allSatisfy { abs(Int((got >> $0) & 0xFF) - Int((want >> $0) & 0xFF)) <= 2 }
}

let shellMacTests: [Test] = [
    Test("the shell draws the sidebar on the raised ground and the rest on the background") {
        for dark in [false, true] {
            let size = ShellView.minimumSize
            guard let bitmap = Snapshot.bitmap(of: ShellView(), size: size, dark: dark) else {
                throw Failure(description: "no bitmap")
            }
            let sidebar = Snapshot.hex(bitmap, x: 10, y: Int(size.height) - 10)
            let detail = Snapshot.hex(bitmap, x: Int(size.width) - 10, y: Int(size.height) - 10)
            try expect(near(sidebar, dark ? Palette.raised.dark : Palette.raised.light), "the raised ground, dark: \(dark)")
            try expect(near(detail, dark ? Palette.background.dark : Palette.background.light), "the background, dark: \(dark)")
        }
    },
    Test("a snapshot is a PNG") {
        guard let bitmap = Snapshot.bitmap(of: ShellView(), size: ShellView.minimumSize),
              let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
        try expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]), "the PNG signature")
    },
]

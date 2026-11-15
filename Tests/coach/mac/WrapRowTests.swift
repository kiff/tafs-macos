import AppKit
import SwiftUI

/// The choices' rows, which wrap rather than squeeze.
let coachWrapTests: [Test] = [
    Test("a card's choices wrap onto a second row when the first is full, as on the iPad") {
        // Six cells of 120 in 300: two fit a row (with 8 between), so the third starts the next.
        let row = WrapRow(count: 6) { _ in Color.red.frame(width: 120, height: 20) }
            .frame(width: 300, alignment: .topLeading)
        guard let bitmap = Snapshot.bitmap(of: row.frame(width: 300, height: 120, alignment: .topLeading), size: CGSize(width: 300, height: 120))
        else { throw Failure(description: "no bitmap") }
        func red(_ x: Int, _ y: Int) -> Bool { Snapshot.hex(bitmap, x: x, y: y).map { $0 >> 16 > 0xC0 && $0 & 0xFF < 0x60 } ?? false }
        try expect(red(10, 10), "the first row")
        try expect(red(10, 38), "a second row, under the first")
        try expect(!red(270, 10), "nothing past the width on the first row")
    },
]

import Foundation

let shellWindowSizeTests: [Test] = [
    Test("the first window opens at the iPad's frame on a screen that has room", {
        try expectEqual(WindowSize.firstLaunch(visible: CGSize(width: 2560, height: 1415)), CGSize(width: 1366, height: 1024))
    }),
    Test("on a smaller screen it takes nine tenths of it, never past the screen", {
        // A 13-inch laptop's visible area, under the menu bar and above the Dock.
        try expectEqual(WindowSize.firstLaunch(visible: CGSize(width: 1440, height: 875)), CGSize(width: 1296, height: 787))
    }),
    Test("never under the minimum, and with no screen read, the iPad's frame", {
        try expectEqual(WindowSize.firstLaunch(visible: CGSize(width: 800, height: 500)), WindowSize.minimum)
        try expectEqual(WindowSize.firstLaunch(visible: nil), WindowSize.first)
        try expect(WindowSize.first.width > WindowSize.minimum.width && WindowSize.first.height > WindowSize.minimum.height)
    }),
]

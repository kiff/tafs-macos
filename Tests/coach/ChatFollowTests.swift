import Foundation

let coachChatFollowTests: [Test] = [
    Test("at the end, what arrives is followed and no ↓ shows") {
        var f = ChatFollow()
        f.scrolled(foot: 600, height: 600)
        try expect(!f.showsJump, "the end shows")
        try expect(f.arrived(), "followed")
        try expect(!f.unseen, "nothing unseen")
    },
    Test("read back up, nothing moves: the ↓ shows, with its dot once something arrives below") {
        var f = ChatFollow()
        f.scrolled(foot: 1400, height: 600)
        try expect(f.showsJump && !f.unseen, "the ↓, no dot yet")
        try expect(!f.arrived(), "not followed: nothing moves under the reader")
        try expect(f.unseen, "the dot: something new below")
    },
    Test("the ↓ takes them to the latest; scrolling back to the end does too, and clears the dot") {
        var f = ChatFollow()
        f.scrolled(foot: 1400, height: 600)
        _ = f.arrived()
        f.jumped()
        try expect(!f.showsJump && !f.unseen, "at the latest")
        f.scrolled(foot: 1400, height: 600)
        _ = f.arrived()
        f.scrolled(foot: 610, height: 600)
        try expect(!f.showsJump && !f.unseen, "a line's rounding still counts as the end")
    },
    Test("before the view has a height, nothing changes") {
        var f = ChatFollow()
        f.scrolled(foot: 5000, height: 0)
        try expect(!f.showsJump, "unchanged")
    },
]

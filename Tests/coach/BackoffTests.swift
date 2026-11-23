import Foundation

let coachBackoffTests: [Test] = [
    Test("a wait doubles from its base up to its ceiling, with jitter of at most its fraction either way, never below none") {
        let b = Backoff(base: 2, ceiling: 15, reads: 30)
        try expectEqual((0..<6).map { b.wait($0, random: 0.5) }, [2, 4, 8, 15, 15, 15])
        try expectEqual(b.wait(0, random: 0), 1.6)
        try expectEqual(b.wait(0, random: 1), 2.4)
        try expectEqual(b.wait(3, random: 1), 18)
        try expectEqual(b.wait(-1, random: 0.5), 2)
        for n in 0..<40 {
            let w = b.wait(n)
            try expect(w >= 1.6 && w <= 18, "read \(n): \(w)")
        }
    },
    Test("Coach's waits are slow fallbacks with an end: an answer, a connection, and a start made on the phone") {
        try expectEqual(Backoff.answer.reads, 30)
        try expectEqual(Backoff.start.reads, 40)
        // About an hour for a start, then it stops: never a loop with no cap.
        let hour = (0..<Backoff.start.reads).map { Backoff.start.wait($0, random: 0.5) }.reduce(0, +)
        try expect(hour > 60 * 60 && hour < 90 * 60, "about an hour: \(hour)")
        try expect(Backoff.connection.ceiling >= 30 && Backoff.answer.ceiling >= 15, "never a fixed fast loop")
    },
]

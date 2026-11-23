import Foundation

let shellWindowReadsTests: [Test] = [
    Test("the window reads everything first, then held calls every wake and the lists every 5 minutes") {
        var reads = WindowReads()
        let t0 = Date(timeIntervalSince1970: 1_794_679_800)
        try expectEqual(reads.plan(now: t0), .all)
        try expectEqual(reads.plan(now: t0.addingTimeInterval(60)), .held)
        try expectEqual(reads.plan(now: t0.addingTimeInterval(240)), .held)
        try expectEqual(reads.plan(now: t0.addingTimeInterval(300)), .all)
        try expectEqual(reads.plan(now: t0.addingTimeInterval(360)), .held)
    },
    Test("in the background it keeps reading for 10 minutes, then nothing; back in front, everything once at once") {
        var reads = WindowReads()
        let t0 = Date(timeIntervalSince1970: 1_794_679_800)
        _ = reads.plan(now: t0)
        try expectEqual(reads.background(true, now: t0.addingTimeInterval(30)), .nothing)
        try expectEqual(reads.plan(now: t0.addingTimeInterval(90)), .held)
        try expectEqual(reads.plan(now: t0.addingTimeInterval(30 + 601)), .nothing)
        // A second "in the background" keeps the first time.
        _ = reads.background(true, now: t0.addingTimeInterval(500))
        try expectEqual(reads.plan(now: t0.addingTimeInterval(30 + 601)), .nothing)
        try expectEqual(reads.background(false, now: t0.addingTimeInterval(2000)), .all)
        try expectEqual(reads.plan(now: t0.addingTimeInterval(2060)), .held)
    },
    Test("a wake is a minute, ±20%: never the same second on every Mac") {
        try expectEqual(WindowReads.wait(random: 0.5), 60)
        try expectEqual(WindowReads.wait(random: 0), 48)
        try expectEqual(WindowReads.wait(random: 1), 72)
    },
]

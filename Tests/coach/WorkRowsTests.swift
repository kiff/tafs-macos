import Foundation

let coachWorkRowsTests: [Test] = [
    Test("tries of one step after a failure fold into one row with the last outcome, as the iPad's WorkLog.rows") {
        let rows = WorkRows.rows([("Connect Mail", .error), ("Connect Mail", .error), ("Connect Mail", .done), ("Read inbox", .done)], running: false)
        try expectEqual(rows, [.init(words: "Connect Mail", status: .done, tries: 3), .init(words: "Read inbox", status: .done, tries: 1)])
        // A step that worked and then runs again is a new row.
        try expectEqual(WorkRows.rows([("Read", .done), ("Read", .done)], running: false).map(\.tries), [1, 1])
    },
    Test("a failure is left out once something worked or while it runs, and kept when nothing worked") {
        let mixed: [(words: String, status: WorkRows.Status)] = [("Connect", .error), ("Look up", .done)]
        try expectEqual(WorkRows.rows(mixed, running: false).map(\.words), ["Look up"])
        let failed: [(words: String, status: WorkRows.Status)] = [("Connect", .error)]
        try expectEqual(WorkRows.rows(failed, running: false).map(\.status), [.error])
        try expectEqual(WorkRows.rows(failed, running: true), [])
        // Not made, and not tried again: it stays, and it isn't a failure.
        try expectEqual(WorkRows.rows([("Choose the tools", .notMade), ("Look up", .done)], running: false).map(\.status), [.notMade, .done])
    },
    Test("a message's work and the live steps are folded the same way; the step at work is no row") {
        let work = Thread.Work(ms: 9000, steps: [.init(words: "Connect", failed: true, why: "no", notMade: false),
                                                 .init(words: "Connect", failed: false, why: nil, notMade: false)])
        try expectEqual(work.rows, [.init(words: "Connect", status: .done, tries: 2)])
        var live = LiveAnswer()
        _ = live.take(.activity(words: "Connect…", call: "c1"))
        _ = live.take(.step(call: "c1", status: "error", why: "no"))
        _ = live.take(.activity(words: "Connect…", call: "c2"))
        try expectEqual(live.rows, [])
        _ = live.take(.step(call: "c2", status: "done", why: nil))
        _ = live.take(.activity(words: "Read…", call: "c3"))
        try expectEqual(live.rows, [.init(words: "Connect", status: .done, tries: 2)])
    },
    Test("a time shows on the first item, and on one an hour or more after the one before") {
        let json = #"""
        {"items":[
          {"type":"message","message":{"id":"m1","at":"2026-11-15T09:00:00Z","from":"owner","text":"a"}},
          {"type":"message","message":{"id":"m2","at":"2026-11-15T09:20:00Z","from":"taf","text":"b"}},
          {"type":"card","card":{"key":"k","at":"2026-11-15T10:20:00Z","component":{"id":"c","type":"notice","text":"c"}}},
          {"type":"message","message":{"id":"m4","from":"owner","text":"d"}},
          {"type":"message","message":{"id":"m5","at":"2026-11-15T12:00:00Z","from":"owner","text":"e"}}
        ]}
        """#
        let page = try JSONDecoder().decode(Thread.Page.self, from: Data(json.utf8))
        try expectEqual((0..<6).map { page.showsTime(at: $0) }, [true, false, true, false, true, false])
    },
    Test("a sign-in card carries its app, its note, and tafs cloud's words for its yes and no") {
        let json = #"{"items":[{"type":"card","card":{"key":"k","component":{"id":"s","type":"sign_in","waits":"owner","service":"Sheets","note":"The vendor's page opens.","yes":"Sign in","no":"Not now"}}}]}"#
        guard case .card(let card, _) = try JSONDecoder().decode(Thread.Page.self, from: Data(json.utf8)).items[0] else { throw Failure(description: "no card") }
        try expectEqual([card.service, card.note, card.yes, card.no], ["Sheets", "The vendor's page opens.", "Sign in", "Not now"])
    },
]

import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

/// A brief as tafs cloud's route sends it (kiff/tafs `docs/api.md`, `GET /v1/brief`), with the
/// iPad's richer parts (a recommendation, a next move, a mission's done cases) where it adds them.
let briefAnswer = #"""
{"at":"2026-11-16T07:00:00.000Z","next_at":"2026-11-16T17:00:00.000Z",
 "decisions":[
  {"id":"connection:taf_2:stripe","question":"Stripe needs signing in again","answers":[{"words":"Sign in again","answer":"sign_in"}],"meanwhile":"Payouts wait.","urgent":true,"now_why":"This can't wait: the payouts stop at 12:00.","ref":{"kind":"connection","id":"stripe","taf":"taf_2"}},
  {"id":"hold:h_1","question":"Refund €180 to Ana?","answers":[{"words":"Approve","answer":"approve","recommended":true},{"words":"Refuse","answer":"refuse","decline":true}],"why":"It's within her order.","meanwhile":"Ana waits.","deadline":"by 12:00","urgent":false,"later":{"words":"Later"},"ref":{"kind":"hold","id":"h_1","taf":"taf_1"}},
  {"id":"step:ho_9","question":"Sign the delivery note","answers":[{"words":"Done","answer":"done"},{"words":"Skip","answer":"skip"}],"meanwhile":"","urgent":false,"later":{"words":"Later"},"ref":{"kind":"step","id":"ho_9","taf":"taf_1"}},
  {"id":"","question":"No id","answers":[{"words":"Yes","answer":"yes"}]},
  {"id":"no-answers","question":"Nothing to answer","answers":[]},
  "not a decision"],
 "more":{"count":2,"words":"2 more decisions"},
 "done":[{"mission":{"id":"m_1","name":"Late invoices"},"cases":[{"name":"INV-0412","words":"Paid","state":"closed"},{"words":"Reminder sent","state":"waiting","next_check":"Tue"}],"value":"€3,400 due back","log":"m_1"},{"mission":"Empty","cases":[]}],
 "next_move":{"words":"Chase the two oldest invoices","start":"Start","dismiss":"Not now"},
 "rest":{"count":4,"words":"4 things need nothing now"},
 "labels":[{"id":"lab_money","name":"Money","color":"money","count":2,"waiting":1}],
 "words":{"title":"Your brief","decisions":"Decisions · 3","done":"Done since last evening","rest":"Everything else","when":"Morning brief · 08:00","recommends":"Coach recommends","meanwhile":"Meanwhile:","evidence":"Evidence","urgent":"Urgent","next_move":"Next move"}}
"""#

let missionLogAnswer = #"""
{"items":[
  {"id":"e3","at":"2026-11-16T07:30:00.000Z","by":{"kind":"taf","name":"Invoices"},"kind":"delivered","kind_words":"delivered","words":"Sent 3 reminders.","evidence":[{"kind":"record","id":"r_1","words":"bill 0412"}],"value":"€1,200"},
  {"id":"e2","at":"2026-11-16T07:00:00Z","by":{"kind":"taf"},"kind":"handed","words":"Handed the dispute on.","removed":true},
  {"id":"e1","at":"2026-11-15T18:00:00Z","by":{"kind":"lead"},"kind":"decided","words":"Paused chasing for the holidays."},
  {"id":"e0","at":"2026-11-15T09:00:00Z","by":{"kind":"person","name":"Rae"},"kind":"note","words":"Ask before writing to Ana."},
  {"id":"draft","at":"2026-11-14T09:00:00Z","by":"taf","by_words":"Bills in → Payouts","kind":"handed","words":"Old draft shape."},
  {"id":"empty","at":"2026-11-14T09:00:00Z","words":""}],
 "before":"e0"}
"""#

private func decoded<T: Decodable>(_ body: String) throws -> T { try JSONDecoder().decode(T.self, from: Data(body.utf8)) }

let briefTests: [Test] = [
    Test("a mission's log offers Ask Coach as the iPad's, only where Coach may be used: its title in Coach's box (sources)") {
        let log = try String(contentsOf: URL(fileURLWithPath: "Sources/App/brief/MissionLogView.swift"), encoding: .utf8)
        try expect(log.contains("if let askCoach {") && log.contains(#"words("coach.ask")"#), "Ask Coach, when given")
        try expect(log.contains(#"words("mission.read_only")"#), "read only, newest first")
        let brief = try String(contentsOf: URL(fileURLWithPath: "Sources/App/brief/BriefView.swift"), encoding: .utf8)
        // Given only through startNextMove, which the window gives only to someone who may use Coach.
        try expect(brief.contains("askCoach: startNextMove.map { start in { log = nil; start(shown.title) } }"), "its title, the log closed")
        let window = try String(contentsOf: URL(fileURLWithPath: "Sources/App/shell/SignedInView.swift"), encoding: .utf8)
        try expect(window.contains("startNextMove: mayUseCoach ? startNextMove : nil"), "only for someone who may use Coach")
    },
    Test("the brief is read as tafs cloud sends it: a decision it can't draw is left out, never the brief") {
        let brief: Brief = try decoded(briefAnswer)
        try expectEqual(brief.decisions.map(\.id), ["connection:taf_2:stripe", "hold:h_1", "step:ho_9"])
        let hold = brief.decisions[1]
        try expectEqual(hold.recommended?.answer, "approve")
        try expectEqual(hold.answers.last?.decline, true)
        try expectEqual(hold.later, "Later")
        try expectEqual(hold.deadline, "by 12:00")
        try expectEqual(hold.ref, Brief.Ref(kind: "hold", id: "h_1", taf: "taf_1"))
        // The route's `now_why` is why it can't wait.
        try expectEqual(brief.decisions[0].cantWait, "This can't wait: the payouts stop at 12:00.")
        try expectEqual(brief.more?.words, "2 more decisions")
        try expectEqual(brief.rest?.words, "4 things need nothing now")
        try expectEqual(brief.labels.map(\.name), ["Money"])
        // The route sends the tab's name as `title`.
        try expectEqual(brief.words.tab, "Your brief")
        try expectEqual(brief.shown, true)
    },
    Test("Done keeps the mission's name, whether as words or as the route's {id, name}, and drops a mission with no case") {
        let brief: Brief = try decoded(briefAnswer)
        try expectEqual(brief.done.count, 1)
        try expectEqual(brief.done[0].mission, "Late invoices")
        try expectEqual(brief.done[0].log, "m_1")
        try expectEqual(brief.done[0].cases.map(\.closed), [true, false])
        try expectEqual(brief.done[0].cases[1].waiting, true)
        try expectEqual(brief.nextMove?.start, "Start")
    },
    Test("a recommendation shows only with its why, and an urgent decision never offers Later, whatever was sent") {
        var decision: Brief.Decision = try decoded(#"{"id":"hold:x","question":"Q","answers":[{"words":"Approve","answer":"approve","recommended":true}],"urgent":true,"later":{"words":"Later"},"ref":{"kind":"hold","id":"x"}}"#)
        try expectEqual(decision.recommended, nil)
        try expectEqual(decision.later, "Later")
        try expectEqual(decision.offersLater, nil)
        decision.urgent = false
        try expectEqual(decision.offersLater, "Later")
    },
    Test("a brief with nothing to show leaves Needs you as it is") {
        let empty: Brief = try decoded(#"{"decisions":[],"done":[],"rest":{"count":3,"words":"3 things"},"words":{"title":"Your brief"}}"#)
        try expectEqual(empty.shown, false)
    },
    Test("a held call opens on its own card with no answer chosen; a step on its step; anything else, Needs you") {
        let brief: Brief = try decoded(briefAnswer)
        try expectEqual(Brief.destination(of: brief.decisions[1]), .hold("h_1"))
        try expectEqual(Brief.destination(of: brief.decisions[2]), .step("ho_9"))
        try expectEqual(Brief.destination(of: brief.decisions[0]), .needsYou)
        try expectEqual(Brief.destination(of: Brief.Decision(id: "hold:", question: "Q", answers: [], ref: Brief.Ref(kind: "hold", id: ""))), .needsYou)
        try expectEqual(Brief.destination(of: Brief.Decision(id: "p", question: "Q", answers: [], ref: Brief.Ref(kind: "proposal", id: "p_1"))), .needsYou)
    },
    Test("Needs you beyond the brief is matched item by item, never by number") {
        let brief: Brief = try decoded(briefAnswer)
        // The brief shows h_1 and ho_9; h_2 isn't shown though the counts are equal.
        try expectEqual(Brief.needsYouBeyond(items: ["hold:h_1", "hold:h_2"], others: 0, shown: brief.decisions), 1)
        try expectEqual(Brief.needsYouBeyond(items: ["hold:h_1", "step:ho_9"], others: 0, shown: brief.decisions), 0)
        try expectEqual(Brief.needsYouBeyond(items: [], others: 2, shown: brief.decisions), 2)
    },
    Test("the brief's routes: the label as a query, Later's id as one escaped path segment, the log's mission escaped", awaiting: {
        let transport = CannedTransport([(200, briefAnswer), (200, #"{"id":"hold:h_1","until":"2026-11-16T17:00:00Z"}"#), (200, missionLogAnswer), (200, missionLogAnswer)])
        let cloud = CloudClient(transport: transport, session: session)
        _ = try await cloud.brief(label: "lab money")
        try await cloud.briefLater("hold:h/1")
        _ = try await cloud.missionLog("m 1")
        _ = try await cloud.missionLog("m_1", before: "e0")
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, [
            "GET /v1/brief?label=lab%20money",
            "POST /v1/brief/decisions/hold:h%2F1/later",
            "GET /v1/missions/m%201/log",
            "GET /v1/missions/m_1/log?before=e0",
        ])
        // Later sends nothing to sign: no device signature.
        try expectEqual(transport.sent[1].headers["KIFF-Device-Signature"], nil)
    }),
    Test("a mission's log reads tafs cloud's shape: by as an object, a removed taf, the lead and the person, the draft's by_words") {
        let log: MissionLog = try decoded(missionLogAnswer)
        try expectEqual(log.items.map(\.id), ["e3", "e2", "e1", "e0", "draft"])
        try expectEqual(log.before, "e0")
        let say: (String) -> String = { ["coach.title": "Coach", "common.you": "You", "needs_you.a_taf": "A taf"][$0] ?? $0 }
        try expectEqual(log.items.map { $0.by(say) }, ["Invoices", "A taf", "Coach", "Rae", "Bills in → Payouts"])
        try expectEqual(log.items[0].evidence.map(\.words), ["bill 0412"])
        try expectEqual(log.items[0].value, "€1,200")
        try expectEqual(log.items[1].removed, true)
        try expectEqual(log.items[0].at, Date(timeIntervalSince1970: 1_794_814_200))
    },
]

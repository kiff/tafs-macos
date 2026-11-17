import Foundation

private let words = try! Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))

/// Four tafs in tafs cloud's order: one ran an hour ago, one ran yesterday, one never ran, and one
/// waiting on the person.
let orderedHome = #"""
{"tafs":[
  {"id":"taf_old","name":"Invoices","kiff_agent":"a_old","state":"working","last_run":"2026-11-13T09:00:00Z"},
  {"id":"taf_never","name":"Payroll","kiff_agent":"a_never","state":"working","last_run":null},
  {"id":"taf_new","name":"Refunds","kiff_agent":"a_new","state":"working","last_run":"2026-11-14T08:00:00Z"},
  {"id":"taf_wait","name":"Deploys","kiff_agent":"a_wait","state":"waiting","waiting":1,"last_run":"2026-11-01T08:00:00Z"}]}
"""#

private func tafs(_ json: String) throws -> [Home.Taf] {
    try AccountClient.decoder.decode(Home.Page.self, from: Data(json.utf8)).tafs
}

private func group(_ json: String) throws -> People.Group { try JSONDecoder().decode(People.Group.self, from: Data(json.utf8)) }
private func person(_ json: String) throws -> People.Person { try JSONDecoder().decode(People.Person.self, from: Data(json.utf8)) }

let overviewListOrderTests: [Test] = [
    Test("the list's last_run is read, and none is none, as the iPad's CloudTaf.lastRun; the home.json contract's too") {
        let listed = try tafs(orderedHome)
        try expectEqual(listed.map { $0.lastRun != nil }, [true, false, true, true])
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: ".shared/contracts/home.json"))) as? [String: Any]
        let live = try AccountClient.decoder.decode(Home.Page.self, from: try JSONSerialization.data(withJSONObject: root?["answer"] ?? [:]))
        try expectEqual(live.tafs[0].lastRun, nil)
        // Its Last result before its runs are read: "Nothing yet", never "–".
        try expectEqual(Runs.line(lastRun: live.tafs[0].lastRun, words: words, time: { _ in "12:00" }), "Nothing yet")
    },
    Test("the order is the iPad's listedTafs: waiting on the person first, then the latest at work, then tafs cloud's order") {
        let listed = try tafs(orderedHome)
        try expectEqual(ListOrder.byRecent(listed).map(\.name), ["Deploys", "Refunds", "Invoices", "Payroll"])
        var order = ListOrder()
        // Before it's settled, the same.
        try expectEqual(order.listed(listed).map(\.name), ["Deploys", "Refunds", "Invoices", "Payroll"])
        order.show(listed)
        try expectEqual(order.listed(listed).map(\.name), ["Deploys", "Refunds", "Invoices", "Payroll"])
    },
    Test("the order is settled when the list's tafs change, not on every read; a taf newly waiting still goes first at once") {
        var order = ListOrder()
        order.show(try tafs(orderedHome))
        // Invoices ran just now: the same tafs, so the order stays while the person looks at it.
        let ran = orderedHome.replacingOccurrences(of: "2026-11-13T09:00:00Z", with: "2026-11-14T10:00:00Z")
        order.show(try tafs(ran))
        try expectEqual(order.listed(try tafs(ran)).map(\.name), ["Deploys", "Refunds", "Invoices", "Payroll"])
        // Payroll now waits on the person: to the top at once, the rest as they were.
        let waits = ran.replacingOccurrences(of: #""a_never","state":"working""#, with: #""a_never","state":"waiting","waiting":2"#)
        order.show(try tafs(waits))
        try expectEqual(order.listed(try tafs(waits)).map(\.name), ["Payroll", "Deploys", "Refunds", "Invoices"])
        // A new taf changes the list: the order settles again, by the latest run.
        let added = waits.replacingOccurrences(of: "]}", with: #",{"id":"taf_add","name":"Payouts","kiff_agent":"a_add","state":"working"}]}"#)
        order.show(try tafs(added))
        try expectEqual(order.listed(try tafs(added)).map(\.name), ["Deploys", "Payroll", "Invoices", "Refunds", "Payouts"])
    },
    Test("who uses a taf, under its name, as the iPad's usedBy: each group and person, then how many people; Not shared with none") {
        let support = try group(#"{"id":"g1","name":"Support","members":[{"subject":"u1","role":"manager"},{"subject":"u2","role":"member"},{"subject":"u3","role":"member"}],"agents":["a_new"]}"#)
        let people = [try person(#"{"subject":"u4","role":"member","status":"active","email":"ana@acme.com"}"#)]
        let grants = [Shares.Share(group: "g1"), Shares.Share(subject: "u4"), Shares.Share(subject: "u2"), Shares.Share(group: "gone")]
        try expectEqual(Shares.usedBy(grants, groups: [support], people: people, words: words), "Support, ana@acme.com, u2 · 4 people")
        try expectEqual(Shares.usedBy([Shares.Share(subject: "u4")], groups: [], people: people, words: words), "ana@acme.com · 1 person")
        try expectEqual(Shares.usedBy([], groups: [support], people: people, words: words), "Not shared")
        // Not read yet: no line.
        try expectEqual(Shares.usedBy(nil, groups: [support], people: people, words: words), nil)
    },
    Test("Last result reads the list's last_run before the runs, and the report's line once read, as the iPad's lastResult") {
        let at = Date(timeIntervalSince1970: 1_794_679_800)
        try expectEqual(Runs.line(lastRun: at, words: words, time: { _ in "08:00" }), "Last ran at 08:00")
        try expectEqual(Runs.line(lastRun: nil, words: words, time: { _ in "08:00" }), "Nothing yet")
        // Read with no report text: when it last ran, by the list's last_run.
        try expectEqual(Runs.line(latest: nil, newest: nil, report: nil, lastRun: at, words: words, time: { _ in "08:00" }), "Last ran at 08:00")
        try expectEqual(Runs.notRead("500", words: words), "Its runs couldn't be loaded. 500")
    },
    Test("the sidebar's Halt all shows where the iPad's does: for whoever manages Cards, while a taf runs, and whenever the account is halted") {
        let listed = try tafs(orderedHome)
        let agentOnly = try tafs(#"{"tafs":[{"name":"Old agent","kiff_agent":"a_x","state":"idle"}]}"#)
        try expectEqual(AccountHalt.shown(managesCards: true, tafs: listed, halt: .running), true)
        try expectEqual(AccountHalt.shown(managesCards: false, tafs: listed, halt: .halted), false)
        try expectEqual(AccountHalt.shown(managesCards: true, tafs: agentOnly, halt: .running), false)
        try expectEqual(AccountHalt.shown(managesCards: true, tafs: [], halt: .running), false)
        try expectEqual(AccountHalt.shown(managesCards: true, tafs: [], halt: .halted), true)
        try expectEqual(AccountHalt.shown(managesCards: true, tafs: [], halt: .halting), true)
        // Read with the list only when no taf runs: else the row reads it for itself.
        try expectEqual(AccountHalt.readsWithList(managesCards: true, tafs: []), true)
        try expectEqual(AccountHalt.readsWithList(managesCards: true, tafs: listed), false)
        try expectEqual(AccountHalt.readsWithList(managesCards: false, tafs: []), false)
    },
]

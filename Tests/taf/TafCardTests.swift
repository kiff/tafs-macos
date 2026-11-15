import Foundation

let tafWithCards = #"""
{"tafs":[{"id":"taf-1","name":"Unanswered emails","kiff_agent":"a1","color":0,"state":"idle","next_run_words":"Next run Mon 09:00","job_summary":"Every weekday at 9, lists inbox emails you haven't answered.",
  "card":{"ids":["c1"],"active":true,"cards":[
    {"id":"c1","title":"List inbox conversations","environment":"","live":true,"active":true,"expires":null,
     "rules":[{"action":"mail.list","label":"List inbox conversations","outside":"refuse","count_per_window":200,"window":"calendar_day","window_words":{"each":"a day","now":"today"}},
              {"action":"mail.me","label":"Read my mail address","outside":"hold","window":"calendar_day"},
              {"action":"mail.send","label":"Send a reply","outside":"ask_the_moon"}],
     "total":null,"calls":{"limit":200,"used":1,"window":"calendar_day","window_words":{"each":"a day","now":"today"}}},
    {"id":"c2","title":"Refunds","rules":[],"total":{"limit":{"minor":200000,"unit":"EUR","scale":2},"used":{"minor":4000,"unit":"EUR","scale":2},"window":"calendar_day","window_words":{"each":"a day","now":"today"}}},
    {"title":"no id"}
  ]}}]}
"""#

private func cards() throws -> [TafCard] {
    try AccountClient.decoder.decode(Home.Page.self, from: Data(tafWithCards.utf8)).tafs[0].cards
}

let tafCardTests: [Test] = [
    Test("a taf's Cards are read with their rules and what is left, and a Card that doesn't read is left out") {
        let page = try AccountClient.decoder.decode(Home.Page.self, from: Data(tafWithCards.utf8))
        try expectEqual(page.tafs[0].tafID, "taf-1")
        let all = page.tafs[0].cards
        try expectEqual(all.map(\.id), ["c1", "c2"])
        try expectEqual(all[0].rules.map(\.label), ["List inbox conversations", "Read my mail address", "Send a reply"])
        try expectEqual(all[0].rules[0].countPerWindow, 200)
        try expectEqual(all[0].rules[0].each, "a day")
        try expectEqual(all[0].rules.map(\.outside), [.refuse, .hold, .unknown])
        try expectEqual(all[0].expires, nil)
        // A Card may have no rules at all: it reads, with none.
        try expectEqual(all[1].rules, [])
        try expectEqual(all[1].active, true)
    },
    Test("the Card's figure is the limit less what was used, in KIFF's own numbers") {
        let all = try cards()
        try expectEqual(all[0].figure, .calls(left: 199, limit: 200, window: "today"))
        guard case .money(let left, let limit, let window)? = all[1].figure else { throw Failure(description: "no money figure") }
        try expectEqual(left.minor, 196_000)
        try expectEqual(limit.minor, 200_000)
        try expectEqual(window, "today")
    },
    Test("no figure is shown when KIFF couldn't say what was used, or when the units don't agree") {
        let unknown = #"{"id":"c","title":"t","calls":{"limit":200,"window":"calendar_day"}}"#
        try expectEqual(try JSONDecoder().decode(TafCard.self, from: Data(unknown.utf8)).figure, nil)
        let mixed = #"{"id":"c","title":"t","total":{"limit":{"minor":1000,"unit":"EUR","scale":2},"used":{"minor":100,"unit":"USD","scale":2},"window":"calendar_day"}}"#
        try expectEqual(try JSONDecoder().decode(TafCard.self, from: Data(mixed.utf8)).figure, nil)
        // A money Card whose money use is unknown says nothing, even with its calls known.
        let moneyUnknown = #"{"id":"c","title":"t","total":{"limit":{"minor":200000,"unit":"EUR","scale":2},"used":null,"window":"calendar_day"},"calls":{"limit":40,"used":1,"window":"calendar_day"}}"#
        try expectEqual(try JSONDecoder().decode(TafCard.self, from: Data(moneyUnknown.utf8)).figure, nil)
        let moneyMixed = #"{"id":"c","title":"t","total":{"limit":{"minor":1000,"unit":"EUR","scale":2},"used":{"minor":100,"unit":"USD","scale":2},"window":"calendar_day"},"calls":{"limit":40,"used":1,"window":"calendar_day"}}"#
        try expectEqual(try JSONDecoder().decode(TafCard.self, from: Data(moneyMixed.utf8)).figure, nil)
        let over = #"{"id":"c","title":"t","calls":{"limit":10,"used":14,"window":"calendar_day"}}"#
        try expectEqual(try JSONDecoder().decode(TafCard.self, from: Data(over.utf8)).figure, .calls(left: 0, limit: 10, window: ""))
    },
    Test("money is written as its language writes it, whole amounts without zeros") {
        try expectEqual(TafCard.Amount(minor: 196_000, unit: "EUR", scale: 2).written(language: "en"), "€1,960")
        try expectEqual(TafCard.Amount(minor: 1250, unit: "EUR", scale: 2).written(language: "en"), "€12.50")
        try expectEqual(TafCard.Amount(minor: 8000, unit: "USD", scale: 2).written(language: "en_US"), "$80")
        try expectEqual(TafCard.Amount(minor: 42, unit: nil, scale: 0).written(language: "en"), "42")
        try expectEqual(TafCard.Amount(minor: 300, unit: "points", scale: 0).written(language: "en"), "300 points")
    },
    Test("a Card's one line is what is left of its money, else of its calls, and nothing without a figure") {
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        let all = try cards()
        try expectEqual(all[1].line(words), "€1,960 left today of €2,000")
        try expectEqual(all[0].line(words), "199 calls left today of 200")
        let unknown = #"{"id":"c","title":"t","calls":{"limit":200,"window":"calendar_day"}}"#
        try expectEqual(try JSONDecoder().decode(TafCard.self, from: Data(unknown.utf8)).line(words), nil)
    },
    Test("a rule's limits read as the iPad's summary, held or refused above them, with the extra room apart") {
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        func rule(_ json: String) throws -> TafCard.Rule { try JSONDecoder().decode(TafCard.Rule.self, from: Data(json.utf8)) }
        let eur = { (minor: Int) in #"{"minor":\#(minor),"unit":"EUR","scale":2}"# }
        let held = try rule(#"{"label":"Refunds","outside":"hold","per_action":\#(eur(15000)),"per_window":\#(eur(200000)),"count_per_window":20,"window_words":{"each":"a day","now":"today"}}"#)
        try expectEqual(held.summary(words), "up to €150 each; more asks you first · €2,000 in total a day, then it asks you · 20 calls a day, then it asks you")
        try expectEqual(held.eachFact(words), "up to €150 each; more asks you first")
        let refused = try rule(#"{"label":"Pay","outside":"refuse","per_action":\#(eur(10000)),"per_window":\#(eur(100000)),"count_per_window":1,"window_words":{"each":"a day"}}"#)
        try expectEqual(refused.summary(words), "≤ €100 each · €1,000 a day · 1 call a day")
        let asksEach = try rule(#"{"label":"Read","outside":"hold","count_per_window":0,"window_words":{"each":"a day"}}"#)
        try expectEqual(asksEach.summary(words), "Each call asks you first")
        // The Card's own total, and the extra room apart: never one sum.
        let room = try rule(#"{"label":"Refunds","outside":"hold","per_window":\#(eur(230000)),"extra_room":\#(eur(30000)),"base_limit":\#(eur(200000)),"window_words":{"each":"a day","now":"today"}}"#)
        try expectEqual(room.summary(words), "€2,000 in total a day, then it asks you · +€300 extra room today")
        // Room with no base: per_window already holds it, so it is said once, never twice.
        let roomOnly = try rule(#"{"label":"Refunds","outside":"hold","per_window":\#(eur(230000)),"extra_room":\#(eur(30000)),"window_words":{"each":"a day","now":"today"}}"#)
        try expectEqual(roomOnly.summary(words), "€2,300 in total a day, then it asks you")
        try expectEqual(try rule(#"{"label":"x","outside":"hold"}"#).summary(words), "")
    },
    Test("a taf's state chip is the iPad's: its shared word and tone, none for a word unknown or a working taf needing you") {
        try expectEqual(TafState.chip(state: "working", attention: false)?.key, "taf.state.working")
        try expectEqual(TafState.chip(state: "working", attention: false)?.tone, .ok)
        try expect(TafState.chip(state: "working", attention: true) == nil, "a working taf that needs you shows no chip")
        try expectEqual(TafState.chip(state: "waiting", attention: true)?.tone, .amber)
        try expectEqual(TafState.chip(state: "idle", attention: false)?.key, "taf.state.ready")
        try expectEqual(TafState.chip(state: "paused", attention: false)?.tone, .soft)
        try expectEqual(TafState.chip(state: "stopped", attention: false)?.tone, .no)
        try expectEqual(TafState.chip(state: "halted", attention: false)?.key, "taf.state.halted")
        try expect(TafState.chip(state: "sleeping", attention: false) == nil, "an unknown word shows no chip")
        // Every chip's word is a shared line.
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        for state in ["working", "waiting", "idle", "paused", "stopped", "revoked", "halted"] {
            guard let key = TafState.chip(state: state, attention: false)?.key else { throw Failure(description: state) }
            try expect(words(key) != key, key)
        }
    },
]

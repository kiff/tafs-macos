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

let tafTests: [Test] = [
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
]

import Foundation

/// "Allow this from now on" (kiff/tafs `docs/allow-from-now-on.md`): the app's own rule for the button, and the one
/// signature only over KIFF's draft as this Mac read it, when it is what was offered. The iPad's `AllowFromNowOnTests`,
/// case for case.
private let g = #""grants":"#
private let cap = #"{"quantity":"amount","max":15000,"unit":"EUR","scale":2}"#
private let raised = #"{"quantity":"amount","max":32000,"unit":"EUR","scale":2}"#
private let day = #"{"quantity":"amount","limit":50000,"window":"day","unit":"EUR","scale":2}"#

private func refund(_ caps: String...) -> String {
    #"{"action":"create_refund","per_action_max":[\#(caps.joined(separator: ","))]}"#
}

/// KIFF's draft: Card c1 revised to `after`, with `current` its terms in force, and anything `extra` adds.
private func card(_ after: String, _ current: String, extra: String = "", retires: String = "", from: String = "",
                  agent: String = #""agent_id":"refunds-1","#) -> String {
    #"{"id":"dr_9",\#(agent)"status":"draft","version":"v7","cards":[{"revises":"c1",\#(after),"current":{\#(current)}}\#(extra)]\#(retires)\#(from)}"#
}

private func draft(max: Int = 32000, extra: String = "", retires: String = "") -> String {
    card("\(g)[\(refund(cap.replacingOccurrences(of: "15000", with: String(max))))]", "\(g)[\(refund(cap))]", extra: extra, retires: retires)
}

private func offerJSON(kind: String = "per_action", before: String = "15000", after: String = "32000", unit: String = #""unit":"EUR","#,
                       window: String = "") -> String {
    #"{"offer":{"changes":[{"mandate_id":"c1","kind":"\#(kind)","before":\#(before),"after":\#(after),\#(unit)\#(window)"words_before":"Refunds up to €150 each","words_after":"Refunds up to €320 each","rounded":false}],"would":{"calls":4,"words":"With this Card, 4 more refunds would have gone out on their own (€1,180)"},"draft":"dr_9","confirm_key":"critical","send_held":true,"round":{"after":35000,"words":"€350"}}}"#
}

private func offer(_ json: String = offerJSON()) throws -> CloudClient.AllowOffer {
    guard let offer = try JSONDecoder().decode(CloudClient.AllowAnswer.self, from: Data(json.utf8)).offer else { throw Failure(description: "no offer") }
    return offer
}

private func signs(_ draft: String, _ offerJSON: String = offerJSON(), agent: String? = "refunds-1", hold: String? = "ce_9") throws -> Bool {
    let d = try JSONDecoder().decode(AccountClient.Draft.self, from: Data(draft.utf8))
    return HoldAllow.matches(d, try offer(offerJSON), agent: agent, hold: hold, action: "create_refund")
}

private func held(_ outcomes: String?, extra: String = "") throws -> HeldCall {
    let breaches = outcomes.map { #","breaches":[\#($0)]"# } ?? ""
    let json = #"{"id":"ce_9","subject":"refunds-1","action":"create_refund","title":"Refund a payment","created_at":"2026-11-14T18:00:00Z","accounting_version":3"# + breaches + extra + "}"
    return try AccountClient.decoder.decode(HeldCall.self, from: Data(json.utf8))
}

private func expectNot(_ draft: String, _ offerJSON: String, _ what: String) throws {
    try expect(!(try signs(draft, offerJSON)), what)
}

private func expectNot(_ draft: String, _ what: String) throws {
    try expectNot(draft, offerJSON(), what)
}

let approvalsHoldAllowTests: [Test] = [
    Test("allow: current.id must be the Card it revises: another Card's id is refused, the same passes, none is as today") {
        let after = "\(g)[\(refund(raised))]", before = "\(g)[\(refund(cap))]"
        try expectNot(card(after, #""id":"c2","# + before), "a current that's another Card's")
        try expect(try signs(card(after, #""id":"c1","# + before)), "the Card it revises")
        try expect(try signs(card(after, before)), "no current.id: as today")
        // A Card marked unchanged is held to it too.
        let unchanged = #",{"revises":"c3","unchanged":true,\#(before),"current":{"id":"c9",\#(before)}}"#
        try expectNot(card(after, before, extra: unchanged), "an unchanged Card whose current is another's")
        // The same unchanged Card naming itself passes: the id is checked, never compared as a term.
        let itself = #",{"revises":"c3","unchanged":true,\#(before),"current":{"id":"c3",\#(before)}}"#
        try expect(try signs(card(after, before, extra: itself)), "an unchanged Card whose current is its own")
    },
    Test("the button shows on a hold a Card change can lift, and never on Coach's install, a Card unit request or a fill in Chrome") {
        try expect(HoldAllow.allowable(try held(#"{"outcome":"per_action_exceeded"}"#)), "a cap")
        try expect(HoldAllow.allowable(try held(#"{"outcome":"limit_reached"},{"outcome":"resource_not_on_card"}"#)), "a total and a scope")
        try expect(!HoldAllow.allowable(try held(#"{"outcome":"per_action_exceeded"},{"outcome":"action_not_on_card"}"#)), "one breach no Card change lifts")
        try expect(!HoldAllow.allowable(try held(#"{"outcome":"something_new"}"#)), "a breach this app doesn't know")
        try expect(!HoldAllow.allowable(try held("")), "no breach")
        try expect(!HoldAllow.allowable(try held(nil)), "no breaches listed")
        try expect(!HoldAllow.allowable(try held(#"{"outcome":"per_action_exceeded"}"#, extra: #","kind":"card_unit""#)), "a Card unit request")
        let install = try AccountClient.decoder.decode(HeldCall.self, from: Data(#"{"id":"ce_1","subject":"coach","action":"version_install","created_at":"2026-11-14T18:00:00Z","breaches":[{"outcome":"limit_reached"}]}"#.utf8))
        try expect(!HoldAllow.allowable(install), "Coach's install")
        try expect(!HoldAllow.allowable(try held(#"{"outcome":"per_action_exceeded"}"#, extra: #","browser":{"sealed_fill":{"sealed":"h"}}"#)),
                   "a fill in Chrome: allowing it from now on would skip the phone's release")
    },
    Test("the button waits for the service to say it's live: holds.allow in the account's capabilities") {
        func me(_ capabilities: String) throws -> Me {
            try JSONDecoder().decode(Me.self, from: Data(#"{"email":"rae@example.com","tenant_display_name":"Rae's","tenant_slug":"rae"\#(capabilities)}"#.utf8))
        }
        try expect(try me(#","capabilities":["cards.manage","holds.allow"]"#).allowIsLive, "listed")
        try expect(!(try me(#","capabilities":["cards.manage"]"#).allowIsLive), "not listed")
        try expect(!(try me("").allowIsLive), "no list at all")
    },
    Test("a draft that carries exactly the offered change matches; another figure, Card, retired Card or new Card doesn't") {
        try expect(try signs(draft()), "the offered change")
        try expectNot(draft(max: 50000), "another figure")
        try expectNot(draft(extra: #",{"revises":"c2","grants":[{"action":"list_charges"}],"current":{"grants":[{"action":"list_charges"},{"action":"create_refund"}]}}"#), "another Card changed")
        try expectNot(draft(retires: #","retires":[{"id":"c3"}]"#), "a Card retired")
        try expectNot(draft(extra: #",{"grants":[{"action":"create_refund"}]}"#), "a Card that revises none in force")
        let unchanged = #",{"revises":"c2","unchanged":true,"current":{"grants":[{"action":"list_charges"}]},"grants":[{"action":"list_charges"}]}"#
        try expect(try signs(draft(extra: unchanged)), "a Card left as it is doesn't count")
        try expectNot(draft(extra: #",{"revises":"c1","grants":[\#(refund(raised))],"current":{"grants":[\#(refund(cap))]}}"#), "the named Card twice")
        try expectNot(draft(), offerJSON(kind: "something_new"), "a kind of change the contract doesn't name")
    },
    Test("the changed Card reads as the Card in force with only the offered figure moved") {
        let count = cap.replacingOccurrences(of: "amount", with: "count")
        try expect(try signs(card("\(g)[\(refund(raised))]", "\(g)[\(refund(cap))]")), "the offered cap, nothing else")
        try expectNot(card("\(g)[\(refund(raised, count))]", "\(g)[\(refund(cap, count.replacingOccurrences(of: "15000", with: "3")))]"), "a second cap moved too")
        try expectNot(card("\(g)[\(refund(raised, cap.replacingOccurrences(of: "amount", with: "fee")))]", "\(g)[\(refund(cap))]"), "a cap added")
        try expectNot(card("\(g)[\(refund())]", "\(g)[\(refund(cap))]"), "a cap taken away")
        try expectNot(card("\(g)[\(refund(raised)),{\"action\":\"delete_customer\"}]", "\(g)[\(refund(cap))]"), "an action added")
        try expectNot(card("\(g)[\(refund(raised))]", "\(g)[\(refund(cap)),{\"action\":\"list_charges\"}]"), "an action taken away")
        let payout = #"{"action":"create_payout","per_action_max":[\#(cap)]}"#
        try expectNot(card("\(g)[\(refund(cap)),\(payout.replacingOccurrences(of: "15000", with: "32000"))]", "\(g)[\(refund(cap)),\(payout)]"), "the same figures on another action's cap")
        try expectNot(card("\(g)[\(refund(raised))],\"aggregates\":[\(day)]", "\(g)[\(refund(cap))]"), "a total added")
        try expectNot(card("\(g)[\(refund(raised))]", "\(g)[\(refund(cap))],\"aggregates\":[\(day)]"), "a total dropped")
        try expectNot(card("\(g)[\(refund(raised))],\"aggregates\":[\(day.replacingOccurrences(of: "day\"", with: "week\""))]", "\(g)[\(refund(cap))],\"aggregates\":[\(day)]"), "a total's window changed")
        try expectNot(card("\(g)[\(refund(raised))],\"aggregates\":[\(day.replacingOccurrences(of: "50000", with: "90000"))]", "\(g)[\(refund(cap))],\"aggregates\":[\(day)]"), "a total's figure changed")
        try expectNot(card("\(g)[\(refund(raised))],\"on_exceed\":\"refuse\"", "\(g)[\(refund(cap))],\"on_exceed\":\"owner\""), "what happens past a limit changed")
        try expectNot(card("\(g)[\(refund(raised))]", "\(g)[\(refund(cap))],\"on_exceed\":\"owner\""), "what happens past a limit dropped")
        try expect(try signs(card("\(g)[\(refund(raised).replacingOccurrences(of: "{\"action\"", with: "{\"title\":\"Refund\",\"action\""))],\"lines\":[\"x\"]", "\(g)[\(refund(cap))],\"lines\":[\"y\"]")),
                   "KIFF's lines and a grant's title are words, not terms")
    },
    Test("the unit must be the offer's exactly") {
        let usd = (raised.replacingOccurrences(of: "EUR", with: "USD"), cap.replacingOccurrences(of: "EUR", with: "USD"))
        try expectNot(card("\(g)[\(refund(usd.0))]", "\(g)[\(refund(usd.1))]"), "another currency")
        try expectNot(card("\(g)[\(refund(raised))]", "\(g)[\(refund(cap))]"), offerJSON(unit: ""), "an offer with no unit for a cap in euros")
        let bare = (#"{"quantity":"amount","max":32000}"#, #"{"quantity":"amount","max":15000}"#)
        try expectNot(card("\(g)[\(refund(bare.0))]", "\(g)[\(refund(bare.1))]"), "an offer in euros for a cap with no unit")
        try expect(try signs(card("\(g)[\(refund(bare.0))]", "\(g)[\(refund(bare.1))]"), offerJSON(unit: "")), "no unit on either")
    },
    Test("a total or a count changes only its figure, in its window") {
        let total = offerJSON(kind: "total", before: "50000", after: "60000")
        let now = "\(g)[\(refund(cap))],\"aggregates\":[\(day)]"
        func after(_ d: String) -> String { "\(g)[\(refund(cap))],\"aggregates\":[\(d)]" }
        try expect(try signs(card(after(day.replacingOccurrences(of: "50000", with: "60000")), now), total), "the offered total")
        try expectNot(card(after(day.replacingOccurrences(of: "50000", with: "70000")), now), total, "another figure")
        try expectNot(card(after(day.replacingOccurrences(of: "50000", with: "60000").replacingOccurrences(of: "day\"", with: "week\"")), now), total, "the window moved with it")
        try expectNot(card("\(g)[\(refund(raised))],\"aggregates\":[\(day.replacingOccurrences(of: "50000", with: "60000"))]", now), total, "the cap moved too")
        try expectNot(card(after(day.replacingOccurrences(of: "50000", with: "60000")), now), offerJSON(kind: "total", before: "50000", after: "60000", unit: #""unit":"USD","#), "another unit")
        // Two totals at the same figure, a day's and a month's: the offer's window says which one moves.
        let month = day.replacingOccurrences(of: "day\"", with: "month\"")
        let both = "\(g)[\(refund(cap))],\"aggregates\":[\(day),\(month)]"
        let dayMoved = "\(g)[\(refund(cap))],\"aggregates\":[\(day.replacingOccurrences(of: "50000", with: "60000")),\(month)]"
        let monthMoved = "\(g)[\(refund(cap))],\"aggregates\":[\(day),\(month.replacingOccurrences(of: "50000", with: "60000"))]"
        let daily = offerJSON(kind: "total", before: "50000", after: "60000", window: #""window":"day","#)
        try expect(try signs(card(dayMoved, both), daily), "the day's total")
        try expectNot(card(monthMoved, both), daily, "the month's total moved, the day's was offered")
    },
    Test("a resource change adds exactly the offered value, on the held action's scope") {
        func scoped(_ values: String, parameter: String = "account", action: String = "create_refund") -> String {
            #""grants":[{"action":"\#(action)","per_action_max":[\#(cap)],"resources":{"parameter":"\#(parameter)","values":[\#(values)]}}]"#
        }
        let resource = #"{"offer":{"changes":[{"mandate_id":"c1","kind":"resource","parameter":"account","value":"acct_2","words_before":"On acct_1","words_after":"On acct_1 and acct_2"}],"draft":"dr_9"}}"#
        let now = scoped(#""acct_1""#)
        try expect(try signs(card(scoped(#""acct_1","acct_2""#), now), resource), "the offered value")
        try expect(try signs(card(scoped(#""acct_2","acct_1""#), now), resource), "the order of the values doesn't matter")
        try expectNot(card(now, now), resource, "nothing added")
        try expectNot(card(scoped(#""acct_1","acct_2","acct_3""#), now), resource, "a second value added")
        try expectNot(card(scoped(#""acct_1","acct_3""#), now), resource, "another value added")
        try expectNot(card(scoped(#""acct_2""#), now), resource, "a value in force dropped")
        try expectNot(card(#""grants":[\#(refund(cap))]"#, now), resource, "the scope dropped: any value")
        try expectNot(card(scoped(#""acct_1","acct_2""#, parameter: "customer"), scoped(#""acct_1""#, parameter: "customer")), resource, "another parameter's scope")
        try expectNot(card(scoped(#""acct_1","acct_2""#, action: "create_payout"), scoped(#""acct_1""#, action: "create_payout")), resource, "another action's scope")
        try expectNot(card(scoped(#""acct_1","acct_2""#).replacingOccurrences(of: "15000", with: "32000"), now), resource, "a cap moved with it")
        try expectNot(card(scoped(#""acct_1","acct_2""#), now), resource.replacingOccurrences(of: #""value":"acct_2","#, with: ""), "an offer that names no value")
        try expectNot(card(scoped(#""acct_1","acct_1""#), scoped(#""acct_1""#)), resource.replacingOccurrences(of: "acct_2", with: "acct_1"), "a value already in force")
    },
    Test("every other term must be the Card in force's: scope, states, next steps, totals, times, holders, where, and what only a draft carries") {
        func grant(_ caps: String, _ more: String = "") -> String { #"{"action":"create_refund","per_action_max":[\#(caps)]\#(more)}"# }
        func differs(_ after: String, _ now: String, _ what: String) throws { try expectNot(card(after, now), what) }
        let scope = #","resources":{"parameter":"account","values":["acct_1"]}"#
        let whole = #","resources":{"parameter":"account","values":["acct_1"]},"entity_states":["paid"],"next_steps":["return_first"]"#
        let totals = #","aggregates":[{"quantity":"count","limit":20,"window":"day","measure":"attempts","per":"invoice_id"}],"on_exceed":"owner","subject":"refunds-1","valid_until":"2027-01-01T00:00:00Z","domain":"Shop","environment":"live""#
        try expect(try signs(card("\(g)[\(grant(raised, whole))]\(totals)", "\(g)[\(grant(cap, whole))]\(totals),\"subjects\":[\"refunds-1\"]")), "every term the same, the cap moved")
        try differs("\(g)[\(grant(raised))]", "\(g)[\(grant(cap, scope))]", "the scope dropped")
        try differs("\(g)[\(grant(raised, scope.replacingOccurrences(of: #"["acct_1"]"#, with: #"["acct_1","acct_2"]"#)))]", "\(g)[\(grant(cap, scope))]", "a value added to the scope")
        try differs("\(g)[\(grant(raised, scope.replacingOccurrences(of: "account", with: "customer")))]", "\(g)[\(grant(cap, scope))]", "the scope's parameter changed")
        try differs("\(g)[\(grant(raised, scope))]", "\(g)[\(grant(cap))]", "a scope added")
        try differs("\(g)[\(grant(raised))]", "\(g)[\(grant(cap, #","entity_states":["paid"]"#))]", "a state restriction dropped")
        try differs("\(g)[\(grant(raised, #","entity_states":["paid","refunded"]"#))]", "\(g)[\(grant(cap, #","entity_states":["paid"]"#))]", "a state added")
        try expect(try signs(card("\(g)[\(grant(raised))]", "\(g)[\(grant(cap, #","entity_states":[]"#))]")), "no states, written as none or as an empty list")
        try expect(try signs(card("\(g)[\(grant(raised))]", "\(g)[\(grant(cap, #","entity_states":null"#))]")), "no states, written as null")
        try differs("\(g)[\(grant(raised))]", "\(g)[\(grant(cap, #","next_steps":["return_first"]"#))]", "a next step dropped")
        try differs("\(g)[\(grant(raised, #","next_steps":["return_first","proof_first"]"#))]", "\(g)[\(grant(cap, #","next_steps":["return_first"]"#))]", "a next step added")
        let perItem = #"{"quantity":"count","limit":1,"window":"week","measure":"attempts","per":"invoice_id"}"#
        try differs("\(g)[\(grant(raised))],\"aggregates\":[\(perItem.replacingOccurrences(of: #","per":"invoice_id""#, with: ""))]", "\(g)[\(grant(cap))],\"aggregates\":[\(perItem)]", "a per-item total turned into one total")
        try differs("\(g)[\(grant(raised))],\"aggregates\":[\(perItem.replacingOccurrences(of: "invoice_id", with: "customer_id"))]", "\(g)[\(grant(cap))],\"aggregates\":[\(perItem)]", "a total kept per another parameter")
        try differs("\(g)[\(grant(raised))],\"aggregates\":[\(perItem.replacingOccurrences(of: "attempts", with: "effects"))]", "\(g)[\(grant(cap))],\"aggregates\":[\(perItem)]", "what a total counts changed")
        let sum = #"{"quantity":"sum(amount)","limit":50000,"window":"day"}"#
        try expect(try signs(card("\(g)[\(grant(raised))],\"aggregates\":[\(sum)]", "\(g)[\(grant(cap))],\"aggregates\":[\(sum.replacingOccurrences(of: "}", with: #","measure":"effects"}"#))]")), "a sum's measure left out reads as effects")
        try differs("\(g)[\(grant(raised))],\"aggregates\":[\(sum)]", "\(g)[\(grant(cap))],\"aggregates\":[\(sum.replacingOccurrences(of: "}", with: #","measure":"attempts"}"#))]", "a sum counting attempts in force, left out in the draft")
        let count = #"{"quantity":"count","limit":20,"window":"day"}"#
        try expect(try signs(card("\(g)[\(grant(raised))],\"aggregates\":[\(count)]", "\(g)[\(grant(cap))],\"aggregates\":[\(count.replacingOccurrences(of: "}", with: #","measure":"attempts"}"#))]")), "a count's measure left out reads as attempts")
        try differs("\(g)[\(grant(raised))],\"aggregates\":[\(count)]", "\(g)[\(grant(cap))],\"aggregates\":[\(count.replacingOccurrences(of: "}", with: #","measure":"effects"}"#))]", "a count counting effects in force, left out in the draft")
        try differs("\(g)[\(grant(raised))],\"valid_until\":\"2028-01-01T00:00:00Z\"", "\(g)[\(grant(cap))],\"valid_until\":\"2027-01-01T00:00:00Z\"", "its end moved later")
        try differs("\(g)[\(grant(raised))]", "\(g)[\(grant(cap))],\"valid_until\":\"2027-01-01T00:00:00Z\"", "its end dropped")
        try differs("\(g)[\(grant(raised))],\"valid_from\":\"2026-01-01T00:00:00Z\"", "\(g)[\(grant(cap))],\"valid_from\":\"2026-06-01T00:00:00Z\"", "its start moved earlier")
        try expect(try signs(card("\(g)[\(grant(raised))],\"valid_until\":\"2027-01-01T01:00:00+01:00\"", "\(g)[\(grant(cap))],\"valid_until\":\"2027-01-01T00:00:00Z\"")), "the same end, with another offset")
        try expect(try signs(card("\(g)[\(grant(raised))],\"valid_until\":\"2027-01-01T00:00:00.000Z\"", "\(g)[\(grant(cap))],\"valid_until\":\"2027-01-01T00:00:00Z\"")), "the same end, to the millisecond")
        try differs("\(g)[\(grant(raised))],\"valid_until\":\"2027-01-01T00:00:01Z\"", "\(g)[\(grant(cap))],\"valid_until\":\"2027-01-01T00:00:00Z\"", "its end one second later")
        try differs("\(g)[\(grant(raised))],\"valid_until\":\"next year\"", "\(g)[\(grant(cap))],\"valid_until\":\"2027-01-01T00:00:00Z\"", "an end that can't be read")
        try expectEqual(HoldAllow.Terms.instant(nil), "")
        try expectEqual(HoldAllow.Terms.instant("2027-01-01T00:00:00Z"), HoldAllow.Terms.instant("2026-12-31T19:00:00-05:00"))
        try expect(HoldAllow.Terms.instant("soon") != HoldAllow.Terms.instant("later"), "two texts that can't be read are never the same")
        let end = HoldAllow.Terms.instant("2027-01-01T00:00:00Z")
        try expect(end.hasPrefix("@"), "an instant's own form")
        try expect(HoldAllow.Terms.instant(end) != end, "an instant's own form, given as a time, is unreadable text")
        try differs("\(g)[\(grant(raised))],\"valid_until\":\"\(end)\"", "\(g)[\(grant(cap))],\"valid_until\":\"2027-01-01T00:00:00Z\"", "a draft whose end is that form as text")
        try differs("\(g)[\(grant(raised))],\"subject\":\"refunds-1\",\"subjects\":[\"refunds-1\",\"payouts-1\"]", "\(g)[\(grant(cap))],\"subject\":\"refunds-1\",\"subjects\":[\"refunds-1\"]", "a holder added")
        try differs("\(g)[\(grant(raised))],\"subject\":\"payouts-1\"", "\(g)[\(grant(cap))],\"subject\":\"refunds-1\",\"subjects\":[\"refunds-1\"]", "another first holder")
        try expect(try signs(card("\(g)[\(grant(raised))],\"subject\":\"refunds-1\"", "\(g)[\(grant(cap))],\"subject\":\"refunds-1\",\"subjects\":[\"refunds-1\",\"support-1\"]")),
                   "a draft that names only the same first holder keeps the Card's holders")
        try differs("\(g)[\(grant(raised))],\"domain\":\"other\"", "\(g)[\(grant(cap))],\"domain\":\"shop\"", "another domain")
        try differs("\(g)[\(grant(raised))],\"environment\":\"live\"", "\(g)[\(grant(cap))],\"environment\":\"test\"", "another environment")
        try differs("\(g)[\(grant(raised))],\"location\":\"Europe/Paris\"", "\(g)[\(grant(cap))],\"location\":\"America/New_York\"", "another time zone for its daily totals")
        try differs("\(g)[\(grant(raised))],\"hold_expiry\":\"24h\"", "\(g)[\(grant(cap))]", "how long a hold waits, set by the draft")
        try differs("\(g)[\(grant(raised))],\"revoked_at\":\"2026-11-12T00:00:00Z\"", "\(g)[\(grant(cap))]", "a draft that revokes")
    },
    Test("a Card marked unchanged is compared on every term, not trusted") {
        try expectNot(draft(extra: #",{"revises":"c2","unchanged":true,"current":{"grants":[{"action":"list_charges","resources":{"parameter":"account","values":["acct_1"]}}],"valid_until":"2027-01-01T00:00:00Z"},"grants":[{"action":"list_charges"}],"valid_until":"2027-01-01T00:00:00Z"}"#), "marked unchanged, with its scope dropped")
        try expectNot(draft(extra: #",{"revises":"c2","unchanged":true,"current":{"grants":[{"action":"list_charges"}],"valid_until":"2027-01-01T00:00:00Z"},"grants":[{"action":"list_charges"}],"valid_until":"2030-01-01T00:00:00Z"}"#), "marked unchanged, with its end moved later")
        try expectNot(draft(extra: #",{"revises":"c2","unchanged":true,"current":{"grants":[{"action":"list_charges"}]},"grants":[{"action":"list_charges"},{"action":"delete_customer"}]}"#), "marked unchanged, with an action added")
    },
    Test("the draft must be this held call's agent's, and from this hold when KIFF says") {
        let after = "\(g)[\(refund(raised))]", now = "\(g)[\(refund(cap))]"
        try expect(!(try signs(card(after, now, agent: #""agent_id":"payouts-1","#))), "another agent's draft")
        try expect(!(try signs(card(after, now), agent: nil)), "a held call with no agent")
        try expect(!(try signs(card(after, now), agent: "")), "a held call with an empty agent")
        try expect(!(try signs(card(after, now, from: #","from_hold":"ce_8""#))), "made from another held call")
        try expect(try signs(card(after, now, from: #","from_hold":"ce_9""#)), "made from this one")
    },
    Test("the offer is asked on the tap at tafs cloud's route, the draft is read from KIFF, and none reads no draft", awaiting: {
        let call = try held(#"{"outcome":"per_action_exceeded"}"#)
        var asked: [Bool] = [], drafts: [String] = []
        let read = try await HoldAllow.read(offer: { asked.append($0); return try JSONDecoder().decode(CloudClient.AllowAnswer.self, from: Data(offerJSON().utf8)) },
                                            draft: { drafts.append($0); return try JSONDecoder().decode(AccountClient.Draft.self, from: Data(draft().utf8)) },
                                            call: call, round: true)
        try expectEqual(asked, [true])
        try expectEqual(drafts, ["dr_9"])
        try expect(read.matches, "the draft as offered")
        try expectEqual(read.answer.offer?.would?.words, "With this Card, 4 more refunds would have gone out on their own (€1,180)")
        let none = try await HoldAllow.read(offer: { _ in try JSONDecoder().decode(CloudClient.AllowAnswer.self, from: Data(#"{"none":"never_rule","words":"A Card change can't let this go."}"#.utf8)) },
                                            draft: { _ in throw Failure(description: "a draft was read") }, call: call, round: false)
        try expectEqual(none.draft, nil)
        try expect(!none.matches, "nothing to sign")
        // An offer without its replay still reads.
        let bare = offerJSON().replacingOccurrences(of: #""would":{"calls":4,"words":"With this Card, 4 more refunds would have gone out on their own (€1,180)"},"#, with: "")
        try expectEqual(try offer(bare).would, nil)
        // tafs cloud's route, escaped: `{}` for the exact figure, `{"round":true}` for the rounded one.
        let transport = CannedTransport([(200, offerJSON()), (200, offerJSON())])
        let cloud = CloudClient(transport: transport, session: Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1"))
        _ = try await cloud.allowOffer(taf: "taf/1", exception: "ce_9", round: false)
        _ = try await cloud.allowOffer(taf: "taf_1", exception: "ce_9", round: true)
        try expectEqual(transport.sent.map { "\($0.method) \($0.path) \(String(decoding: $0.body, as: UTF8.self))" },
                        [#"POST /v1/tafs/taf%2F1/holds/ce_9/allow {}"#, #"POST /v1/tafs/taf_1/holds/ce_9/allow {"round":true}"#])
    }),
    Test("what the key signs is KIFF's plain draft confirm, at the version this Mac read: never the held call") {
        let d = try JSONDecoder().decode(AccountClient.Draft.self, from: Data(draft().utf8))
        let act = HoldAllow.confirm(d)
        try expectEqual(act, .confirmDraft(id: "dr_9", version: "v7"))
        try expectEqual(act.path, "/v1/me/agent-drafts/dr_9/confirm")
        try expectEqual(String(decoding: act.body, as: UTF8.self), #"{"version":"v7"}"#)
    },
]

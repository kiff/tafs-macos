import Foundation

private func english() throws -> Words { try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings")) }

private func grant(_ fields: String) throws -> AppConnections.Grant {
    try AccountClient.decoder.decode(AppConnections.Grant.self, from: Data(("{\"id\":\"g1\",\"status\":\"connected\",\"entry\":\"reviewed:stripe\"," + fields + "}").utf8))
}

/// A taf as Home lists it, with one Card whose rules are on `actions`.
private func taf(_ agent: String, _ id: String, _ name: String, actions: [String], active: Bool = true) throws -> Home.Taf {
    let rules = actions.map { #"{"action":"\#($0)","label":"\#($0)","outside":"hold"}"# }.joined(separator: ",")
    let json = #"{"kiff_agent":"\#(agent)","id":"\#(id)","name":"\#(name)","state":"idle","card":{"cards":[{"id":"c_\#(agent)","title":"Card","active":\#(active),"live":true,"rules":[\#(rules)]}]}}"#
    return try AccountClient.decoder.decode(Home.Taf.self, from: Data(json.utf8))
}

private func call(_ kind: String, action: String, taf: String, at: String, title: String, detail: String) -> String {
    #"{"id":"\#(title)","at":"\#(at)","kind":"\#(kind)","title":"\#(title)","detail":"\#(detail)","time":"09:00","taf":{"id":"\#(taf)","name":"T"},"call":{"action_name":"\#(action)","proposal_id":"p"}}"#
}

let connectionLinesTests: [Test] = [
    Test("a connection's Card actions are planque's tools when sent, else its request's minus Setup's own reads, as the iPad's") {
        let asked = try grant(#""request":{"server":"s","agent":"a_refunds","tools":[{"tool":"refund","name":"stripe_refund"},{"tool":"read","setup_reads":true}]}"#)
        try expectEqual(asked.cardActions, ["stripe_refund"])
        let held = try grant(#""tools":["stripe_charge"],"request":{"server":"s","agent":"a_refunds","tools":[{"tool":"refund","name":"stripe_refund"}]}"#)
        try expectEqual(held.cardActions, ["stripe_charge"])
    },
    Test("Also on …'s Card: the other tafs whose active Card has a rule on its actions, never its own, as the iPad's alsoStops") {
        let words = try english()
        let g = try grant(#""request":{"server":"s","agent":"a_refunds","tools":[{"tool":"refund","name":"stripe_refund"}]}"#)
        let tafs = [try taf("a_refunds", "t1", "Refunds", actions: ["stripe_refund"]),
                    try taf("a_leads", "t2", "Leads", actions: ["stripe_refund", "gmail_send"]),
                    try taf("a_old", "t3", "Old", actions: ["stripe_refund"], active: false),
                    try taf("a_mail", "t4", "Mail", actions: ["gmail_send"]),
                    try taf("a_ops", "t5", "Ops", actions: ["stripe_refund"])]
        let names = AppConnections.alsoOn(g, in: tafs)
        try expectEqual(names, ["Leads", "Ops"])
        try expectEqual(AppConnections.alsoOnLine(names, words), "Also on the Cards of " + words.list(["Leads", "Ops"]))
        try expectEqual(AppConnections.alsoOnLine(["Leads"], words), "Also on Leads' Card")
        try expectEqual(AppConnections.alsoOnLine([], words), nil)
        // Remove access names them, as the iPad's DisconnectWords.
        try expect(AppConnections.disconnectTitle("Stripe", taf: "Refunds", alsoStops: names, words).contains("Leads"), "the title names them")
        try expectEqual(AppConnections.alsoOn(try grant(#""request":{"server":"s","agent":"a_refunds","tools":[]}"#), in: tafs), [])
    },
    Test("a connection's last failed call: the newest not done on its tools, its own taf's first, in tafs cloud's words") {
        let words = try english()
        let g = try grant(#""request":{"server":"s","agent":"a_refunds","tools":[{"tool":"refund","name":"stripe_refund"}]}"#)
        let page = #"{"q":"","entries":["# + [
            call("not_done", action: "stripe_refund", taf: "t2", at: "2026-11-24T09:30:00Z", title: "Refund (Leads)", detail: "Stripe was down"),
            call("not_done", action: "stripe_refund", taf: "t1", at: "2026-11-24T08:00:00Z", title: "Refund", detail: "Signed out of Stripe"),
            call("done", action: "stripe_refund", taf: "t1", at: "2026-11-24T10:00:00Z", title: "Refund done", detail: "Done"),
            call("not_done", action: "gmail_send", taf: "t1", at: "2026-11-24T11:00:00Z", title: "Email", detail: "Gmail failed"),
        ].joined(separator: ",") + #"],"groups":[]}"#
        let record = try AccountClient.decoder.decode(Record.Page.self, from: Data(page.utf8)).entries
        try expectEqual(record.map(\.action), ["stripe_refund", "stripe_refund", "stripe_refund", "gmail_send"])
        try expectEqual(AppConnections.lastFailure(g, record: record, ownTaf: "t1", words), "Last failed: Refund · Signed out of Stripe")
        try expectEqual(AppConnections.lastFailure(g, record: record, ownTaf: "t9", words), "Last failed: Refund (Leads) · Stripe was down")
        try expectEqual(AppConnections.lastFailure(g, record: [], ownTaf: "t1", words), nil)
    },
]

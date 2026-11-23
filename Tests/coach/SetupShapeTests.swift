import Foundation

private let words = try! Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))

private func page(_ cards: [String]) throws -> Thread.Page {
    let items = cards.map { #"{"type":"card","card":"# + $0 + "}" }.joined(separator: ",")
    return try JSONDecoder().decode(Thread.Page.self, from: Data((#"{"items":["# + items + "]}").utf8))
}

private func grants(_ json: String) throws -> [AppConnections.Grant] {
    try AccountClient.decoder.decode([AppConnections.Grant].self, from: Data(json.utf8))
}

/// planque's grants for Stripe (connected, with its tools), Qonto (signed in), Shippo (failed) and Gmail (waiting).
private let shapeGrants = #"""
[{"id":"g_stripe","status":"connected","vendor":"Stripe","request":{"server":"mcp.stripe.com","agent":"a","tools":[{"tool":"create_refund","name":"stripe__create_refund"},{"tool":"list_charges"}]}},
 {"id":"g_qonto","status":"listed","vendor":"Qonto","request":{"server":"mcp.qonto.com","agent":"a"}},
 {"id":"g_shippo","status":"failed","status_words":"Shippo refused the sign-in","vendor":"Shippo","request":{"server":"mcp.shippo.com","agent":"a"}},
 {"id":"g_gmail","status":"approved","vendor":"Gmail","request":{"server":"gmail","agent":"a"}}]
"""#

let coachShapeTests: [Test] = [
    Test("without a plan, what Coach asked makes the steps, each where it stands", awaiting: {
        let thread = try page([
            #"{"key":"k1","answer":{"state":"answered","words":"Approved","answer":"approved"},"component":{"id":"a1","type":"approval","grant":"g_stripe","waits":"owner"}}"#,
            #"{"key":"k2","answer":{"state":"answered","words":"Declined"},"component":{"id":"a2","type":"approval","service":"Gmail","waits":"owner"}}"#,
            #"{"key":"k3","answer":{"state":"wrote","words":"x"},"component":{"id":"c1","type":"confirm","title":"Refund above €100?","waits":"owner"}}"#,
            #"{"key":"k4","component":{"id":"n1","type":"notice","title":"Note"}}"#,
            #"{"key":"k5","component":{"id":"s1","type":"sign_in","grant":"g_qonto","waits":"owner"}}"#,
            #"{"key":"k6","component":{"id":"a3","type":"approval","waits":"owner"}}"#,
        ])
        let shape = SetupShape(page: thread, grants: try grants(shapeGrants), drafts: [:], words)
        try expectEqual(shape.steps.map(\.label), ["Approve Stripe", "Approve Gmail", "Refund above €100?", "Sign in at Qonto", "Approve the connection"])
        try expectEqual(shape.steps.map(\.state), [.done, .skipped, .skipped, .done, .needsYou])
        try expectEqual(shape.progress(words), "Plan · 2 of 5")
        try expectEqual(shape.steps.map(\.mark), ["done", "pending", "pending", "done", "active"])
    }),
    Test("with a plan, its active step needs you while a card waits", awaiting: {
        let plan = #"{"key":"p","component":{"id":"plan","type":"steps","title":"Connect Stripe","steps":[{"label":"Read your shop","status":"done"},{"label":"Connect Stripe","status":"active"},{"label":"Hand it over","status":"pending"},{"label":"Old","status":"skipped"}]}}"#
        let waiting = #"{"key":"k","component":{"id":"a","type":"approval","grant":"g_gmail","waits":"owner"}}"#
        let shape = SetupShape(page: try page([plan, waiting]), grants: try grants(shapeGrants), drafts: [:], words)
        try expectEqual(shape.title, "Connect Stripe")
        try expectEqual(shape.steps.map(\.state), [.done, .needsYou, .toDo, .skipped])
        let none = SetupShape(page: try page([plan]), grants: [], drafts: [:], words)
        try expectEqual(none.steps.map(\.state), [.done, .now, .toDo, .skipped])
        try expectEqual(SetupShape.waiting(in: try page([plan, waiting]), grants: []), "k")
    }),
    Test("a tool reads where its grant stands, once each, with its tools once connected", awaiting: {
        let thread = try page(["g_stripe", "g_qonto", "g_stripe", "g_shippo", "g_gmail", "g_unknown"].enumerated().map { i, g in
            #"{"key":"k\#(i)","component":{"id":"a\#(i)","type":"approval","grant":"\#(g)","waits":"owner"}}"#
        })
        let shape = SetupShape(page: thread, grants: try grants(shapeGrants), drafts: [:], words)
        try expectEqual(shape.tools.map(\.vendor), ["Stripe", "Qonto", "Shippo", "Gmail"])
        try expectEqual(shape.tools.map(\.state), [.connected, .signedIn, .failed("Shippo refused the sign-in"), .waiting])
        try expectEqual(shape.tools.map(\.actions), [["stripe__create_refund", "list_charges"], [], [], []])
        try expectEqual(shape.tools.map { SetupShape.status($0.state, words).0 }, ["Connected", "Signed in", "Not connected", "Waiting for you"])
        try expectEqual(SetupShape.status(.connected, words).1, .ok)
        try expectEqual(SetupShape.status(.failed(nil), words).1, .no)
    }),
    Test("the Card is the latest draft an approval names, never Setup's own, and the name once handed over", awaiting: {
        let thread = try page([
            #"{"key":"k1","component":{"id":"a1","type":"approval","draft":"drf_setup","waits":"owner"}}"#,
            #"{"key":"k2","component":{"id":"a2","type":"approval","draft":"drf_s1","waits":"owner"}}"#,
            #"{"key":"k3","component":{"id":"done","type":"result","taf":{"name":"Refunds","agent":"refunds-x"}}}"#,
        ])
        let refunds = try AccountClient.decoder.decode(AccountClient.Draft.self, from: Data(approvalDraftAnswer.utf8))
        let setup = try AccountClient.decoder.decode(AccountClient.Draft.self, from: Data(#"{"id":"drf_setup","agent_id":"setup","status":"confirmed","version":"1","no_tools":true}"#.utf8))
        let shape = SetupShape(page: thread, grants: [], drafts: ["drf_s1": refunds, "drf_setup": setup], words)
        try expectEqual(shape.name, "Refunds")
        try expectEqual(shape.card, SetupShape.Card(title: "Refunds assistant's Card", lines: refunds.lines(words), confirmed: false))
        let onlySetup = SetupShape(page: thread, grants: [], drafts: ["drf_setup": setup], words)
        try expectEqual(onlySetup.card, nil)
    }),
    Test("an empty conversation has taken no shape, and the panel shows from 780 across in Coach's own chat", awaiting: {
        let empty = SetupShape(page: .empty, grants: [], drafts: [:], words)
        try expectEqual(empty.isEmpty, true)
        try expectEqual(SetupShape.shows(width: 779, coach: true), false)
        try expectEqual(SetupShape.shows(width: 780, coach: true), true)
        try expectEqual(SetupShape.shows(width: 1200, coach: false), false)
    }),
]

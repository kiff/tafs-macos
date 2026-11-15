import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

let tafTabsTests: [Test] = [
    Test("a taf's Activity and Setup are read only, by the taf's id, with the filter asked for", awaiting: {
        let transport = CannedTransport([(200, #"{"entries":[],"filters":[],"filter":"held"}"#), (200, #"{"workflow":{"title":"Workflow"}}"#)])
        let client = CloudClient(transport: transport, session: session)
        let activity = try await client.activity(of: "taf-1", filter: "held")
        _ = try await client.setup(of: "taf-1")
        try expectEqual(transport.sent.map(\.method), ["GET", "GET"])
        try expectEqual(transport.sent.map(\.path), ["/v1/tafs/taf%2D1/activity?filter=held", "/v1/tafs/taf%2D1/setup"])
        try expectEqual(activity.groups, [])
    }),
    Test("a call that doesn't read is left out, never the day; a list that isn't one is unreadable") {
        let json = #"{"groups":[{"id":"d1","title":"Today","entries":[{"id":"e1","kind":"held","title":"Pay Atlas"},{"id":"e2"},7]},{"id":"d2","title":"Empty","entries":[{"title":"no id"}]}],"filters":[{"id":"all","title":"All"},{"id":"x"}]}"#
        let activity = try JSONDecoder().decode(TafActivity.self, from: Data(json.utf8))
        try expectEqual(activity.groups.map(\.id), ["d1"])
        try expectEqual(activity.groups[0].entries.map(\.id), ["e1"])
        try expectEqual(activity.filters.map(\.id), ["all"])
        try expect((try? JSONDecoder().decode(TafActivity.self, from: Data(#"{"filters":[]}"#.utf8))) == nil, "no calls at all")
        try expect((try? JSONDecoder().decode(TafSetup.self, from: Data(#"{"connections":[]}"#.utf8))) == nil, "no part of a Setup")
    },
    Test("the next page is asked for with its cursor and filter, and a day carried over continues the last one", awaiting: {
        let first = #"{"groups":[{"id":"d1","title":"Today","entries":[{"id":"e1","kind":"done","title":"A"}]}],"filters":[],"filter":"held","next_cursor":"c 2"}"#
        let second = #"{"groups":[{"id":"d1b","title":"","entries":[{"id":"e1","kind":"done","title":"A"},{"id":"e2","kind":"held","title":"B"}]},{"id":"d2","title":"Yesterday","entries":[{"id":"e3","kind":"refused","title":"C"}]}],"filters":[],"filter":"held","end_words":"Nothing older"}"#
        let transport = CannedTransport([(200, first), (200, second)])
        let client = CloudClient(transport: transport, session: session)
        var page = try await client.activity(of: "taf-1", filter: "held")
        try expectEqual(page.nextCursor, "c 2")
        try expectEqual(page.endWords, nil)
        let cursor = page.nextCursor
        let next = try await client.activity(of: "taf-1", filter: "held", cursor: cursor)
        try expectEqual(transport.sent[1].path, "/v1/tafs/taf%2D1/activity?filter=held&cursor=c%202")
        page.append(next)
        // The untitled first day is the last day carried on; a call already listed isn't twice.
        try expectEqual(page.groups.map(\.title), ["Today", "Yesterday"])
        try expectEqual(page.groups[0].entries.map(\.id), ["e1", "e2"])
        try expectEqual(page.nextCursor, nil)
        try expectEqual(page.endWords, "Nothing older")
    }),
    Test("a call's dot follows the iPad's kinds, any other kind amber; its amount is tafs cloud's words") {
        let kinds = ["done", "approved", "held", "refused", "not_done", "sending", "unknown", "revoked", "new_kind"]
        let entries = kinds.map { #"{"id":"\#($0)","kind":"\#($0)","title":"T","amount_text":"€40"}"# }.joined(separator: ",")
        let activity = try JSONDecoder().decode(TafActivity.self, from: Data((#"{"entries":["# + entries + "]}").utf8))
        let tones = activity.groups[0].entries.map(\.tone)
        try expectEqual(tones, [.ok, .ok, .amber, .no, .no, .amber, .amber, .no, .amber])
        try expectEqual(activity.groups[0].entries[0].amountText, "€40")
    },
    Test("Setup's notes show the latest note, as tafs cloud sends it") {
        let json = #"{"memory":{"count":1,"title":"1 note","latest":"Refunds over €100 need the receipt"},"workflow":{"title":"Workflow","summary":"Reads cases"}}"#
        let setup = try JSONDecoder().decode(TafSetup.self, from: Data(json.utf8))
        try expectEqual(setup.memory, TafSetup.Part(title: "1 note", summary: "Refunds over €100 need the receipt"))
        try expectEqual(setup.workflow, TafSetup.Part(title: "Workflow", summary: "Reads cases"))
    },
    Test("connections are one node per app: the one with actions, else one to sign in again, else the first") {
        func app(_ id: String, _ name: String, count: Int = 0, reconnect: Bool = false) -> String {
            #"{"id":"\#(id)","name":"\#(name)","action_count":\#(count),"reconnect":\#(reconnect)}"#
        }
        let json = "{\"workflow\":{\"title\":\"W\"},\"connections\":[" + [app("s1", "Stripe"), app("g1", "Gmail", reconnect: true), app("s2", "Stripe", count: 2), app("g2", "Gmail"), app("q1", "Qonto")].joined(separator: ",") + "]}"
        let setup = try JSONDecoder().decode(TafSetup.self, from: Data(json.utf8))
        let nodes = TafSetup.nodes(setup.connections)
        try expectEqual(nodes.map(\.app.id), ["s2", "g1", "q1"])
        try expectEqual(nodes.map { $0.others.map(\.id) }, [["s1"], ["g2"], []])
    },
    Test("an app's Activity is asked for with tafs cloud's query as written, and only a query is sent", awaiting: {
        let transport = CannedTransport([(200, #"{"entries":[]}"#), (200, #"{"entries":[]}"#)])
        let client = CloudClient(transport: transport, session: session)
        _ = try await client.activity(of: "taf-1", query: "tools=fetch_emails&from=2026-10-22T10%3A00%3A00.000Z")
        _ = try await client.activity(of: "taf-1", query: "x=1#frag/../../v1/other")
        try expectEqual(transport.sent.map(\.path), ["/v1/tafs/taf%2D1/activity?tools=fetch_emails&from=2026-10-22T10%3A00%3A00.000Z",
                                                     "/v1/tafs/taf%2D1/activity?filter=all"])
    }),
    Test("a halt reads as tafs cloud sends it, with the iPad's words for where it stands", awaiting: {
        let halting = #"{"halt":{"state":"halting","runtime":true,"kiff":true,"planque":false}}"#
        let halted = #"{"halt":{"state":"halted","halted_at":"2026-11-15T10:30:00Z","runtime":true,"kiff":true,"planque":true,"account":true}}"#
        let transport = CannedTransport([(200, halting), (200, halted), (200, #"{"halt":{"state":"running"}}"#)])
        let client = CloudClient(transport: transport, session: session)
        let first = try await client.halt("taf-1")
        let second = try await client.halted("taf-1")
        let all = try await client.halt(nil)
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["POST /v1/tafs/taf%2D1/halt", "GET /v1/tafs/taf%2D1/halt", "POST /v1/halt"])
        try expectEqual(first, Halt(state: .halting, runtime: true, kiff: true, planque: false))
        try expectEqual(second.account, true)
        try expect(second.haltedAt != nil, "since when")
        try expectEqual(all, .running)
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        try expectEqual(Halt.running.headline(words), "Running")
        try expectEqual(first.headline(words), "Halting…")
        try expectEqual(second.headline(words), "Halted")
        try expectEqual(second.explanation(all: false, words, time: { _ in "11:30" }), "Since 11:30. Resuming starts only new work.")
        try expect(Halt.running.explanation(all: true, words, time: { _ in "" }).contains("your tafs"), "every taf")
        try expect((try? JSONDecoder().decode(Halt.self, from: Data(#"{"state":"paused"}"#.utf8))) == nil, "a state it doesn't know isn't one")
    }),
]

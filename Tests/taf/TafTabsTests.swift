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
]

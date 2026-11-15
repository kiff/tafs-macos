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
]

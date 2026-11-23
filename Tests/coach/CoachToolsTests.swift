import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let words = try! Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))

/// tafs cloud's `GET /v1/setup` at the pin, with Coach's tools to give (`setup-coach.json`).
private func contract() throws -> Data {
    let fixture = try Data(contentsOf: URL(fileURLWithPath: ".shared/contracts/setup-coach.json"))
    guard let root = try JSONSerialization.jsonObject(with: fixture) as? [String: Any], let answer = root["answer"] else {
        throw Failure(description: "setup-coach.json has no answer")
    }
    return try JSONSerialization.data(withJSONObject: answer)
}

private func tools(_ json: String) -> CoachTools? { CoachTools.read(Data(json.utf8)) }

let coachToolsTests: [Test] = [
    Test("the contract's tools read as the iPad reads them: the step's words, its groups and tools, and KIFF's words for Coach's Cards", awaiting: {
        let raw = try contract()
        guard let read = CoachTools.read(raw) else { throw Failure(description: "no tools read") }
        try expectEqual(read.state, "to_give")
        try expectEqual(read.showsRow, true)
        try expectEqual(read.step?.title, "Give Coach its tools")
        try expectEqual(read.rowWords(words), "Coach's tools are waiting for you · Give them")
        try expectEqual(read.notNow(words), "Not now")
        try expectEqual(read.step?.groups.first?.name, "Watch your tafs")
        try expectEqual(read.step?.groups.first?.tools.first?.name, "See your tafs")
        try expect((read.step?.groups.count ?? 0) >= 3, "every group is read")
        try expectEqual(read.stateLine(words), nil)
        // What the phone would sign is never kept here: only the words.
        let root = try JSONSerialization.jsonObject(with: raw) as? [String: Any]
        let said = (root?["tools"] as? [String: Any])?["card"] as? [String: Any]
        try expectEqual(read.cardTitle, said?["card_title"] as? String)
        try expectEqual(read.cards?.count, (said?["cards"] as? [Any])?.count)
    }),
    Test("Coach and its tools come from one read of GET /v1/setup, with no time zone, and nothing else is sent", awaiting: {
        let transport = CannedTransport([(200, String(decoding: try contract(), as: UTF8.self)), (200, #"{"setup":null}"#)])
        let client = CloudClient(transport: transport, session: session)
        let (coach, read) = try await client.coachAndTools()
        try expectEqual(coach?.name, "Coach")
        try expectEqual(read?.toGive, true)
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["GET /v1/setup"])
        try expectEqual(transport.sent[0].headers["X-Time-Zone"], nil)
        let (none, noTools) = try await client.coachAndTools()
        try expectEqual(none, nil)
        try expectEqual(noTools, nil)
        try expectEqual(transport.sent.count, 2)
        try expect(transport.sent.allSatisfy { $0.method == "GET" }, "the Mac builds no tools request: nothing is posted")
    }),
    Test("nothing once given or before tafs cloud says", awaiting: {
        try expectEqual(tools(#"{"tools":{"state":"given"}}"#)?.showsRow, false)
        try expect(tools(#"{"setup":{"id":"c","name":"Coach"}}"#) == nil, "no tools: no row")
        try expect(tools(#"{"tools":null}"#) == nil, "null tools: no row")
        try expect(tools("not json") == nil, "an answer that isn't JSON: no row")
    }),
    Test("the app's own words stand in only for a tafs cloud without them", awaiting: {
        let bare = tools(#"{"tools":{"state":"to_give","coach_tools_step":{"title":"  ","row":""}}}"#)
        try expectEqual(bare?.rowWords(words), "Coach's tools")
        try expectEqual(bare?.title(words), "Coach's tools")
        try expectEqual(bare?.notNow(words), "Not now")
        let said = tools(#"{"tools":{"state":"to_give","coach_tools_step":{"title":"Outils","row":"Donnez-les","not_now":"Plus tard"}}}"#)
        try expectEqual(said?.rowWords(words), "Donnez-les")
        try expectEqual(said?.title(words), "Outils")
        try expectEqual(said?.notNow(words), "Plus tard")
    }),
    Test("taken and unknown say why", awaiting: {
        try expectEqual(tools(#"{"tools":{"state":"taken","taken":"tafs_state"}}"#)?.stateLine(words),
                        "Coach can't have its tools yet: another tool in KIFF is named tafs_state. Rename or remove it in KIFF.")
        try expectEqual(tools(#"{"tools":{"state":"taken"}}"#)?.stateLine(words), words("coach.taken.unnamed"))
        try expectEqual(tools(#"{"tools":{"state":"new_one"}}"#)?.stateLine(words), words("coach.tools_unknown"))
        try expectEqual(tools(#"{"tools":{}}"#)?.state, "unknown")
    }),
    Test("a lenient step leaves out what it can't read; the batch's lines and the Cards only beside the body they'd sign", awaiting: {
        let read = tools(#"""
        {"tools":{"state":"to_give",
          "connect":{"body":{"connections":[]},"lines":["Read your tafs",7]},
          "card":{"body":{},"card_title":"Coach's Cards","cards":[{"label":"Watching","lines":["Up to 500 a day"]},{"lines":[]},5,{"card_title":"Run them"}]},
          "coach_tools_step":{"title":7,"groups":[{"name":"Watch","line":"See them","tools":[{"name":"See","does":"Read each taf","why":7},{"does":"no name"},3]},"odd"]}}}
        """#)
        try expectEqual(read?.connectLines, ["Read your tafs"])
        try expectEqual(read?.cardTitle, "Coach's Cards")
        try expectEqual(read?.cards, [CoachTools.CardWords(title: "Watching", lines: ["Up to 500 a day"]), CoachTools.CardWords(title: "Run them", lines: [])])
        try expectEqual(read?.step?.title, "")
        try expectEqual(read?.step?.groups, [CoachTools.Step.Group(name: "Watch", line: "See them", tools: [CoachTools.Step.Tool(name: "See", does: "Read each taf", why: "")])])
        let bodiless = tools(#"{"tools":{"state":"to_give","connect":{"lines":["x"]},"card":{"card_title":"C","cards":[{"title":"t"}]}}}"#)
        try expectEqual(bodiless?.connectLines, nil)
        try expectEqual(bodiless?.cards, nil)
    }),
]

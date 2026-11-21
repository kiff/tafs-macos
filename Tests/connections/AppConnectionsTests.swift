import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "acme/1", subject: "u1", deviceID: nil)

/// planque's grants as it sends them: two tafs' connections to Qonto, one waiting for its sign-in;
/// a removed taf's; one no taf here is named for; a provider's; one disconnected; another app's;
/// and one that doesn't read.
let grantsAnswer = #"""
{"grants":[
  {"id":"g1","status":"connected","title":"Qonto · Demo Shop","entry":"reviewed:qonto-invoicing","vendor":"Qonto","request":{"server":"mcp.qonto.com","agent":"a_refunds","tools":[]},"events":[]},
  {"id":"g2","status":"approved","entry":"reviewed:qonto-invoicing","request":{"server":"mcp.qonto.com","agent":"a_billing","tools":[]},"events":[]},
  {"id":"g3","status":"connected","entry":"reviewed:qonto-invoicing","agent_name":"Old refunds","status_words":"Connected","request":{"server":"mcp.qonto.com","agent":"a_gone"}},
  {"id":"g4","status":"needs_reconnect","account":"ops@shop.example","entry":"reviewed:qonto-invoicing","status_words":"Signed out by Qonto · sign in again","request":{"server":"mcp.qonto.com","agent":"a_unknown","kind":"api_key"}},
  {"id":"g5","status":"connected","title":"Qonto","entry":"other","request":{"server":"q","agent":"a_refunds","connector":{"provider":"p"}}},
  {"id":"g6","status":"disconnected","entry":"reviewed:qonto-invoicing","request":{"server":"q","agent":"a_refunds"}},
  {"id":"g7","status":"connected","entry":"connector:p:gmail","request":{"server":"g","agent":"a_refunds"}},
  {"id":"g8","status":"connected","title":"Qonto rows","entry":"reviewed:qonto-invoicing","used_by":["Refunds"],"health":{"state":"working","ok":true,"words":"Working · last used 09:12"},"actions":[],"request":{"server":"q","agent":"a_refunds"}},
  {"status":"connected"}
]}
"""#

private func app(_ fields: String) throws -> Apps.App {
    try AccountClient.decoder.decode(Apps.App.self, from: Data(("{\"entry\":\"reviewed:qonto-invoicing\",\"name\":\"Qonto\"," + fields + "}").utf8))
}

private func taf(_ agent: String, _ id: String?, _ name: String) throws -> Home.Taf {
    let tafID = id.map { ",\"id\":\"\($0)\"" } ?? ""
    return try AccountClient.decoder.decode(Home.Taf.self, from: Data("{\"kiff_agent\":\"\(agent)\"\(tafID),\"name\":\"\(name)\",\"state\":\"idle\"}".utf8))
}

private func source(_ transport: CannedTransport, proof: String? = "t=1700000000000,v1=c2ln,d=dev_1") -> ConnectionsSource {
    ConnectionsSource(transport: transport, tenant: "acme/1", language: "fr", proof: { proof })
}

let appConnectionsTests: [Test] = [
    Test("the connections are read from planque with this Mac's signed read, the tenant escaped, and nothing else sent", awaiting: {
        let transport = CannedTransport([(200, grantsAnswer)])
        let grants = try await source(transport).grants()
        try expectEqual(transport.sent.count, 1)
        try expectEqual(transport.sent[0].method, "GET")
        try expectEqual(transport.sent[0].path, "/v1/accounts/acme%2F1/grants")
        try expectEqual(transport.sent[0].headers["Planque-Device-Signature"], "t=1700000000000,v1=c2ln,d=dev_1")
        try expectEqual(transport.sent[0].headers["Accept-Language"], "fr")
        try expectEqual(transport.sent[0].headers["Accept"], "application/json")
        try expect(transport.sent[0].headers["Authorization"] == nil, "no session goes to planque")
        try expect(transport.sent[0].body.isEmpty, "a read has no body")
        // A grant that doesn't read is left out, never the list.
        try expectEqual(grants.map(\.id), ["g1", "g2", "g3", "g4", "g5", "g6", "g7", "g8"])
        try expectEqual(grants[0].name, "Qonto · Demo Shop")
        try expectEqual(grants[0].vendor, "Qonto")
        try expectEqual(grants[1].vendor, "mcp.qonto.com")
        try expectEqual(grants[1].waitingSignIn, true)
        try expectEqual(grants[3].name, "ops@shop.example")
        try expectEqual(grants[3].takesKey, true)
        try expectEqual(grants[4].signsInThroughProvider, true)
        try expectEqual(grants[4].name, "Qonto")
        try expectEqual(grants[7].rowFromPlanque, true)
        try expectEqual(grants[7].health, AppConnections.Grant.Health(ok: true, words: "Working · last used 09:12"))
        try expectEqual(grants[0].rowFromPlanque, false)
    }),
    Test("without a signed read nothing is sent; a refusal and an answer with no list are never \"no connections\"", awaiting: {
        let none = CannedTransport([])
        do { _ = try await source(none, proof: nil).grants(); throw Failure(description: "read without a proof") } catch let error as ConnectionsSource.Unread {
            try expectEqual(error, .notSigning)
        }
        try expectEqual(none.sent.count, 0)
        do { _ = try await source(CannedTransport([(403, #"{"error":"not enrolled","words":"Set up first."}"#)])).grants(); throw Failure(description: "a 403 was read") } catch let error as PlanqueClient.PlanqueError {
            try expectEqual(error, .server(status: 403, message: "not enrolled", words: "Set up first."))
        }
        for body in ["{}", "<html>"] {
            do { _ = try await source(CannedTransport([(200, body)])).grants(); throw Failure(description: "\(body) was read") } catch let error as KIFFError { try expectEqual(error, .unreadable) }
        }
    }),
    Test("this Mac's own read is signed by its device key over planque's message for the grants, with its device id", awaiting: {
        let planque = PlanqueClient()
        planque.deviceID = "dev_9"
        var signed: [String] = []
        var account = AccountClient(transport: CannedTransport([]), session: session)
        account.signMessage = { message in signed.append(message); return "c2ln" }
        let transport = CannedTransport([(200, #"{"grants":[]}"#)])
        let read = try await ConnectionsSource(account: account, planque: planque, transport: transport).grants()
        try expectEqual(read, [])
        try expectEqual(signed.count, 1)
        let lines = signed[0].split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        try expectEqual(Array(lines.prefix(5)), ["planque.request.v1", PlanqueClient.baseURL, "acme/1", "GET", "/v1/accounts/acme%2F1/grants"])
        try expectEqual(lines[5], PlanqueClient.emptyBodyHash)
        let header = transport.sent[0].headers["Planque-Device-Signature"] ?? ""
        try expect(header.hasPrefix("t=\(lines[6]),v1=c2ln,d=dev_9"), header)
        // No device key in the session: no read, and nothing sent.
        let unsigned = CannedTransport([])
        let bare = ConnectionsSource(account: AccountClient(transport: CannedTransport([]), session: session), planque: planque, transport: unsigned)
        do { _ = try await bare.grants(); throw Failure(description: "read without a key") } catch let error as ConnectionsSource.Unread { try expectEqual(error, .notSigning) }
        try expectEqual(unsigned.sent.count, 0)
    }),
    Test("an app's connections are its entry's or the grant tafs cloud named, never a disconnected or failed one", awaiting: {
        let grants = try await source(CannedTransport([(200, grantsAnswer)])).grants()
        let qonto = try app(#""state":"connected""#)
        try expectEqual(AppConnections.connections(of: qonto, in: grants).map(\.id), ["g1", "g2", "g3", "g4", "g8"])
        let named = try app(#""state":"available","grant":"g5""#)
        try expectEqual(AppConnections.connections(of: named, in: grants).map(\.id), ["g1", "g2", "g3", "g4", "g5", "g8"])
        // A connected app opens its page; one holding a connection does too; any other doesn't.
        try expectEqual(AppConnections.opens(qonto, in: []), true)
        try expectEqual(AppConnections.opens(named, in: grants), true)
        let slack = try AccountClient.decoder.decode(Apps.App.self, from: Data(#"{"entry":"connector:p:slack","name":"Slack","state":"available"}"#.utf8))
        try expectEqual(AppConnections.opens(slack, in: grants), false)
    }),
    Test("grouped as the iPad's: a section per taf, one needing attention first, then the removed tafs', then the others", awaiting: {
        let grants = try await source(CannedTransport([(200, grantsAnswer)])).grants()
        let tafs = [try taf("a_refunds", "t1", "Refunds"), try taf("a_billing", "t2", "Billing")]
        let mine = AppConnections.connections(of: try app(#""state":"connected""#), in: grants)
        let parts = AppConnections.groups(mine, taf: { AppConnections.taf(of: $0, in: tafs) }, removed: ["a_gone"])
        // Billing's sign-in waits, so it comes before Refunds.
        try expectEqual(parts.tafs.map(\.taf), ["Billing", "Refunds"])
        try expectEqual(parts.tafs.map { $0.grants.map(\.id) }, [["g2"], ["g1", "g8"]])
        try expectEqual(parts.removed.map(\.id), ["g3"])
        // A taf this app can't name isn't taken as removed without tafs cloud's word.
        try expectEqual(parts.others.map(\.id), ["g4"])
        let unnamed = AppConnections.groups(mine, taf: { AppConnections.taf(of: $0, in: tafs) })
        try expectEqual(unnamed.removed.map(\.id), [])
        try expectEqual(unnamed.others.map(\.id), ["g3", "g4"])
        // With none waiting, by name.
        let calm = AppConnections.groups(mine.filter { $0.id != "g2" },
                                         taf: { $0.agent == "a_refunds" ? "Refunds" : $0.agent == "a_gone" ? "Accounts" : nil })
        try expectEqual(calm.tafs.map(\.taf), ["Accounts", "Refunds"])
    }),
    Test("the removed tafs' connections: what tafs cloud lists, Clear only for those no live taf's Card uses, and who keeps one") {
        let page = try AccountClient.decoder.decode(Apps.Page.self, from: Data(#"""
        {"apps":[],"removed_tafs":[{"agent":"a_gone","removed_at":"2026-11-01T10:00:00Z","grants":[{"grant":"g3"},{"grant":"g9","used_by":[{"taf":"t1","name":"Refunds"}]}]},{"agent":"a_old"}]}
        """#.utf8))
        try expectEqual(page.removedTafs.map(\.agent), ["a_gone", "a_old"])
        let listed = AppConnections.removedListed(page.removedTafs)
        try expectEqual(Set(listed.keys), ["g3", "g9"])
        let grants = try AccountClient.decoder.decode([AppConnections.Grant].self, from: Data(#"""
        [{"id":"g3","status":"connected","request":{"server":"q","agent":"a_gone"}},{"id":"g9","status":"connected","request":{"server":"q","agent":"a_gone"}},{"id":"g10","status":"connected","request":{"server":"q","agent":"a_old"}}]
        """#.utf8))
        try expectEqual(AppConnections.clearable(grants, listed: listed), ["g3"])
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        try expectEqual(AppConnections.keptLine(["Refunds"], words), "Kept: Refunds' Card uses it")
        // Each name once, as the language lists them ("Refunds and Billing"; joined with commas on Linux).
        try expectEqual(AppConnections.keptLine(["Refunds", "Billing", "Refunds", " "], words), "Kept: the Cards of \(words.list(["Refunds", "Billing"])) use it")
        try expectEqual(AppConnections.keptLine([], words), nil)
        // An unreadable list is none, never the page.
        let odd = try AccountClient.decoder.decode(Apps.Page.self, from: Data(#"{"apps":[],"removed_tafs":"x"}"#.utf8))
        try expectEqual(odd.removedTafs, [])
    },
    Test("a connection's end is Cancel the request, Cancel or Remove access, as the iPad's endWord") {
        let grants = try AccountClient.decoder.decode([AppConnections.Grant].self, from: Data(#"""
        [{"id":"a","status":"pending","request":{"server":"q","agent":"x"}},
         {"id":"b","status":"pending","signed_in":true,"request":{"server":"q","agent":"x"}},
         {"id":"c","status":"approved","request":{"server":"q","agent":"x"}},
         {"id":"d","status":"approved","signed_in":true,"request":{"server":"q","agent":"x"}},
         {"id":"e","status":"connected","request":{"server":"q","agent":"x"}}]
        """#.utf8))
        try expectEqual(grants.map(AppConnections.endKey), ["connect.cancel_request.button", "connect.disconnect_button", "common.cancel", "connect.disconnect_button", "connect.disconnect_button"])
        try expectEqual(grants.map(\.cancellable), [true, false, true, false, false])
    },
    Test("the catalog is read with this Mac's signed read, as the iPad's, and reads needed_by and misplaced", awaiting: {
        let page1 = #"{"apps":[{"entry":"e","name":"Qonto","state":"connected","grant":"g1","needed_by":[{"taf":"t1","name":"Refunds"},{"name":"no id"}],"misplaced":[{"grant":"g4","taf":"t2","name":"Billing"},{"taf":"no grant"}]}]}"#
        let transport = CannedTransport([(200, page1), (200, page1)])
        let client = CloudClient(transport: transport, session: session)
        let page = try await client.apps("", proof: "t=1,v1=s,d=dev_1")
        try expectEqual(transport.sent[0].headers["Planque-Device-Signature"], "t=1,v1=s,d=dev_1")
        try expectEqual(transport.sent[0].headers["Authorization"], "Bearer tok")
        try expectEqual(page.apps[0].grant, "g1")
        try expectEqual(page.apps[0].neededBy, [Apps.Named(taf: "t1", name: "Refunds")])
        try expectEqual(page.apps[0].misplaced.map(\.grant), [])
        let lenient = try app(#""state":"available","needed_by":"x","misplaced":[{"grant":"g4","taf":"t2","name":"Billing"}]"#)
        try expectEqual(lenient.neededBy, nil)
        try expectEqual(lenient.misplaced.map(\.name), ["Billing"])
        _ = try await client.apps()
        try expect(transport.sent[1].headers["Planque-Device-Signature"] == nil, "a read without a proof sends none")
    }),
    Test("a row's button says the iPad's words: Ask Coach where no taf needs the app, else Connect or Sign in again") {
        let refunds = try taf("a_refunds", "t1", "Refunds")
        let notOnCloud = try taf("a_x", nil, "Old agent")
        // tafs cloud doesn't say which tafs need it: Connect, for any taf, or none.
        try expectEqual(Apps.buttonKey(try app(#""state":"available""#), connectable: [refunds]), "connect.apps.connect")
        try expectEqual(Apps.buttonKey(try app(#""state":"available""#), connectable: []), "connect.apps.connect")
        // It says, and none needs it, or none it needs can have it: Ask Coach.
        try expectEqual(Apps.buttonKey(try app(#""state":"available","needed_by":[]"#), connectable: [refunds]), "coach.ask")
        try expectEqual(Apps.buttonKey(try app(#""state":"available","needed_by":[{"taf":"t9","name":"Other"}]"#), connectable: [refunds]), "coach.ask")
        try expectEqual(Apps.buttonKey(try app(#""state":"needs_reconnect","needed_by":[]"#), connectable: [refunds]), "coach.ask")
        // A taf that needs it can have it: Connect, or Sign in again.
        try expectEqual(Apps.buttonKey(try app(#""state":"available","needed_by":[{"taf":"t1","name":"Refunds"}]"#), connectable: [refunds, notOnCloud]), "connect.apps.connect")
        try expectEqual(Apps.buttonKey(try app(#""state":"needs_reconnect","needed_by":[{"taf":"t1","name":"Refunds"}]"#), connectable: [refunds]), "connect.sign_in_again")
        try expectEqual(Apps.buttonKey(try app(#""state":"needs_reconnect""#), connectable: [refunds]), "connect.sign_in_again")
        // The iPad's routes, opened from a taf or not.
        try expectEqual(Apps.connectFor(openedFrom: nil, connectable: [], needed: false), .noTaf)
        try expectEqual(Apps.connectFor(openedFrom: nil, connectable: ["t1"], needed: false), .ask)
        try expectEqual(Apps.connectFor(openedFrom: "t1", connectable: [], needed: false), .taf("t1"))
        try expectEqual(Apps.connectFor(openedFrom: "t1", connectable: ["t1"], needed: true), .taf("t1"))
        try expectEqual(Apps.connectFor(openedFrom: "t2", connectable: ["t1"], needed: true), .askCoach)
        try expectEqual(Apps.connectFor(openedFrom: nil, connectable: [], needed: true), .askCoach)
        try expectEqual(Apps.connectable([refunds, notOnCloud], needed: nil).map(\.name), ["Refunds", "Old agent"])
        try expectEqual(Apps.connectable([refunds], needed: [Apps.Named(taf: "t1", name: "R"), Apps.Named(taf: "t9", name: "X")]).map(\.name), ["Refunds"])
    },
    Test("the page's and the button's words are shared lines in every shipped language") {
        let folder = URL(fileURLWithPath: ".shared/app/strings")
        let keys = ["coach.ask", "connect.apps.connect", "connect.sign_in_again", "connect.apps.your_connections", "connect.start_connected_tools_first",
                    "connect.other_connections", "connect.from_removed", "connect.clear_removed.button", "connect.apps.disconnect_why",
                    "connect.apps.used_by", "connect.misplaced", "connect.through_provider", "connect.replace_key", "connect.status.waiting_sign_in",
                    "connect.cancel_request.button", "common.cancel", "connect.disconnect_button", "connect.used_by.one", "connect.used_by.many",
                    "approval.device_can_not_approve_approve", "connect.apps.title"]
        let shipped = try Words.shipped(folder: folder)
        try expectEqual(shipped.count, 10)
        for language in shipped {
            let words = try Words(language: language, folder: folder)
            for key in keys { try expect(words(key) != key, "\(key) in \(language)") }
        }
    },
]

import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

let appsPage = #"""
{"apps":[
  {"entry":"reviewed:qonto-invoicing","vendor":"Qonto","title":"Qonto invoicing: reads, and invoice drafts from quotes","name":"Qonto","subtitle":"Invoicing: reads, and invoice drafts from quotes","how":"oauth","state":"connected","connected":true,"method":"sign_in","whose":"Company","used_by":[{"taf":"taf-1","name":"Refunds"}],"line":"Sign in · Connected · Used by Refunds"},
  {"entry":"connector:p:gmail","vendor":"gmail","title":"Gmail","name":"Gmail","how":"oauth","state":"needs_reconnect","connected":false,"method":"sign_in","whose":"Company","line":"Sign in · Sign in again"},
  {"entry":"connector:p:slack","vendor":"slack","title":"Slack","name":"Slack","how":"oauth","state":"available","connected":false,"method":"sign_in","line":"Sign in"},
  {"entry":"reviewed:bank","vendor":"Bank","title":"Bank","state":"needs_setup","words":"An operator sets this app up first.","line":"Key"},
  {"entry":"broken"},
  {"entry":"nameless","state":"available","name":"  "}
],"by_key":{},"next_cursor":"c2","partial":false,"removed_tafs":0}
"""#

private func cloud(_ answers: [(Int, String)]) -> (CloudClient, CannedTransport) {
    let transport = CannedTransport(answers)
    return (CloudClient(transport: transport, session: session), transport)
}

let connectionsAppsTests: [Test] = [
    Test("the catalog is read as tafs cloud sends it, and a row that doesn't read is left out", awaiting: {
        let (client, transport) = cloud([(200, appsPage)])
        let page = try await client.apps()
        try expectEqual(transport.sent[0].path, "/v1/connect/apps?q=")
        try expectEqual(page.apps.map(\.name), ["Qonto", "Gmail", "Slack", "Bank"])
        try expectEqual(page.apps[0].subtitle, "Invoicing: reads, and invoice drafts from quotes")
        try expectEqual(page.apps[0].line, "Sign in · Connected · Used by Refunds")
        try expectEqual(page.apps[0].whose, "Company")
        try expectEqual(page.apps.map(\.howKey), ["connect.how.sign_in", "connect.how.sign_in", "connect.how.sign_in", "connect.how.sign_in"])
        try expectEqual(page.apps.map(\.usedBy), [["Refunds"], [], [], []])
        try expectEqual(page.apps[3].words, "An operator sets this app up first.")
        try expectEqual(page.nextCursor, "c2")
        try expectEqual(page.partial, false)
    }),
    Test("yours are the connected and the ones to sign in again; the key called vendor is never a name") {
        let page = try AccountClient.decoder.decode(Apps.Page.self, from: Data(appsPage.utf8))
        try expectEqual(page.apps.filter(\.isYours).map(\.name), ["Qonto", "Gmail"])
        try expectEqual(page.apps.filter(\.needsReconnect).map(\.name), ["Gmail"])
        // A row with only a vendor has nothing to read as: it is left out, not named by its key.
        let vendorOnly = #"{"apps":[{"entry":"e","vendor":"gmail","state":"available"}]}"#
        try expectEqual(try AccountClient.decoder.decode(Apps.Page.self, from: Data(vendorOnly.utf8)).apps.count, 0)
    },
    Test("a sign-in no taf uses yet is under Yours and opens its connections, where it can be ended; it has no Connect") {
        let json = #"""
        {"apps":[{"entry":"connector:p:pipedrive","vendor":"pipedrive","title":"Pipedrive","name":"Pipedrive","how":"oauth",
          "state":"signed_in","grant":"g-pipedrive","connected":false,"method":"sign_in","whose":"Company","used_by":[],
          "line":"Sign in · Signed in · Not used by any taf","needed_by":[]}]}
        """#
        let app = try AccountClient.decoder.decode(Apps.Page.self, from: Data(json.utf8)).apps[0]
        try expect(app.isYours && app.isSignedIn && app.opensConnections, "yours, signed in, opens")
        try expect(!app.isConnected && !app.needsReconnect, "neither connected nor to sign in again")
        try expectEqual(app.line, "Sign in · Signed in · Not used by any taf")
        try expect(AppConnections.opens(app, in: []), "opens even before its connection is read")
    },
    Test("tafs cloud's Connect apps contract: every sign-in the account holds is under Yours, the unused one opening its connections") {
        let data = try Data(contentsOf: URL(fileURLWithPath: ".shared/contracts/connect-apps.json"))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let answer = object["answer"] else {
            throw Failure(description: "connect-apps.json has no answer")
        }
        let page = try AccountClient.decoder.decode(Apps.Page.self, from: JSONSerialization.data(withJSONObject: answer))
        try expectEqual(page.apps.filter(\.isYours).map(\.name), ["Gmail", "Stripe", "Pipedrive"])
        let pipedrive = try page.apps.first { $0.name == "Pipedrive" } ?? { throw Failure(description: "no Pipedrive row") }()
        try expect(pipedrive.isSignedIn && pipedrive.opensConnections && !pipedrive.isConnected, "signed in, opens, not connected")
        try expectEqual(pipedrive.line, "Sign in · Signed in · Not used by any taf")
    },
    Test("a search is escaped and cut, a cursor continues it, and an answer with no list is unreadable", awaiting: {
        let (client, transport) = cloud([(200, appsPage), (200, appsPage)])
        _ = try await client.apps("Qonto & co/..", cursor: "a+b")
        try expectEqual(transport.sent[0].path, "/v1/connect/apps?q=Qonto%20%26%20co%2F%2E%2E&cursor=a%2Bb")
        _ = try await client.apps(String(repeating: "x", count: 130))
        try expectEqual(transport.sent[1].path, "/v1/connect/apps?q=" + String(repeating: "x", count: 100))
        for body in ["{}", "<html>"] {
            do { _ = try await cloud([(200, body)]).0.apps(); throw Failure(description: "\(body) was read") } catch let error as KIFFError { try expectEqual(error, .unreadable) }
        }
    }),
    Test("how an app connects is a shared line in every shipped language, by the iPad's rule") {
        let folder = URL(fileURLWithPath: ".shared/app/strings")
        for language in try Words.shipped(folder: folder) {
            let words = try Words(language: language, folder: folder)
            for key in ["connect.how.sign_in", "connect.how.key", "connect.apps.used_by"] { try expect(words(key) != key, "\(key) in \(language)") }
        }
        func how(_ fields: String) throws -> String {
            try JSONDecoder().decode(Apps.App.self, from: Data(#"{"entry":"e","name":"N","state":"available"\#(fields)}"#.utf8)).howKey
        }
        // method first; an older tafs cloud's how; anything else is Sign in, as on the iPad.
        try expectEqual(try how(#","method":"key","how":"oauth""#), "connect.how.key")
        try expectEqual(try how(#","how":"key""#), "connect.how.key")
        try expectEqual(try how(#","method":"carrier_pigeon""#), "connect.how.sign_in")
        try expectEqual(try how(""), "connect.how.sign_in")
    },
    Test("which tafs use a connection are its used_by names, and a user that doesn't read is left out") {
        let json = #"{"entry":"e","name":"N","state":"connected","used_by":[{"taf":"t1","name":"Refunds"},{"taf":"t2"},7,{"taf":"t3","name":" "},{"taf":"t4","name":"Invoices"}]}"#
        let app = try JSONDecoder().decode(Apps.App.self, from: Data(json.utf8))
        try expectEqual(app.usedBy, ["Refunds", "Invoices"])
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        try expectEqual(words("connect.apps.used_by", ["tafs": words.list(["Refunds"])]), "Used by Refunds")
        try expect(words.list(["Refunds", "Invoices"]).contains("Invoices"), "both names")
    },
    Test("a logo is kept only as tafs cloud's own /v1/logos/ path, and nothing stands in for one it didn't send") {
        let key = String(repeating: "0a", count: 16)
        try expectEqual(Apps.logoPath("/v1/logos/\(key)"), "/v1/logos/\(key)")
        for path in ["https://elsewhere.example/x.png", "/v1/logos/\(key)0", "/v1/logos/\(key.uppercased())", "/v1/logos/../me", "/v1/logos/"] {
            try expect(Apps.logoPath(path) == nil, path)
        }
        let json = #"{"apps":[{"entry":"a","name":"A","state":"connected","logo":"/v1/logos/"# + key + #""},{"entry":"b","name":"B","state":"available","logo":"https://elsewhere.example/b.png"},{"entry":"c","name":"C","state":"available"}]}"#
        let page = try AccountClient.decoder.decode(Apps.Page.self, from: Data(json.utf8))
        try expectEqual(page.apps.map(\.logoURL?.absoluteString), [CloudClient.base + "/v1/logos/" + key, nil, nil])
    },
    Test("a row ends as the iPad's: a check when connected, nothing to set up first, else Connect or Sign in again") {
        let page = try AccountClient.decoder.decode(Apps.Page.self, from: Data(appsPage.utf8))
        try expectEqual(page.apps.map(\.isConnected), [true, false, false, false])
        try expectEqual(page.apps.map(\.needsSetup), [false, false, false, true])
        try expectEqual(page.apps.map(\.needsReconnect), [false, true, false, false])
    },
    Test("by_key says Coach can connect an app that isn't listed; anything but true reads as false") {
        func byKey(_ value: String) throws -> Bool {
            try AccountClient.decoder.decode(Apps.Page.self, from: Data((#"{"apps":[],"by_key":"# + value + "}").utf8)).byKey
        }
        try expectEqual(try byKey("true"), true)
        try expectEqual(try byKey("false"), false)
        try expectEqual(try byKey("{}"), false)
        try expectEqual(try AccountClient.decoder.decode(Apps.Page.self, from: Data(#"{"apps":[]}"#.utf8)).byKey, false)
    },
]

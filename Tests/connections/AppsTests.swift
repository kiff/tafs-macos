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

let connectionsTests: [Test] = [
    Test("the catalog is read as tafs cloud sends it, and a row that doesn't read is left out", awaiting: {
        let (client, transport) = cloud([(200, appsPage)])
        let page = try await client.apps()
        try expectEqual(transport.sent[0].path, "/v1/connect/apps?q=")
        try expectEqual(page.apps.map(\.name), ["Qonto", "Gmail", "Slack", "Bank"])
        try expectEqual(page.apps[0].subtitle, "Invoicing: reads, and invoice drafts from quotes")
        try expectEqual(page.apps[0].line, "Sign in · Connected · Used by Refunds")
        try expectEqual(page.apps[0].whose, "Company")
        try expectEqual(page.apps.map(\.howKey), ["connect.how.sign_in", "connect.how.sign_in", "connect.how.sign_in", nil])
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
    Test("how an app connects is a shared line in every shipped language, and nothing for a way not known") {
        let folder = URL(fileURLWithPath: ".shared/app/strings")
        for language in try Words.shipped(folder: folder) {
            let words = try Words(language: language, folder: folder)
            for key in ["connect.how.sign_in", "connect.how.key"] { try expect(words(key) != key, "\(key) in \(language)") }
        }
        let json = #"{"entry":"e","name":"N","state":"available","method":"carrier_pigeon"}"#
        try expectEqual(try JSONDecoder().decode(Apps.App.self, from: Data(json.utf8)).howKey, nil)
    },
]

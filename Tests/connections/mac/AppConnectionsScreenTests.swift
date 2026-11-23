import AppKit
import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

/// tafs cloud's logo keys for the catalog below.
private let qontoLogo = "/v1/logos/0123456789abcdef0123456789abcdef"
private let gmailLogo = "/v1/logos/11111111111111111111111111111111"
private let slackLogo = "/v1/logos/22222222222222222222222222222222"
private let refusedLogo = "/v1/logos/33333333333333333333333333333333"

/// The catalog with logos, as tafs cloud sends it: one refused by tafs cloud (Notion), one sent
/// from elsewhere and dropped (Bank).
private let logosPage = """
{"apps":[
  {"entry":"reviewed:qonto-invoicing","name":"Qonto","subtitle":"Invoicing: reads, and invoice drafts from quotes","state":"connected","method":"sign_in","whose":"Company","used_by":[{"taf":"t1","name":"Refunds"}],"logo":"\(qontoLogo)","grant":"g1"},
  {"entry":"connector:p:gmail","name":"Gmail","state":"needs_reconnect","method":"sign_in","whose":"Company","logo":"\(gmailLogo)"},
  {"entry":"connector:p:slack","name":"Slack","state":"available","method":"sign_in","logo":"\(slackLogo)","needed_by":[]},
  {"entry":"connector:p:notion","name":"Notion","state":"available","method":"key","logo":"\(refusedLogo)","needed_by":[{"taf":"t1","name":"Refunds"}]},
  {"entry":"reviewed:bank","name":"Bank","state":"available","method":"key","logo":"https://cdn.example.com/bank.png"}
],"removed_tafs":[{"agent":"a_gone","grants":[{"grant":"g3"}]}]}
"""

/// A logo as tafs cloud serves one: a small PNG, here a rounded square of one colour.
@MainActor
private func logoPNG(_ color: Color) -> Data {
    let view = RoundedRectangle(cornerRadius: 10).fill(color).padding(4)
    return Snapshot.bitmap(of: view, size: CGSize(width: 48, height: 48)).flatMap { Snapshot.png($0) } ?? Data()
}

/// tafs cloud's logo route: a PNG for each key it keeps, a 404 for any other.
private final class LogoRoute: Transport, @unchecked Sendable {
    let logos: [String: Data]
    private let lock = NSLock()
    private var made: [HTTPRequest] = []
    init(_ logos: [String: Data]) { self.logos = logos }
    var sent: [HTTPRequest] {
        lock.lock(); defer { lock.unlock() }
        return made
    }
    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        lock.lock()
        made.append(request)
        lock.unlock()
        guard let png = logos[request.path] else { return (404, Data(#"{"error":"no logo"}"#.utf8)) }
        return (200, png)
    }
}

/// The logos read before the screen is drawn, as they are once read: each in its first frame.
@MainActor
private func readLogos() async -> (AppLogoImages, LogoRoute) {
    let route = LogoRoute([qontoLogo: logoPNG(Color(red: 0.42, green: 0.25, blue: 0.85)), gmailLogo: logoPNG(Color(red: 0.86, green: 0.2, blue: 0.16)),
                           slackLogo: logoPNG(Color(red: 0.2, green: 0.6, blue: 0.35))])
    let images = AppLogoImages(AppLogos(transport: route))
    for path in [qontoLogo, gmailLogo, slackLogo, refusedLogo] { _ = await images.load(path) }
    return (images, route)
}

private func taf(_ agent: String, _ id: String, _ name: String) throws -> Home.Taf {
    try AccountClient.decoder.decode(Home.Taf.self, from: Data("{\"kiff_agent\":\"\(agent)\",\"id\":\"\(id)\",\"name\":\"\(name)\",\"state\":\"idle\"}".utf8))
}

@MainActor
private func makeModel(grants: (Int, String)) -> (ConnectAppsModel, CannedTransport, CannedTransport) {
    let cloud = CannedTransport([(200, logosPage), (200, logosPage)])
    let planque = CannedTransport([grants, grants])
    var proofs = 0
    let source = ConnectionsSource(transport: planque, tenant: "t1", proof: { proofs += 1; return "t=\(proofs),v1=c2ln,d=dev_1" })
    return (ConnectAppsModel(cloud: CloudClient(transport: cloud, session: session), connections: source), cloud, planque)
}

private func write<V: View>(_ view: V, _ name: String, size: CGSize, dark: Bool) throws {
    guard let bitmap = Snapshot.bitmap(of: view, size: size, dark: dark), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
    let folder = URL(fileURLWithPath: "build/screenshots")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try png.write(to: folder.appendingPathComponent(name + (dark ? "-dark" : "") + ".png"))
}

private let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])

let appConnectionsMacTests: [Test] = [
    Test("Connect apps reads the account's connections first, then the catalog with a fresh signed read, as the iPad's", awaiting: { @MainActor in
        let (model, cloud, planque) = makeModel(grants: (200, grantsAnswer))
        await model.load()
        try expectEqual(planque.sent.map(\.path), ["/v1/accounts/t1/grants"])
        try expectEqual(planque.sent[0].headers["Planque-Device-Signature"], "t=1,v1=c2ln,d=dev_1")
        try expectEqual(cloud.sent.map(\.path), ["/v1/connect/apps?q="])
        try expectEqual(cloud.sent[0].headers["Planque-Device-Signature"], "t=2,v1=c2ln,d=dev_1")
        try expectEqual(model.readsConnections, true)
        try expectEqual(model.grants.count, 8)
        try expectEqual(model.removedTafs.map(\.agent), ["a_gone"])
        // A search reads only the catalog; the next page has its own signed read.
        model.search = "q"
        await model.load()
        try expectEqual(planque.sent.count, 1)
        try expectEqual(Set(cloud.sent.map(\.method) + planque.sent.map(\.method)), ["GET"])
    }),
    Test("connections that can't be read leave none, and the page says this Mac doesn't read them", awaiting: { @MainActor in
        let (model, _, _) = makeModel(grants: (403, #"{"error":"not enrolled"}"#))
        await model.load()
        try expectEqual(model.readsConnections, false)
        try expectEqual(model.grants, [])
        try expectEqual(model.state, .loaded)
        let bare = ConnectAppsModel(cloud: CloudClient(transport: CannedTransport([(200, logosPage)]), session: session))
        await bare.load()
        try expectEqual(bare.readsConnections, false)
    }),
    Test("a logo read is drawn in its square; a refused or unreadable one leaves it empty", awaiting: { @MainActor in
        let (images, route) = await readLogos()
        try expectEqual(route.sent.map(\.path), [qontoLogo, gmailLogo, slackLogo, refusedLogo])
        try expect(route.sent.allSatisfy { $0.headers["Authorization"] == nil }, "a logo is read with no session")
        func centre(_ logo: String?) throws -> [UInt32] {
            let view = AppLogo(logo: logo, side: 24, holdsPlace: true).environment(\.appLogos, images).frame(width: 24, height: 24).background(Color.white)
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 24, height: 24)) else { throw Failure(description: "no bitmap") }
            return Snapshot.hexes(bitmap, x: 12, y: 12)
        }
        let gmail = try centre(gmailLogo)
        try expect(gmail.contains { ($0 >> 16) & 0xFF > 0xA0 && ($0 >> 8) & 0xFF < 0x70 }, "Gmail's red logo: \(gmail.map { String($0, radix: 16) })")
        for empty in [refusedLogo, "https://cdn.example.com/bank.png", "/v1/logos/44444444444444444444444444444444"] {
            let drawn = try centre(empty)
            try expect(drawn.contains(0xFFFFFF), "\(empty) drew something: \(drawn.map { String($0, radix: 16) })")
        }
        // Bytes that say PNG but don't decode keep nothing.
        let broken = AppLogoImages(AppLogos(transport: LogoRoute([refusedLogo: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])])))
        let none = await broken.load(refusedLogo)
        try expect(none == nil, "a PNG that doesn't decode was drawn")
        try expect(broken.cached(refusedLogo) == nil, "a PNG that doesn't decode was kept")
    }),
    Test("a connected row's chevron opens \"Your {app} connections\"; the button says Ask Coach where no taf needs the app", awaiting: { @MainActor in
        let (model, _, _) = makeModel(grants: (200, grantsAnswer))
        await model.load()
        let qonto = model.apps[0]
        try expectEqual(AppConnections.opens(qonto, in: model.grants), true)
        let refunds = try taf("a_refunds", "t1", "Refunds")
        // Gmail to sign in again; Slack, which no taf needs; Notion, which Refunds needs.
        try expectEqual(Array(model.apps.map { Apps.buttonKey($0, connectable: [refunds]) }[1...3]),
                        ["connect.sign_in_again", "coach.ask", "connect.apps.connect"])
        try expectEqual(words("coach.ask"), "Ask Coach")
        model.opened = qonto
        try expectEqual(words("connect.apps.your_connections", ["app": qonto.name]), "Your Qonto connections")
    }),
    Test("the screenshots: Connect apps with its logos, light and dark", awaiting: { @MainActor in
        let (images, _) = await readLogos()
        let (model, _, _) = makeModel(grants: (200, grantsAnswer))
        await model.load()
        let refunds = try taf("a_refunds", "t1", "Refunds")
        for dark in [false, true] {
            let view = ConnectAppsView(model: model, tafs: [refunds], connectable: [refunds]).environment(\.words, words).environment(\.appLogos, images)
            try write(view, "connect-apps-logos-en", size: CGSize(width: 980, height: 760), dark: dark)
        }
    }),
    Test("the screenshots: \"Your Qonto connections\", light and dark, and a click on Remove access saying to approve elsewhere", awaiting: { @MainActor in
        let (model, _, _) = makeModel(grants: (200, grantsAnswer))
        await model.load()
        let tafs = [try taf("a_refunds", "t1", "Refunds"), try taf("a_billing", "t2", "Billing")]
        let qonto = model.apps[0]
        for dark in [false, true] {
            let view = AppConnectionsView(app: qonto, model: model, tafs: tafs, managesCards: true, back: {}).environment(\.words, words)
            try write(view, "connect-app-connections-en", size: CGSize(width: 980, height: 1100), dark: dark)
        }
        let gated = AppConnectionsView(app: qonto, model: model, tafs: tafs, managesCards: true, gated: "g1|end", back: {}).environment(\.words, words)
        try write(gated, "connect-app-connections-gated-en", size: CGSize(width: 980, height: 1100), dark: false)
        // Opened from Connect apps, the page is drawn in its place.
        model.opened = qonto
        try write(ConnectAppsView(model: model, tafs: tafs).environment(\.words, words), "connect-app-connections-opened-en", size: CGSize(width: 980, height: 760), dark: false)
    }),
    Test("the screenshots: a connection's page from planque's row, light and dark, its Remove clicked, and Make one first with no taf", awaiting: { @MainActor in
        let json = #"""
        {"id":"g8","status":"connected","title":"Qonto rows","used_by":["Refunds"],"request":{"server":"q","agent":"a_refunds"},
         "health":{"ok":false,"words":"Signed out by Qonto · sign in again"},
         "actions":[{"id":"sign_in_again","words":"Sign in again","how":"approve"},{"id":"remove","words":"Remove access","how":"delete","stops":"Refunds stops reading Qonto."}]}
        """#
        let grant = try JSONDecoder().decode(AppConnections.Grant.self, from: Data(json.utf8))
        try expectEqual(grant.knownActions.count, 2)
        for dark in [false, true] {
            let view = ConnectionDetailView(grant: grant, appTitle: "Qonto", managesCards: true, back: {}).environment(\.words, words)
            try write(view, "connect-connection-page-en", size: CGSize(width: 980, height: 600), dark: dark)
        }
        let gated = ConnectionDetailView(grant: grant, appTitle: "Qonto", managesCards: true, gated: "1", back: {}).environment(\.words, words)
        try write(gated, "connect-connection-page-gated-en", size: CGSize(width: 980, height: 600), dark: false)
        let (model, _, _) = makeModel(grants: (200, grantsAnswer))
        await model.load()
        try write(ConnectAppsView(model: model, tafs: [], connectable: []).environment(\.words, words), "connect-apps-make-one-first-en",
                  size: CGSize(width: 980, height: 760), dark: false)
    }),
]

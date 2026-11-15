import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

private let tafThread = #"""
{"working":false,"items":[
  {"type":"message","message":{"id":"m1","at":"2026-11-15T00:30:00Z","from":"owner","text":"Which emails are still waiting on me?"}},
  {"type":"message","message":{"id":"m2","at":"2026-11-15T00:30:12Z","from":"taf","text":"**3 emails** are waiting for your answer:\n- Invoice 1042, from the accountant\n- The venue's quote\n- A question about Friday",
    "work":{"ms":12400,"steps":[{"tool":"mail.list","words":"Listing your inbox"}]}}}
]}
"""#

@MainActor
private func make(_ answers: [(Int, String)]) async throws -> (Home.Taf, CoachModel, CannedTransport) {
    let taf = try AccountClient.decoder.decode(Home.Page.self, from: Data(tafWithCards.utf8)).tafs[0]
    let transport = CannedTransport(answers)
    let chat = CoachModel(cloud: CloudClient(transport: transport, session: session),
                          taf: Coach(id: taf.tafID ?? "", name: taf.name), sleep: { _ in })
    await chat.load()
    return (taf, chat, transport)
}

/// A contract fixture's answer, as tafs cloud sends it.
private func contract(_ file: String) throws -> String {
    let root = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: ".shared/contracts/\(file)"))) as? [String: Any]
    guard let answer = root?["answer"] else { throw Failure(description: "\(file) has no answer") }
    return String(decoding: try JSONSerialization.data(withJSONObject: answer), as: UTF8.self)
}

/// A taf's Activity and Setup, read from the contracts.
@MainActor
private func pages(setup: String = "taf-setup.json") async throws -> (TafPagesModel, CannedTransport) {
    let transport = CannedTransport([(200, try contract("taf-activity.json")), (200, try contract(setup))])
    let model = TafPagesModel(cloud: CloudClient(transport: transport, session: session), taf: "taf-1")
    await model.loadActivity()
    await model.loadSetup()
    return (model, transport)
}

let tafScreenTests: [Test] = [
    Test("the credits fix opens Plan & usage in place of the taf's page; Coach's fix is no button", awaiting: { @MainActor in
        let health = try JSONDecoder().decode(Home.Taf.Health.self, from: Data(#"{"level":"at_risk","lines":["Credits are low."],"fixes":[{"line":0,"kind":"credits","words":"Add credits"},{"line":0,"kind":"coach","words":"Ask Coach","say":"Why?"}]}"#.utf8))
        let fixes = health.fixes(for: 0)
        var openTaf: String? = "taf-1"
        var selection = Screen.overview
        guard let act = TafActivityTab.action(fixes[0], openUsage: { SignedInView.showUsage(openTaf: &openTaf, selection: &selection) }) else {
            throw Failure(description: "no credits button")
        }
        act()
        try expectEqual(openTaf, nil)
        try expectEqual(selection, .usage)
        try expect(TafActivityTab.action(fixes[1], openUsage: {}) == nil, "Coach's fix comes with Coach mode")
    }),
    Test("versions that read stay when a later read fails, with tafs cloud's why under them; Cancel drops a switch and reads again", awaiting: { @MainActor in
        let state = #"{"versions":[{"n":1,"created":"2026-11-01T09:00:00Z","live":false},{"n":2,"created":"2026-11-10T09:00:00Z","live":true}],"switching":{"n":1,"draft":"d1","at":"2026-11-12T09:00:00Z"}}"#
        let transport = CannedTransport([(200, state), (503, #"{"error":"down"}"#), (200, #"{"cancelled":true}"#), (200, #"{"versions":[]}"#)])
        let model = TafPagesModel(cloud: CloudClient(transport: transport, session: session), taf: "taf-1")
        try expectEqual(model.versionList, nil)
        await model.loadVersions()
        try expectEqual(model.versionList?.map(\.n), [1, 2])
        try expectEqual(model.switching?.n, 1)
        await model.loadVersions()
        try expectEqual(model.versionList?.map(\.n), [1, 2])
        try expectEqual(model.versionError, "Its versions couldn't be loaded. down")
        await model.cancelSwitch()
        try expectEqual(transport.sent[2].method + " " + transport.sent[2].path, "DELETE /v1/tafs/taf-1/switching")
        try expectEqual(model.versionList, [])
        try expectEqual(model.switching, nil)
        try expectEqual(model.versionError, nil)
    }),
    Test("Activity and Setup only read, and a filter is tafs cloud's own, asked for again", awaiting: { @MainActor in
        let (model, transport) = try await pages()
        guard case .loaded(let activity) = model.activity, case .loaded(let setup) = model.setup else { throw Failure(description: "not read") }
        try expectEqual(activity.groups.first?.entries.first?.title, "Read a case")
        try expectEqual(setup.exceptions.count, 1)
        let held = #"{"entries":[],"filters":[{"id":"all","title":"All"},{"id":"held","title":"Held"}],"filter":"held"}"#
        transport.answers.append((200, held))
        await model.loadActivity(filter: "held")
        try expectEqual(model.filter, "held")
        try expectEqual(transport.sent.map(\.method), ["GET", "GET", "GET"])
        try expectEqual(transport.sent.map { $0.path.removingPercentEncoding ?? "" },
                        ["/v1/tafs/taf-1/activity?filter=all", "/v1/tafs/taf-1/setup", "/v1/tafs/taf-1/activity?filter=held"])
        // A Setup tafs cloud refuses (not someone who manages the taf) says so.
        transport.answers.append((403, #"{"error":"not_allowed"}"#))
        await model.loadSetup()
        guard case .unread = model.setup else { throw Failure(description: "a refusal read as a Setup") }
    }),
    Test("a Setup with an expired sign-in lists the app as to sign in again, with tafs cloud's words", awaiting: { @MainActor in
        let (model, _) = try await pages(setup: "taf-setup-reconnect.json")
        guard case .loaded(let setup) = model.setup else { throw Failure(description: "not read") }
        try expectEqual(setup.connections.map(\.reconnect), [true])
        try expect(setup.connectAgain != nil, "Connect again's words")
    }),
    Test("an app's week opens the Activity of its calls with tafs cloud's query; a filter chosen after leaves it", awaiting: { @MainActor in
        let (model, transport) = try await pages(setup: "taf-setup-connected.json")
        guard case .loaded(let setup) = model.setup, let query = TafSetup.nodes(setup.connections).first?.app.activityQuery else { throw Failure(description: "no app's query") }
        transport.answers.append((200, try contract("taf-activity.json")))
        model.show(activityQuery: query)
        await model.loadActivity()
        try expectEqual(model.query, query)
        try expectEqual(transport.sent.last?.path, "/v1/tafs/taf-1/activity?" + query)
        transport.answers.append((200, try contract("taf-activity.json")))
        await model.loadActivity(filter: "held")
        try expectEqual(model.query, nil)
        try expectEqual(transport.sent.last?.path, "/v1/tafs/taf-1/activity?filter=held")
    }),
    Test("the Cards stack as the iPad's wallet: the chosen one in front, the furthest back on top, each a shade darker") {
        let cards = try JSONDecoder().decode([TafCard].self, from: Data(#"[{"id":"c1","title":"Live","active":true,"rules":[]},{"id":"c2","title":"Test","active":true,"rules":[]},{"id":"c3","title":"Old","active":false,"rules":[]}]"#.utf8))
        try expectEqual(CardStack.front(of: cards, nil)?.id, "c1")
        try expectEqual(CardStack.front(of: cards, "c2")?.id, "c2")
        try expectEqual(CardStack.front(of: cards, "gone")?.id, "c1")
        try expectEqual(CardStack.ordered(cards, front: nil).map(\.id), ["c3", "c2", "c1"])
        try expectEqual(CardStack.ordered(cards, front: "c2").map(\.id), ["c3", "c1", "c2"])
        try expectEqual(CardStack.shade(depth: 0), 0)
        try expectEqual(CardStack.shade(depth: 1), 0.12)
        try expectEqual(CardStack.shade(depth: 9), 0.32)
    },
    Test("every tab's name is a shared line, in the iPad's order") {
        try expectEqual(TafView.Tab.allCases, [.chat, .activity, .card, .setup])
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        for tab in TafView.Tab.allCases { try expect(words(tab.titleKey) != tab.titleKey, tab.titleKey) }
    },
    Test("a taf's chat reads that taf's conversation, without asking which taf is Coach", awaiting: { @MainActor in
        let (_, chat, transport) = try await make([(200, tafThread)])
        try expectEqual(transport.sent.map(\.method), ["GET"])
        try expect(transport.sent[0].path.removingPercentEncoding == "/v1/tafs/taf-1/conversation", "read \(transport.sent[0].path)")
        guard case .loaded(let coach, _) = chat.state else { throw Failure(description: "not loaded") }
        try expectEqual(coach.id, "taf-1")
    }),
    Test("a Card with no rules has no empty panel under it on the Card tab", awaiting: { @MainActor in
        // Whether a panel's white shows anywhere down the page's middle, under the Card's face.
        @MainActor func panelUnderCard(rules: String) throws -> Bool {
            let json = #"{"tafs":[{"id":"taf-2","name":"Refunds","kiff_agent":"a2","state":"idle","card":{"cards":[{"id":"c9","title":"Refunds","rules":\#(rules)}]}}]}"#
            let taf = try AccountClient.decoder.decode(Home.Page.self, from: Data(json.utf8)).tafs[0]
            let chat = CoachModel(cloud: CloudClient(transport: CannedTransport([]), session: session), taf: Coach(id: "taf-2", name: "Refunds"), sleep: { _ in })
            guard let bitmap = Snapshot.bitmap(of: TafView(taf: taf, chat: chat, tab: .card), size: CGSize(width: 980, height: 860)) else {
                throw Failure(description: "no bitmap")
            }
            return (330...760).contains { Snapshot.hex(bitmap, x: 490, y: $0) == Palette.panel.light }
        }
        let withRules = try panelUnderCard(rules: #"[{"label":"Refund a payment","outside":"hold"}]"#)
        let without = try panelUnderCard(rules: "[]")
        try expect(withRules, "a Card with rules has its panel")
        try expect(!without, "a Card with none has no panel")
    }),
    Test("the screenshots: each of a taf's tabs, in three languages", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr", "pt"] {
            for tab in TafView.Tab.allCases {
                let (taf, chat, _) = try await make([(200, tafThread)])
                // The Setup with a connection whose sign-in expired: its rows and Connect again show.
                let (read, _) = try await pages(setup: "taf-setup-reconnect.json")
                let view = TafView(taf: taf, chat: chat, pages: read, tab: tab).environment(\.words, Words.load(folder: strings, preferred: [language]))
                guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 860)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
                try png.write(to: folder.appendingPathComponent("taf-\(tab.rawValue)-\(language).png"))
            }
        }
    }),
    Test("who the taf is shared with shows under its head only for whoever manages it", awaiting: { @MainActor in
        let groups = #"{"groups":[{"id":"g1","name":"Support","members":[],"agents":["a"]}]}"#
        let members = #"{"members":[{"subject":"u2","role":"member","status":"active","email":"ana@acme.com"}]}"#
        let account = AccountClient(transport: CannedTransport([(200, groups), (200, members)]), session: session)
        let people = PeopleModel(account: account)
        await people.load()
        let (taf, chat, _) = try await make([(200, tafThread)])
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        let line = ShareLine(agent: taf.kiffAgent, account: account, people: people, email: "zoe@example.com",
                             shares: [Shares.Share(group: "g1"), Shares.Share(subject: "u2")])
        let size = CGSize(width: 980, height: 300)
        guard let managed = Snapshot.bitmap(of: TafView(taf: taf, chat: chat, manages: true, shareLine: line).environment(\.words, words), size: size),
              let notManaged = Snapshot.bitmap(of: TafView(taf: taf, chat: chat, manages: false, shareLine: line).environment(\.words, words), size: size),
              let png = Snapshot.png(managed) else { throw Failure(description: "no bitmap") }
        try expect(Snapshot.png(notManaged) != png, "the line shows only when managed")
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: "build/screenshots"), withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: "build/screenshots/taf-shared-en.png"))
    }),
]

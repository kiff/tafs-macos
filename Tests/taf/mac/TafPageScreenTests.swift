import AppKit
import Foundation
import SwiftUI

private let pageSession = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

/// A taf with tafs cloud's time zone words and a Card that says how KIFF counts its tool.
private let pageTaf = #"""
{"tafs":[{"id":"taf-1","name":"Unanswered emails","kiff_agent":"a1","color":2,"state":"idle",
  "job_summary":"Every weekday at 9, lists inbox emails you haven't answered.",
  "time_zone_words":"Times are in Paris time.","schedule_time_zone_words":"Its schedule runs on New York time.",
  "card":{"cards":[{"id":"c1","title":"Inbox","active":true,
    "rules":[{"label":"List inbox conversations","outside":"refuse","count_per_window":200,"window_words":{"each":"a day","now":"today"}}],
    "calls":{"limit":200,"used":1,"window_words":{"each":"a day","now":"today"}},
    "counted":[{"tool":"mail.list","title":"List inbox conversations","lines":["Each listing counts as one call."]}]}]}}]}
"""#

/// A taf's chat with an `ask_coach` card in it.
private let askThread = #"""
{"working":false,"items":[
  {"type":"message","message":{"id":"m1","at":"2026-11-16T08:59:00Z","from":"owner","text":"Could you run at 8 on weekdays?"}},
  {"type":"card","card":{"key":"s1#ask-1","at":"2026-11-16T09:00:00Z","session":"s1","component":{"type":"ask_coach","id":"ask-1","text":"Run it at 8 instead of 9 on weekdays."}}}
]}
"""#

private func pageWords(_ language: String = "en") -> Words {
    Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: [language])
}

/// A contract fixture's answer, as tafs cloud sends it.
private func pageContract(_ file: String) throws -> String {
    let root = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: ".shared/contracts/\(file)"))) as? [String: Any]
    guard let answer = root?["answer"] else { throw Failure(description: "\(file) has no answer") }
    return String(decoding: try JSONSerialization.data(withJSONObject: answer), as: UTF8.self)
}

private func pageHomeTaf() throws -> Home.Taf {
    try AccountClient.decoder.decode(Home.Page.self, from: Data(pageTaf.utf8)).tafs[0]
}

/// The taf's page, its chat read and its Setup read from a contract.
@MainActor
private func pageModels(thread: String = askThread, setup: String = "taf-setup-connected.json") async throws -> (CoachModel, TafPagesModel, CannedTransport) {
    let transport = CannedTransport([(200, thread), (200, try pageContract(setup))])
    let cloud = CloudClient(transport: transport, session: pageSession)
    let chat = CoachModel(cloud: cloud, taf: Coach(id: "taf-1", name: "Unanswered emails"), sleep: { _ in })
    await chat.load()
    let pages = TafPagesModel(cloud: cloud, taf: "taf-1")
    await pages.loadSetup()
    return (chat, pages, transport)
}

/// Writes a view in light and dark, as `<name>-<light|dark>.png`, and answers both bitmaps.
@MainActor
private func shoot<V: View>(_ view: V, _ name: String, size: CGSize = CGSize(width: 1100, height: 900)) throws -> [NSBitmapImageRep] {
    let folder = URL(fileURLWithPath: "build/screenshots")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var drawn: [NSBitmapImageRep] = []
    for dark in [false, true] {
        guard let bitmap = Snapshot.bitmap(of: view, size: size, dark: dark), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG for \(name)") }
        try png.write(to: folder.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        drawn.append(bitmap)
    }
    return drawn
}

/// Whether the taf's colour is drawn anywhere in a box of the bitmap.
private func tafColour(_ bitmap: NSBitmapImageRep, x: ClosedRange<Int>, y: ClosedRange<Int>) -> Bool {
    let colour = Palette.tafColor(2)
    return x.contains { px in stride(from: y.lowerBound, through: y.upperBound, by: 4).contains { Snapshot.hexes(bitmap, x: px, y: $0).contains(colour) } }
}

let tafPageMacTests: [Test] = [
    Test("the Card tab: its time zone, the Card issued by You, How this is counted, Halt, its versions, Usage and Revoke for whoever manages it; only reads go", awaiting: { @MainActor in
        let taf = try pageHomeTaf()
        let (chat, pages, transport) = try await pageModels()
        let me = try AccountClient.decoder.decode(Me.self, from: Data(#"{"tenant_display_name":"Acme"}"#.utf8))
        let managed = TafView(taf: taf, chat: chat, pages: pages, manages: true, me: me, tab: .card).environment(\.words, pageWords())
        let other = TafView(taf: taf, chat: chat, pages: pages, manages: false, me: me, tab: .card).environment(\.words, pageWords())
        let shots = try shoot(managed, "taf-card-managed")
        let others = try shoot(other, "taf-card-member")
        try expect(Snapshot.png(shots[0]) != Snapshot.png(others[0]), "Halt, its versions, Usage and Revoke only for whoever manages it")
        try expect(Snapshot.png(shots[0]) != Snapshot.png(shots[1]), "light and dark")
        _ = try shoot(TafView(taf: taf, chat: chat, pages: pages, manages: true, me: me, tab: .card).environment(\.words, pageWords("fr")), "taf-card-managed-fr")
        try expect(transport.sent.allSatisfy { $0.method == "GET" }, "only reads: \(transport.sent.map(\.method))")
    }),
    Test("a Card's face says who issued it, at its bottom left", awaiting: { @MainActor in
        let card = try pageHomeTaf().cards[0]
        let you = CardFace(card: card, color: Theme.tafColor(2), issuedBy: pageWords()("common.you")).environment(\.words, pageWords())
        let account = CardFace(card: card, color: Theme.tafColor(2), issuedBy: "Acme").environment(\.words, pageWords())
        let size = CGSize(width: 300, height: 190)
        let shots = try shoot(you, "taf-card-face", size: size)
        guard let other = Snapshot.bitmap(of: account, size: size) else { throw Failure(description: "no bitmap") }
        try expect(Snapshot.png(shots[0]) != Snapshot.png(other), "the issuer is drawn")
    }),
    Test("How this is counted lists KIFF's lines under each tool's title", awaiting: { @MainActor in
        let card = try pageHomeTaf().cards[0]
        _ = try shoot(CountedView(card: card, close: {}).environment(\.words, pageWords()), "taf-counted", size: CGSize(width: 480, height: 440))
    }),
    Test("the Setup tab in the iPad's order: the job with Improve in Coach, Starts when, the apps' ring, Results go to, what it remembers; only reads go", awaiting: { @MainActor in
        let taf = try pageHomeTaf()
        let (chat, pages, transport) = try await pageModels()
        var improved = 0
        let view = TafView(taf: taf, chat: chat, pages: pages, manages: true, improveInCoach: { improved += 1 }, openConnect: {}, tab: .setup)
            .environment(\.words, pageWords())
        let plain = TafView(taf: taf, chat: chat, pages: pages, manages: false, tab: .setup).environment(\.words, pageWords())
        let shots = try shoot(view, "taf-setup-ring", size: CGSize(width: 1100, height: 1300))
        guard let member = Snapshot.bitmap(of: plain, size: CGSize(width: 1100, height: 1300)) else { throw Failure(description: "no bitmap") }
        try expect(Snapshot.png(shots[0]) != Snapshot.png(member), "Improve in Coach, + and the removal line only for whoever manages it")
        try expectEqual(improved, 0)
        try expect(transport.sent.allSatisfy { $0.method == "GET" }, "only reads: \(transport.sent.map(\.method))")
        guard case .loaded(let setup) = pages.setup else { throw Failure(description: "not read") }
        try expect(!TafSetup.nodes(setup.connections).isEmpty, "the ring has its apps")
    }),
    Test("the ring places each app from the top, clockwise, as the iPad's", awaiting: { @MainActor in
        try expectEqual(ConnectedToolsRing.angle(0, of: 4), -Double.pi / 2)
        try expectEqual(ConnectedToolsRing.angle(1, of: 4), 0)
        try expectEqual(ConnectedToolsRing.angle(0, of: 0), -Double.pi / 2)
        let top = ConnectedToolsRing.point(-Double.pi / 2, center: CGPoint(x: 100, y: 100), radius: 50)
        try expect(abs(top.x - 100) < 0.001 && abs(top.y - 50) < 0.001, "the first at the top: \(top)")
    }),
    Test("an ask_coach card in a taf's chat has Ask Coach for whoever may, its words alone for anyone else", awaiting: { @MainActor in
        let taf = try pageHomeTaf()
        let (chat, pages, _) = try await pageModels()
        guard case .loaded(_, let page) = chat.state else { throw Failure(description: "not read") }
        let asks = page.items.compactMap { item -> String? in if case .card(let card, _) = item { return card.askCoach } else { return nil } }
        try expectEqual(asks, ["Run it at 8 instead of 9 on weekdays."])
        var asked: [String] = []
        let may = TafView(taf: taf, chat: chat, pages: pages, manages: true, askCoach: { asked.append($0) }, tab: .chat).environment(\.words, pageWords())
        let mayNot = TafView(taf: taf, chat: chat, pages: pages, manages: true, tab: .chat).environment(\.words, pageWords())
        let shots = try shoot(may, "taf-chat-ask-coach")
        guard let alone = Snapshot.bitmap(of: mayNot, size: CGSize(width: 1100, height: 900)) else { throw Failure(description: "no bitmap") }
        try expect(Snapshot.png(shots[0]) != Snapshot.png(alone), "Ask Coach only for whoever may")
        try expectEqual(asked, [])
    }),
    Test("Coach asked about a taf's card has the card's words in its box, nothing sent, only for whoever manages it", awaiting: { @MainActor in
        let transport = CannedTransport([])
        let coach = CoachModel(cloud: CloudClient(transport: transport, session: pageSession), sleep: { _ in })
        let taf = CoachModel.Improving(id: "taf-1", name: "Unanswered emails")
        coach.ask(about: taf, words: "Run it at 8.", mayUseCoach: true, manages: false)
        try expectEqual(coach.draft, "")
        coach.ask(about: taf, words: "Run it at 8.", mayUseCoach: true, manages: true)
        try expectEqual(coach.draft, "Run it at 8.")
        try expectEqual(transport.sent.count, 0)
    }),
    Test("Share is beside who it's shared with, and a click sends nothing", awaiting: { @MainActor in
        let account = AccountClient(transport: CannedTransport([(200, #"{"groups":[]}"#), (200, #"{"members":[]}"#)]), session: pageSession)
        let people = PeopleModel(account: account)
        await people.load()
        let line = ShareLine(agent: "a1", account: account, people: people, email: "zoe@example.com", shares: [])
        _ = try shoot(line.environment(\.words, pageWords()).padding(16), "taf-share", size: CGSize(width: 520, height: 90))
    }),
    Test("the Activity: its Cards in the side column, as the Chat's, never a bar above it; its calls as plain rows", awaiting: { @MainActor in
        let taf = try pageHomeTaf()
        let transport = CannedTransport([(200, askThread), (200, try pageContract("taf-activity.json"))])
        let cloud = CloudClient(transport: transport, session: pageSession)
        let chat = CoachModel(cloud: cloud, taf: Coach(id: "taf-1", name: taf.name), sleep: { _ in })
        await chat.load()
        let pages = TafPagesModel(cloud: cloud, taf: "taf-1")
        await pages.loadActivity()
        let view = TafView(taf: taf, chat: chat, pages: pages, manages: true, tab: .activity).environment(\.words, pageWords())
        let shots = try shoot(view, "taf-activity-side")
        for bitmap in shots {
            // The page is 1100 wide, inset 24: the column is the last 360 points.
            try expect(tafColour(bitmap, x: 720...1060, y: 140...520), "the Card in the side column")
            try expect(!tafColour(bitmap, x: 30...690, y: 140...520), "no Card bar beside the calls")
        }
    }),
    Test("Usage reads the taf's credits; More runs adds the next page after them; a failed read keeps them and says why", awaiting: { @MainActor in
        let first = #"{"credits":120,"runs":2,"words":"120 credits this period","items":[{"run":"r1","at":"2026-11-16T09:00:00Z","credits":40,"counted":true,"words":"40 credits · 3 emails listed"},{"run":"r2","at":"2026-11-15T09:00:00Z","credits":0,"counted":false,"why":"trial","words":"Trial · not counted"}],"next":"c2"}"#
        let second = #"{"credits":120,"words":"120 credits this period","items":[{"run":"r3","at":"2026-11-14T09:00:00Z","credits":80,"counted":true,"words":"80 credits · 9 emails listed"}]}"#
        let transport = CannedTransport([(200, first), (200, second), (503, #"{"error":"down","words":"tafs cloud is busy."}"#)])
        let model = TafCreditsModel(cloud: CloudClient(transport: transport, session: pageSession), taf: "taf-1")
        await model.load()
        try expectEqual(model.credits?.items.map(\.run), ["r1", "r2"])
        await model.load(more: true)
        try expectEqual(model.credits?.items.map(\.run), ["r1", "r2", "r3"])
        try expectEqual(model.credits?.next, nil)
        await model.load()
        try expectEqual(model.credits?.items.map(\.run), ["r1", "r2", "r3"])
        try expectEqual(model.error, "tafs cloud is busy.")
        try expectEqual(transport.sent.map(\.path), ["/v1/usage/credits/tafs/taf-1", "/v1/usage/credits/tafs/taf-1?after=c2", "/v1/usage/credits/tafs/taf-1"])
        // Drawn last: the sheet reads again when it shows.
        _ = try shoot(TafCreditsView(model: model, name: "Unanswered emails", close: {}).environment(\.words, pageWords()), "taf-usage", size: CGSize(width: 520, height: 520))
    }),
    Test("a run opens its request in the sheet: read once, Back to the runs, Try again after a failed read", awaiting: { @MainActor in
        let detail = #"{"id":"r1","from":"From the website door","line":"Refund order 4471","steps":[{"label":"Read the order","state":"done"},{"label":"Reply","state":"failed","line":"The reply wasn't delivered"}],"deliveries":[{"place":"door_reply","state":"given_up","send_again":true}]}"#
        let transport = CannedTransport([(503, #"{"error":"down","words":"tafs cloud is busy."}"#), (200, detail)])
        let model = TafCreditsModel(cloud: CloudClient(transport: transport, session: pageSession), taf: "taf-1", previous: true)
        await model.open("r1")
        try expectEqual(model.opened, "r1")
        try expectEqual(model.detail, nil)
        try expectEqual(model.detailError, "tafs cloud is busy.")
        await model.readDetail()
        try expectEqual(model.detail?.line, "Refund order 4471")
        try expectEqual(model.detailError, nil)
        try expectEqual(transport.sent.map(\.path), ["/v1/tafs/taf-1/requests/r1", "/v1/tafs/taf-1/requests/r1"])
        // Drawn with Send again and Ask Coach, for someone who manages the taf.
        _ = try shoot(TafCreditsView(model: model, name: "Unanswered emails", manages: true, askCoach: {}, close: {}).environment(\.words, pageWords()),
                      "taf-usage-request", size: CGSize(width: 520, height: 520))
        model.closeDetail()
        try expectEqual(model.opened, nil)
        try expectEqual(model.detail, nil)
    }),
    Test("a run's Send again is tafs cloud's unsigned call, then the request is read again; a failure says why under it", awaiting: { @MainActor in
        let detail = #"{"id":"r1","from":"From the website door","line":"Refund order 4471","steps":[],"deliveries":[{"place":"door_reply","state":"given_up","send_again":true}]}"#
        let transport = CannedTransport([(200, detail), (200, "{}"), (200, detail), (503, #"{"error":"down","words":"tafs cloud is busy."}"#), (200, detail)])
        let model = TafCreditsModel(cloud: CloudClient(transport: transport, session: pageSession), taf: "taf-1")
        await model.open("r1")
        await model.sendAgain(run: "r1", place: "door_reply")
        try expectEqual(transport.sent[1].method + " " + transport.sent[1].path, "POST /v1/tafs/taf-1/requests/r1/deliveries/door_reply/send")
        try expectEqual(transport.sent[1].headers["KIFF-Device-Signature"], nil)
        try expectEqual(model.detailError, nil)
        try expectEqual(model.sendingAgain, [])
        await model.sendAgain(run: "r1", place: "door_reply")
        try expectEqual(model.detailError, "tafs cloud is busy.")
        try expectEqual(transport.sent.count, 5)
    }),
    Test("a run's request offers Send again only to whoever manages the taf, and Ask Coach only where given (sources)") {
        let view = try String(contentsOf: URL(fileURLWithPath: "Sources/App/taf/TafCreditsView.swift"), encoding: .utf8)
        try expect(view.contains("if delivery.sendAgain, manages {"), "Send again for whoever manages it")
        try expect(view.contains("if run.opens {"), "a run opens only while tafs cloud says it can")
        let usage = try String(contentsOf: URL(fileURLWithPath: "Sources/App/usage/UsageView.swift"), encoding: .utf8)
        try expect(usage.contains("askCoach: manages ? openCoach : nil"), "Ask Coach only for a managed taf")
        let window = try String(contentsOf: URL(fileURLWithPath: "Sources/App/shell/SignedInView.swift"), encoding: .utf8)
        try expect(window.contains("openCoach: mayUseCoach ? openCoach : nil"), "only where Coach may be used")
    },
    Test("See all reads every note; Forget takes one away at once, puts it back when refused, and one already gone stays gone", awaiting: { @MainActor in
        let notes = #"{"notes":[{"id":"n1","path":"/customers/acme.md","content":"Acme pays by card.","updated_at":"2026-11-16T09:00:00Z"},{"id":"n2","path":"/how-you-like-it.md","content":"Short replies.","updated_at":"2026-11-15T09:00:00Z"}]}"#
        let transport = CannedTransport([(200, notes), (503, #"{"error":"down"}"#), (404, #"{"error":"not_found"}"#)])
        let model = TafMemoryModel(cloud: CloudClient(transport: transport, session: pageSession), taf: "taf-1")
        await model.loadAll()
        try expectEqual(model.notes?.map(\.id), ["n1", "n2"])
        guard let first = model.notes?.first else { throw Failure(description: "no note") }
        let refused = await model.forget(first)
        try expectEqual(refused, false)
        try expectEqual(model.notes?.map(\.id), ["n1", "n2"])
        try expectEqual(model.error, "It wasn't forgotten. down")
        let gone = await model.forget(first)
        try expectEqual(gone, true)
        try expectEqual(model.notes?.map(\.id), ["n2"])
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["GET /v1/tafs/taf-1/memory?all=true", "DELETE /v1/tafs/taf-1/memory/n1", "DELETE /v1/tafs/taf-1/memory/n1"])
        // Drawn last: the sheet reads again when it shows.
        _ = try shoot(TafMemoryView(model: model, close: {}).environment(\.words, pageWords()), "taf-memory", size: CGSize(width: 520, height: 520))
    }),
    Test("Starts when has its doors, then Change when it starts with Coach between the follow-ups and Pause, for whoever may", awaiting: { @MainActor in
        let words = pageWords()
        let transport = CannedTransport([(200, knobAnswer)])
        let cloud = CloudClient(transport: transport, session: pageSession)
        let knob = TafKnobModel(cloud: cloud, taf: "taf-1")
        await knob.load(words: words)
        let taf = try pageHomeTaf()
        let doors = DoorsModel(cloud: cloud, taf: "taf-1")
        let size = CGSize(width: 520, height: 900)
        var improved = 0
        let full = StartsWhenView(model: knob, taf: taf, manages: true, timeZone: "Europe/Paris", doors: doors, myEmail: "zoe@example.com",
                                  improveInCoach: { improved += 1 }, close: {}).environment(\.words, words)
        let bare = StartsWhenView(model: knob, taf: taf, manages: true, timeZone: "Europe/Paris", close: {}).environment(\.words, words)
        let shots = try shoot(full, "taf-starts-when", size: size)
        guard let without = Snapshot.bitmap(of: bare, size: size) else { throw Failure(description: "no bitmap") }
        try expect(Snapshot.png(shots[0]) != Snapshot.png(without), "its doors and Change when it starts with Coach")
        try expectEqual(improved, 0)
        try expect(transport.sent.allSatisfy { $0.method == "GET" }, "only reads: \(transport.sent.map(\.method))")
    }),
    Test("− and + are as wide as the iPad's: each fills its third of the row", awaiting: { @MainActor in
        let stepper = SizeStepper(label: "How often", canLower: true, canRaise: true, move: { _ in })
            .environment(\.words, pageWords()).background(Color.white)
        guard let bitmap = Snapshot.bitmap(of: stepper, size: CGSize(width: 480, height: 60)) else { throw Failure(description: "no bitmap") }
        // The − button's outline crosses the row's first third, well past 60 points.
        let drawn = (80...140).contains { x in (0...59).contains { y in Snapshot.hexes(bitmap, x: x, y: y).contains { $0 != 0xFFFFFF } } }
        try expect(drawn, "the − button reaches past the old 60 points")
    }),
    Test("Results go to: Add a place from a connected app for whoever may, and a switch on that can't change stays green", awaiting: { @MainActor in
        let words = pageWords()
        let transport = CannedTransport([(200, knobAnswer)])
        let knob = TafKnobModel(cloud: CloudClient(transport: transport, session: pageSession), taf: "taf-1")
        await knob.load(words: words)
        let taf = try AccountClient.decoder.decode(Home.Page.self, from: Data(#"{"tafs":[{"kiff_agent":"a","id":"taf-1","name":"Refunds","state":"working","results":["app"]}]}"#.utf8)).tafs[0]
        let size = CGSize(width: 520, height: 600)
        let managed = ResultsGoToView(model: knob, taf: taf, manages: true, email: "you@example.com", improveInCoach: {}, close: {}).environment(\.words, words)
        let plain = ResultsGoToView(model: knob, taf: taf, manages: true, email: "you@example.com", close: {}).environment(\.words, words)
        let shots = try shoot(managed, "taf-results-go-to", size: size)
        guard let without = Snapshot.bitmap(of: plain, size: size) else { throw Failure(description: "no bitmap") }
        try expect(Snapshot.png(shots[0]) != Snapshot.png(without), "Add a place from a connected app")
        // Alert our phones is the one place on: it can't be turned off, and stays green.
        for bitmap in shots {
            let green = (400...510).contains { x in stride(from: 60, through: 590, by: 2).contains { y in
                Snapshot.hexes(bitmap, x: x, y: y).contains { c in
                    let r = Int(c >> 16 & 0xFF), g = Int(c >> 8 & 0xFF), b = Int(c & 0xFF)
                    return g - r > 40 && g - b > 15
                }
            } }
            try expect(green, "a locked-on switch drawn green")
        }
    }),
]

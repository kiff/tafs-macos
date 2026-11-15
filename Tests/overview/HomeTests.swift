import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

let homePage = #"""
{"tafs":[
  {"id":"taf_1","name":"Refunds","kiff_agent":"agent_refunds","color":1,"state":"working","waiting":2,
   "job_summary":"Refunds orders within its limit.","work":{"status":"working","line":"Working on 3 refunds","needs_you":2},
   "next_run_words":"Next run Mon 08:00","health":{"level":"healthy","lines":[]},"card":{"ids":["c1"]}},
  {"id":"taf_2","name":"Invoices","kiff_agent":"agent_invoices","color":4,"state":"idle","waiting":0,
   "work":{"status":"idle","line":"  ","attention":true},"next_run_words":"Next run Mon 08:00",
   "health":{"level":"degraded","lines":["Its bank connection needs signing in again.","Second line"]}},
  {"name":"Bare","kiff_agent":"agent_bare","state":"stopped"}
],"headline":{"words":"1 taf working."},"needs_you":{"count":2,"words":"2 need you."},"limits":{"text":4000}}
"""#

private func cloud(_ answers: [(Int, String)]) -> (CloudClient, CannedTransport) {
    let transport = CannedTransport(answers)
    return (CloudClient(transport: transport, session: session, language: "fr"), transport)
}

let overviewTests: [Test] = [
    Test("a taf's status is tafs cloud's, active when it isn't sent, as the iPad's CloudTaf.status") {
        func taf(_ fields: String) throws -> Home.Taf {
            try AccountClient.decoder.decode(Home.Taf.self, from: Data((#"{"kiff_agent":"a1","name":"Refunds","#  + fields + "}").utf8))
        }
        try expectEqual(try taf(#""state":"waiting","status":"paused""#).paused, true)
        try expectEqual(try taf(#""state":"paused""#).status, "active")
        try expectEqual(try taf(#""state":"paused""#).paused, false)
        try expect((try? taf(#""state":"idle","status":7"#)) == nil, "a status that isn't words doesn't read")
    },
    Test("the list is read as tafs cloud sends it, with its own counts and words", awaiting: {
        let (client, transport) = cloud([(200, homePage)])
        let page = try await client.home()
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "GET /v1/home")
        try expectEqual(transport.sent[0].headers["Accept-Language"], "fr")
        try expectEqual(page.headline, "1 taf working.")
        try expectEqual(page.needsYouCount, 2)
        try expectEqual(page.needsYouWords, "2 need you.")
        try expectEqual(page.tafs.map(\.name), ["Refunds", "Invoices", "Bare"])
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        try expectEqual(page.tafs[0].now(words, time: { _ in "08:00" }), "Next run Mon 08:00")
        try expectEqual(page.tafs[0].healthNow, nil)
        try expectEqual(page.tafs[0].waiting, 2)
        try expectEqual(page.tafs[0].trouble, nil)
    }),
    Test("now follows the state as the iPad's mapping; what went wrong is the work line, only when flagged", awaiting: {
        let page = try await cloud([(200, homePage)]).0.home()
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        let at: (Date) -> String = { _ in "12:30" }
        // Idle: acting under KIFF. A blank work line is no line, flagged or not.
        try expectEqual(page.tafs[1].now(words, time: at), "Acting under KIFF")
        try expectEqual(page.tafs[1].attention, true)
        try expectEqual(page.tafs[1].healthNow, nil)
        try expectEqual(page.tafs[1].trouble, "Its bank connection needs signing in again.")
        // Any state it doesn't know: its Card isn't active.
        try expectEqual(page.tafs[2].now(words, time: at), "Card not active")
        func taf(_ json: String) throws -> Home.Taf { try AccountClient.decoder.decode(Home.Taf.self, from: Data(json.utf8)) }
        let base = #""kiff_agent":"a","name":"A""#
        try expectEqual(try taf("{\(base),\"state\":\"waiting\"}").now(words, time: at), "Waiting for you")
        try expectEqual(try taf("{\(base),\"state\":\"halted\"}").now(words, time: at), "Halted · resume it from Halt")
        try expectEqual(try taf("{\(base),\"state\":\"working\",\"unscheduled\":true}").now(words, time: at), "Works from its chat")
        try expectEqual(try taf("{\(base),\"state\":\"working\",\"next_run\":\"2026-11-16T12:30:00Z\"}").now(words, time: at), "Next run 12:30")
        try expectEqual(try taf("{\(base),\"state\":\"working\"}").now(words, time: at), "Running")
        // A setup stopped partway says tafs cloud's words, with its chat; without the chat it's none.
        try expectEqual(try taf("{\(base),\"state\":\"idle\",\"finish\":{\"taf\":\"t\",\"session\":\"s\",\"words\":\"Finish setting it up\"}}").now(words, time: at), "Finish setting it up")
        try expectEqual(try taf("{\(base),\"state\":\"idle\",\"finish\":{\"words\":\"Finish\"}}").finishWords, nil)
        // An idle taf that isn't healthy says what went wrong, flagged or not.
        let idle = try taf("{\(base),\"state\":\"idle\",\"work\":{\"status\":\"idle\",\"line\":\"Its bank needs signing in again\"},\"health\":{\"level\":\"degraded\",\"lines\":[\"x\"]}}")
        try expectEqual(idle.healthNow, "Its bank needs signing in again")
        let fine = try taf("{\(base),\"state\":\"idle\",\"work\":{\"status\":\"idle\",\"line\":\"Checked 3 cases\"},\"health\":{\"level\":\"healthy\",\"lines\":[]}}")
        try expectEqual(fine.healthNow, nil)
        try expectEqual(page.tafs[2].color, 0)
        try expectEqual(page.tafs[2].health, nil)
    }),
    Test("a list that isn't one is unreadable, never \"no tafs\", and a missing headline is just absent", awaiting: {
        for body in ["{}", "<html>", #"{"tafs":[{"name":"No agent","state":"idle"}]}"#] {
            do { _ = try await cloud([(200, body)]).0.home(); throw Failure(description: "\(body) was read") } catch let error as KIFFError { try expectEqual(error, .unreadable) }
        }
        let bare = try await cloud([(200, #"{"tafs":[],"headline":7,"needs_you":"soon"}"#)]).0.home()
        try expectEqual(bare.tafs.count, 0)
        try expectEqual(bare.headline, nil)
        try expectEqual(bare.needsYouCount, nil)
    }),
    Test("a last result is its report's first line without Markdown's marks", awaiting: {
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        let report = try JSONDecoder().decode(Runs.Report.self, from: Data(#"{"report":{"status":"idle","text":"\n## **Done:** 3 refunds\nMore"}}"#.utf8))
        try expectEqual(Runs.line(latest: nil, newest: nil, report: report, words: words, time: { _ in "" }), "Done: 3 refunds")
        // The newest run with a chat is the one whose report is read.
        let page = try AccountClient.decoder.decode(Runs.Page.self, from: Data(#"{"runs":[{"session":null,"error":"x"},{"session":"s2"}]}"#.utf8))
        try expectEqual(Runs.latest(page.runs)?.session, "s2")
        let transport = CannedTransport([(200, #"{"runs":[]}"#)])
        _ = try await CloudClient(transport: transport, session: Session(accessToken: "t", expiresIn: 60, tenant: "t1", subject: "u", deviceID: nil)).runs(of: "taf-1")
        try expectEqual(transport.sent.map { "\($0.method) \($0.path)" }, ["GET /v1/tafs/taf-1/runs"])
    }),
    Test("the recipes read as the iPad reads them: by category, each led by the problem it ends, its Card in zones") {
        let json = #"""
        {"categories":[{"id":"money","title":"Money","color":{"light":"#1F7A4D","dark":"#4CC38A"}},{"id":"support","title":"Support","color":{"light":"green","dark":"#000000"}},{"id":"empty","title":"Empty"}],
         "recipes":[{"id":"r1","title":"Refunds","category":"money","headline":"Refunds wait days","line":"Refunds within its limit","say":" Refund orders under €150 ","today":"About 2 hours a week","card":{"allows":["Refund up to €150"],"holds":["Refunds over €150"],"never":[]},"apps":[{"name":"Stripe"},{"logo":"x"}],"proved":" Proved on a test shop. "},
                    {"id":"r2","title":"Replies","category":"support","say":"Answer tickets","headline":7}],
         "home":{"shown":true,"words":"Pick a job for your first taf.","own_words":{"title":"Say it in your own words","line":"Coach builds the taf with you."}},
         "labels":{"allows":"Does on its own","holds":"Asks you first","never":"Never does","hand":"Hand it to Coach"}}
        """#
        let recipes = try JSONDecoder().decode(Recipes.self, from: Data(json.utf8))
        try expectEqual(recipes.byCategory.map(\.category.id), ["money", "support"])
        try expectEqual(recipes.categories[0].color, Shade(light: 0x1F7A4D, dark: 0x4CC38A))
        try expectEqual(recipes.categories[1].color, nil)
        try expectEqual(recipes.homeListsRecipes, true)
        try expectEqual(recipes.groups(picked: "support").map(\.category.id), ["support"])
        try expectEqual(recipes.groups(picked: "gone").count, 2)
        let refunds = recipes.recipes[0]
        try expectEqual(refunds.lead, "Refunds wait days")
        try expectEqual(recipes.recipes[1].lead, "Replies")
        try expectEqual(refunds.apps.map(\.name), ["Stripe"])
        try expectEqual(refunds.proved, "Proved on a test shop.")
        // `say` goes in Coach's box as sent: only `proved` and `sample` are trimmed.
        try expectEqual(refunds.say, " Refund orders under €150 ")
        try expectEqual(recipes.zones(of: refunds).map(\.title), ["Does on its own", "Asks you first"])
        try expectEqual(recipes.handWords, "Hand it to Coach")
        try expectEqual(recipes.homeOwnWords?.title, "Say it in your own words")
        try expectEqual(recipes.homeWords, "Pick a job for your first taf.")
    },
    Test("the recipes are as strict as the iPad's: a category or recipe that doesn't read fails the whole read") {
        func reads(_ json: String) -> Recipes? { try? JSONDecoder().decode(Recipes.self, from: Data(json.utf8)) }
        let ok = #"{"id":"r1","title":"Refunds","category":"money"}"#
        try expect(reads(#"{"categories":[{"id":"money","title":"Money"}],"recipes":[\#(ok)]}"#) != nil, "the plain answer reads")
        for broken in [#"{"recipes":[\#(ok),{"title":"no id"}]}"#, #"{"recipes":[{"id":"r1","title":"Refunds","category":7}]}"#,
                       #"{"recipes":[{"id":"r1","title":"Refunds","say":["x"]}]}"#, #"{"recipes":[{"id":"r1","title":"Refunds","line":false}]}"#,
                       #"{"categories":[{"id":"money"}]}"#, #"{"shown":"yes"}"#] {
            try expect(reads(broken) == nil, "\(broken) fails the read")
        }
        // The rest reads leniently, as the iPad's: a label that isn't words is "", and Home's own
        // words with no title isn't a row.
        let lenient = reads(#"{"categories":[{"id":"money","title":"Money","color":"green"}],"recipes":[\#(ok)],"labels":{"allows":"Does on its own","hand":7},"home":{"shown":true,"words":7,"own_words":{"title":" ","line":"x"}}}"#)
        try expectEqual(lenient?.labels?.allows, "Does on its own")
        try expectEqual(lenient?.handWords, nil)
        try expectEqual(lenient?.homeListsRecipes, true)
        try expectEqual(lenient?.homeWords, nil)
        try expect(lenient?.homeOwnWords == nil, "no own-words row without a title")
    },
    Test("who may use Coach, as the iPad's mayUseCoach: KIFF's answer for Setup, else an account admin") {
        try expectEqual(Access.mayUseCoach(setup: Access(use: true), capabilities: nil), true)
        try expectEqual(Access.mayUseCoach(setup: Access(use: false), capabilities: ["members.manage"]), false)
        try expectEqual(Access.mayUseCoach(setup: nil, capabilities: ["members.manage"]), true)
        try expectEqual(Access.mayUseCoach(setup: nil, capabilities: ["cards.manage"]), false)
        try expectEqual(Access.mayUseCoach(setup: nil, capabilities: nil), false)
    },
    Test("tafs cloud's recipes contract reads: Home's line, its own-words row and the sheet's words") {
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: ".shared/contracts/recipes-home.json"))) as? [String: Any]
        guard let answer = root?["answer"] else { throw Failure(description: "no answer") }
        let recipes = try JSONDecoder().decode(Recipes.self, from: try JSONSerialization.data(withJSONObject: answer))
        try expectEqual(recipes.home?.shown, true)
        try expect(recipes.homeWords?.isEmpty == false, "Home's line")
        try expect(recipes.homeOwnWords?.title.isEmpty == false, "own words")
        try expect(recipes.handWords?.isEmpty == false, "the sheet's button")
        // The contract leaves the recipes out: nothing listed, never an empty list drawn.
        try expectEqual(recipes.homeListsRecipes, false)
    },
    Test("a taf's health keeps tafs cloud's fixes for its lines, only of the kinds the app acts on", awaiting: {
        let json = #"{"tafs":[{"kiff_agent":"a","name":"A","state":"idle","health":{"level":"at_risk","lines":["Its bank needs signing in again.","  ","Credits are low."],"fixes":[{"line":0,"kind":"coach","words":"Fix it with Coach","say":"Sign my bank in again"},{"line":0,"kind":"coach","words":"No say"},{"line":1,"kind":"credits","words":"Add credits"},{"line":0,"kind":"teleport","words":"Beam it"},{"kind":7}]}}]}"#
        let taf = try await cloud([(200, json)]).0.home().tafs[0]
        guard let health = taf.health else { throw Failure(description: "no health") }
        try expectEqual(health.lines, ["Its bank needs signing in again.", "Credits are low."])
        try expectEqual(health.needsAttention, true)
        try expectEqual(health.failing, false)
        try expectEqual(health.fixes(for: 0).map(\.words), ["Fix it with Coach"])
        try expectEqual(health.fixes(for: 1).map(\.kind), ["credits"])
        try expectEqual(health.fixes(for: 0).first?.say, "Sign my bank in again")
    }),
    Test("a health line that isn't words is left out, never the others, as the iPad's LenientItem", {
        let health = try JSONDecoder().decode(Home.Taf.Health.self, from: Data(#"{"level":"failing","lines":["A",null,"B",7]}"#.utf8))
        try expectEqual(health.lines, ["A", "B"])
        try expectEqual(health.failing, true)
    }),
]

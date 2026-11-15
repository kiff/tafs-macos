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
    Test("the gallery reads as the iPad's: a job or category that doesn't read is left out, missing words are none", awaiting: {
        let json = #"""
        {"categories":[{"id":"money","title":"Money"},{"title":"no id"}],
         "recipes":[{"id":"r1","title":"Refunds","category":"money","say":"Refund"},{"id":"r2","title":"Disputes","category":"money"},{"id":"r3","title":"Invoices","category":"money"},{"title":"no id"},{"id":"r4","title":"x","say":7}],
         "strip":{"shown":true,"title":"Jobs to try","ids":["r3","gone","r1"]},
         "words":{"title":"New taf","all":"All jobs","own_words":"Say it in your own words","explore":" Explore jobs ","see_all":"See all jobs","try":"Try it with Coach","sample":"What it reported","own_words_line":7},
         "labels":{"hand":"Set it up with Coach"}}
        """#
        let (client, transport) = cloud([(200, json), (200, "{}")])
        let gallery = try await client.recipesGallery()
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "GET /v1/recipes/gallery")
        try expectEqual(gallery.categories.map(\.id), ["money"])
        try expectEqual(gallery.recipes.map(\.id), ["r1", "r2", "r3"])
        // The strip in tafs cloud's order, an id it doesn't list skipped.
        try expectEqual(gallery.stripRecipes.map(\.id), ["r3", "r1"])
        try expectEqual(gallery.seeAll, "See all jobs")
        try expectEqual(gallery.explore, "Explore jobs")
        try expectEqual(gallery.title(browse: true), "Explore jobs")
        try expectEqual(gallery.title(browse: false), "New taf")
        try expectEqual(gallery.handWords(browse: true, labels: gallery.labels), "Try it with Coach")
        try expectEqual(gallery.handWords(browse: false, labels: gallery.labels), "Set it up with Coach")
        try expectEqual(gallery.sampleLabel, "What it reported")
        try expectEqual(gallery.words.ownWordsLine, "")
        try expectEqual(gallery.category(of: gallery.recipes[0])?.title, "Money")
        try expectEqual(gallery.asRecipes().labels?.hand, "Set it up with Coach")
        try expectEqual(gallery.asRecipes().byCategory.first?.recipes.map(\.id), ["r1", "r2", "r3"])
        let empty = try await client.recipesGallery()
        try expectEqual(empty.recipes, [])
        try expectEqual(empty.explore, nil)
        try expectEqual(empty.seeAll, nil)
        try expectEqual(empty.stripRecipes, [])
        try expectEqual(empty.title(browse: true), "")
        try expectEqual(empty.handWords(browse: true, labels: nil), nil)
        try expectEqual(empty.sampleLabel, nil)
    }),
    Test("the strip's See all is tafs cloud's, else its All jobs, and none when the strip shows every job; it shows only when tafs cloud says") {
        let gallery = { (strip: String, words: String) in
            try JSONDecoder().decode(Gallery.self, from: Data((#"{"recipes":[{"id":"r1","title":"A"},{"id":"r2","title":"B"}],"strip":"# + strip + #","words":"# + words + "}").utf8))
        }
        try expectEqual(try gallery(#"{"shown":true,"ids":["r1"]}"#, #"{"all":"All jobs"}"#).seeAll, "All jobs")
        try expectEqual(try gallery(#"{"shown":true,"ids":["r1","r2"]}"#, #"{"see_all":"See all"}"#).seeAll, nil)
        try expectEqual(try gallery(#"{"shown":true,"ids":["r1"]}"#, #"{"see_all":"  "}"#).seeAll, nil)
        try expectEqual(try gallery(#"{"shown":false,"ids":["r1"]}"#, "{}").stripRecipes, [])
        // The sheet's words from /v1/recipes, where the gallery sends none.
        let recipes = try JSONDecoder().decode(Recipes.self, from: Data(#"{"labels":{"hand":"Hand it over"}}"#.utf8))
        try expectEqual(try gallery("{}", "{}").asRecipes(labels: recipes.labels).labels?.hand, "Hand it over")
    },
]

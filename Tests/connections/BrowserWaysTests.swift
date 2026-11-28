import Foundation

/// Connect apps' read as tafs cloud sends it with browser batch 2 (tafs docs/api.md, "How a taf uses websites"): the two
/// ways for the account, and a browser connection's way and each saved sign-in's health, every word as sent.
private let page = #"""
{"apps":[
  {"entry":"browser","name":"Websites","state":"connected","grant":"g_web","way":"cloud",
   "way_words":{"title":"Cloud browser","line":"Works while your computer is off."},
   "sites":[
     {"site":"supplier-portal.example","health":{"state":"needs_you_soon","needs_you_by":"2026-12-02T00:00:00Z","checked_at":"2026-11-28T07:00:00Z",
      "words":{"line":"Needs you by Tue 2 Dec","why":"At 07:00, tafs opened one page of the site with your saved sign-in, without clicking anything. The site set your saved sign-in to end on 2 Dec."}}},
     {"site":"books.example","health":{"state":"signed_in","checked_at":"2026-11-28T07:00:00Z","words":{"line":"Signed in · checked today 07:00"}}},
     {"site":"tax-office.example","health":{"state":"stopped","checked_at":"2026-11-28T07:55:00Z","words":{"line":"Stopped working at 07:55","why":"The site asked to sign in again."}}},
     {"site":"new.example","health":{"state":"unknown","words":{"line":"Not checked"}}},
     {"site":"odd.example","health":{"state":"maybe","words":{"line":"Not checked"}}},
     {"site":"","health":{"state":"signed_in","words":{"line":"x"}}},
     {"site":"broken-health.example","health":{"state":"stopped"}}
   ]},
  {"entry":"chrome","name":"Your Chrome","state":"connected","way":"chrome","chrome_name":"Office Mac",
   "way_words":{"title":"Chrome extension","line":"Works in your Chrome, where you're signed in."},
   "sites":[{"site":"never.example","health":{"state":"stopped","words":{"line":"x"}}}]},
  {"entry":"stripe","name":"Stripe","state":"connected","way":"cloud"}
],
"ways":[
  {"way":"cloud","words":{"title":"Cloud browser","line":"Works while your computer is off.",
   "facts":["A fresh browser for each run, only on the sites you allow.","You sign in once, in a live view. Your password is never kept."],"status":"2 sign-ins saved"}},
  {"way":"chrome","words":{"title":"Chrome extension","line":"Works in your Chrome, where you're signed in.",
   "facts":["Uses the sign-ins already in your Chrome. Your passwords stay there.","Banks and password managers stay blocked unless your phone allows each one."]}},
  {"way":"carrier pigeon","words":{"title":"x","line":"y","facts":[]}},
  {"way":"cloud","words":{"line":"no title"}}
]}
"""#

let connectionsBrowserWaysTests: [Test] = [
    Test("Connect apps lists both ways for the account, each with its words, facts and status; an unknown way or one without words is left out") {
        let p = try AccountClient.decoder.decode(Apps.Page.self, from: Data(page.utf8))
        try expectEqual(p.ways.map(\.way), ["cloud", "chrome"])
        try expectEqual(p.ways[0].words.facts.count, 2)
        try expectEqual(p.ways[0].words.status, "2 sign-ins saved")
        try expect(p.ways[1].words.status == nil, "nothing to say: no status")
        let older = try AccountClient.decoder.decode(Apps.Page.self, from: Data(#"{"apps":[]}"#.utf8))
        try expect(older.ways.isEmpty, "a tafs cloud before them: none")
    },
    Test("a cloud connection lists each saved sign-in with tafs cloud's health; a site that doesn't read is left out, and odd health reads as unknown") {
        let p = try AccountClient.decoder.decode(Apps.Page.self, from: Data(page.utf8))
        let web = try p.apps.first { $0.entry == "browser" } ?? { throw Failure(description: "no browser row") }()
        try expectEqual(web.way, "cloud")
        try expectEqual(web.wayWords?.line, "Works while your computer is off.")
        try expectEqual(web.sites.map(\.site), ["supplier-portal.example", "books.example", "tax-office.example", "new.example", "odd.example", "broken-health.example"])
        try expectEqual(web.sites.map { $0.health?.state }, ["needs_you_soon", "signed_in", "stopped", "unknown", "unknown", nil])
        try expectEqual(web.sites.map { $0.health?.tone }, [.soon, .plain, .stopped, .plain, .plain, nil])
        try expectEqual(web.sites.map { $0.health?.asksToSignIn ?? false }, [true, false, true, false, false, false])
        try expectEqual(web.sites[0].health?.words.line, "Needs you by Tue 2 Dec")
        try expect(web.sites[0].health?.words.why?.hasPrefix("At 07:00") == true, "Why?, as sent")
    },
    Test("a chrome connection keeps no sign-in, so it lists none, and carries its paired Chrome's name; another app has no way") {
        let p = try AccountClient.decoder.decode(Apps.Page.self, from: Data(page.utf8))
        let chrome = try p.apps.first { $0.entry == "chrome" } ?? { throw Failure(description: "no chrome row") }()
        try expectEqual(chrome.way, "chrome")
        try expectEqual(chrome.chromeName, "Office Mac")
        try expect(chrome.sites.isEmpty, "no sign-ins kept at tafs")
        let stripe = try p.apps.first { $0.entry == "stripe" } ?? { throw Failure(description: "no stripe row") }()
        try expectEqual(stripe.way, "cloud")
        try expect(stripe.wayWords == nil && stripe.sites.isEmpty, "no words sent: nothing drawn for its way")
    },
    Test("direction characters are taken out of a way's and a sign-in's words") {
        let json = #"{"apps":[{"entry":"b","name":"W","state":"connected","way":"cloud","sites":[{"site":"a‮b.example","health":{"state":"stopped","words":{"line":"Stopped ‮working"}}}]}],"ways":[{"way":"cloud","words":{"title":"Cloud ‮browser","line":"x","facts":["‮"]}}]}"#
        let p = try AccountClient.decoder.decode(Apps.Page.self, from: Data(json.utf8))
        try expect(!p.ways[0].words.title.unicodeScalars.contains { $0.value == 0x202E }, "title")
        try expect(p.ways[0].words.facts.isEmpty, "a fact that's only a direction character is none")
        try expect(!(p.apps[0].sites[0].site.unicodeScalars.contains { $0.value == 0x202E }), "site")
        try expect(!(p.apps[0].sites[0].health?.words.line.unicodeScalars.contains { $0.value == 0x202E } ?? true), "line")
    },
]

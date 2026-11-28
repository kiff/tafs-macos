import Foundation

/// Home's `sign_ins` (tafs docs/api.md, "Needs you, and the run that waits"): a saved sign-in that needs the owner soon,
/// with Later, or stopped and holding a run, with Skip this run, every word tafs cloud's.
private let home = #"""
{"tafs":[],"sign_ins":[
  {"kind":"sign_in_soon","grant":"g_web","site":"supplier-portal.example","needs_you_by":"2026-12-02T00:00:00Z","taf":{"id":"t1","name":"File invoices"},
   "words":{"title":"Sign-in · needs you soon","line":"supplier-portal.example asks you to sign in again by Tue 2 Dec","sign_in":"Sign in again","later":"Later","why":"At 07:00, tafs opened one page of the site with your saved sign-in."}},
  {"kind":"sign_in_stopped","grant":"g_web","site":"tax-office.example","checked_at":"2026-11-28T06:55:00Z","run_at":"2026-11-28T07:00:00Z","taf":{"id":"t2","name":"VAT return"},
   "words":{"title":"Sign-in · stopped working","line":"VAT return's 8:00 run waits for you. It won't run with a broken sign-in, and it's skipped only if you skip it.","sign_in":"Sign in again","skip":"Skip this run"}},
  {"kind":"sign_in_maybe","grant":"g","site":"s","taf":{"id":"t","name":"n"},"words":{"title":"x","line":"y","sign_in":"z"}},
  {"kind":"sign_in_soon","grant":"g","site":"s","taf":{"id":"t","name":"n"},"words":{"title":"x","line":"y"}},
  {"kind":"sign_in_soon","grant":"","site":"s","taf":{"id":"t","name":"n"},"words":{"title":"x","line":"y","sign_in":"z"}}
]}
"""#

let signInNeedTests: [Test] = [
    Test("Home lists each saved sign-in that needs the owner, soon with Later and stopped with Skip this run; one this app can't draw is left out") {
        let page = try AccountClient.decoder.decode(Home.Page.self, from: Data(home.utf8))
        try expectEqual(page.signIns.map(\.kind), ["sign_in_soon", "sign_in_stopped"])
        try expectEqual(page.signIns.map(\.stopped), [false, true])
        try expectEqual(page.signIns.map(\.words.other), ["Later", "Skip this run"])
        try expectEqual(page.signIns[0].taf.name, "File invoices")
        try expect(page.signIns[0].words.why != nil && page.signIns[1].words.why == nil, "Why?, only when sent")
        let older = try AccountClient.decoder.decode(Home.Page.self, from: Data(#"{"tafs":[]}"#.utf8))
        try expect(older.signIns.isEmpty, "a tafs cloud before them: none")
    },
    Test("Later and Skip this run are the person's own requests, with no signature: Later by connection and site, Skip by taf", awaiting: {
        let transport = CannedTransport([(200, "{}"), (200, "{}")])
        let cloud = CloudClient(transport: transport, session: Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil))
        try await cloud.laterSignIn(grant: "g/1", site: "a.example")
        try await cloud.skipHeldSignIn(taf: "t 1")
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["POST /v1/needs-you/sign-in/g%2F1/a.example/later", "POST /v1/tafs/t%201/held-sign-in/skip"])
        try expect(transport.sent.allSatisfy { $0.headers["Authorization"] == "Bearer tok" }, "the person's session")
    }),
]

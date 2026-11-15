import Foundation

private let calls = #"""
{"exceptions":[
  {"id":"exc_1","subject":"agent_deploys","action":"deploy.migrate","title":"Run migration 0042","reason_text":"Schema migrations: always asks you",
   "created_at":"2026-11-15T00:17:00Z","expires_at":"2026-11-15T00:27:00Z"},
  {"id":"exc_2","subject":"agent_gone","action":"pay.send","created_at":"2026-11-15T00:17:00Z"},
  {"id":"exc_3","subject":"agent_deploys","action":"deploy.run","reason_text":"Over its limit","created_at":"2026-11-15T00:17:00Z"},
  {"id":"exc_4","subject":"agent_deploys","action":"deploy.run","created_at":"2026-11-15T00:17:00Z","expires_at":"2026-11-15T00:27:00Z"}
]}
"""#

private let home = #"{"tafs":[{"name":"Deploys","kiff_agent":"agent_deploys","state":"waiting"}]}"#

private struct Held: Decodable { let exceptions: [HeldCall] }

let shellHeldTests: [Test] = [
    Test("a held call in the sidebar is its taf's name and what it asks, then why and the time to answer by") {
        let held = try AccountClient.decoder.decode(Held.self, from: Data(calls.utf8)).exceptions
        let tafs = try JSONDecoder().decode(Home.Page.self, from: Data(home.utf8)).tafs
        let rows = held.map { HeldRow($0, tafs: tafs) }
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        let time: (Date) -> String = { _ in "00:27" }
        // Each call as the iPad names it (`summary`): the title, with the action in words when
        // the title doesn't say it; the action in words without a title.
        try expectEqual(rows.map(\.title), ["Deploys: Run migration 0042 · migrate", "send", "Deploys: run", "Deploys: run"])
        try expectEqual(rows[0].line(words, time: time), "Schema migrations: always asks you · answer by 00:27")
        // A taf that isn't listed: the call alone, never a name made up.
        try expectEqual(rows[1].line(words, time: time), nil)
        try expectEqual(rows[2].line(words, time: time), "Over its limit")
        try expectEqual(rows[3].line(words, time: time), "answer by 00:27")
        try expectEqual(rows.map(\.id), ["exc_1", "exc_2", "exc_3", "exc_4"])
        try expectEqual(rows.map(\.taf), ["Deploys", nil, "Deploys", "Deploys"])
        try expectEqual(rows[0].asks, "Run migration 0042 · migrate")
    },
]

import Foundation

private func english() -> Words { (try? Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))) ?? Words(language: "en", lines: [:]) }
private let at = Date(timeIntervalSince1970: 1_794_679_800)

private func clients() -> (AccountClient, CloudClient, SampleTransport) {
    let transport = SampleTransport(words: english(), now: { at })
    return (AccountClient(transport: transport, session: Sample.session), CloudClient(transport: transport, session: Sample.session), transport)
}

/// The sample, as the iPad's `loadSample` and Windows' `--sample`: read through this Mac's own clients, as its screens
/// read tafs cloud and KIFF.
let shellSampleTests: [Test] = [
    Test("the sample's Home is the iPad's five tafs, Support replies first, each with its Card, read by Home's own decoder", awaiting: {
        let (_, cloud, _) = clients()
        let home = try await cloud.home()
        try expectEqual(home.tafs.map(\.name), ["Support replies", "Late parcels", "Access", "Deploys", "Lead follow-up"])
        try expectEqual(home.tafs.map(\.state), Array(repeating: "working", count: 5))
        try expect(home.tafs.allSatisfy { !$0.cards.isEmpty }, "each with its Card")
        try expectEqual(home.tafs[0].cards.first?.rules.map(\.label), ["Replies", "Promises", "Customer data"])
        try expectEqual(home.tafs.map(\.waiting), [1, 1, 0, 1, 0])
    }),
    Test("the calls its Cards hold wait in Needs you, as the iPad's first two rounds: Support's promise, the reship, the migration", awaiting: {
        let (account, _, _) = clients()
        let held = try await account.heldCalls()
        try expectEqual(held.map(\.subject), ["sample-agent-support", "sample-agent-parcels", "sample-agent-deploys"])
        try expectEqual(held.map(\.title), [english()("sample.support.promise_7802"), english()("sample.parcels.reship_5098"), english()("sample.deploys.migration")])
        try expectEqual(Sample.done().count, 7)
    }),
    Test("the sample's account approves nothing and names itself Sample data; its lists read as empty, never unread", awaiting: {
        let (account, _, _) = clients()
        let me = try await account.me()
        try expectEqual(me.approvalMode, "view")
        try expectEqual(me.account, "Sample data")
        let devices = try await account.devices()
        try expectEqual(devices.map(\.name), ["tafs on Mac", "tafs on iPhone", "tafs on Mac"])
        try expectEqual(devices.map(\.thisDevice), [true, false, false])
        let unproven = try await account.didThisHappen()
        try expectEqual(unproven, [])
    }),
    Test("the sample writes and approves nothing: every write is refused in the app's words, and nothing reaches the network", awaiting: {
        let (_, cloud, transport) = clients()
        do { _ = try await cloud.post("/v1/tafs/sample-support/runs", [:]); throw Failure(description: "written") } catch let refusal as CloudRefusal {
            try expectEqual(refusal.status, 403)
            try expectEqual(refusal.words, english()("sign_in.with_kiff"))
        }
        // An unknown read is "not found", in the same words: a screen says it as it says any read that failed.
        let (status, _) = try await transport.send(HTTPRequest(method: "GET", path: "/v1/tafs/sample-support/knob", headers: [:], body: Data()))
        try expectEqual(status, 404)
        try expectEqual(Sample.session.deviceID, nil)
    }),
    Test("Plan & usage reads the iPad's sample balance and both periods' credits; the Record, each call done or waiting", awaiting: {
        let (_, cloud, _) = clients()
        let balance = try await cloud.balance()
        try expectEqual(balance.words, english()("sample.credits.balance_words"))
        let now = try await cloud.credits()
        try expectEqual(now.words, english()("sample.credits.this_period"))
        try expectEqual(now.rows.map(\.taf), ["sample-support", "sample-parcels"])
        let before = try await cloud.credits(previous: true)
        try expectEqual(before.words, english()("sample.credits.last_period"))
        let record = try await cloud.record()
        try expectEqual(record.entries.count, 10)
        try expectEqual(record.entries.filter { $0.kind == "held" }.count, 3)
        try expectEqual(record.entries.last?.taf.name, "Support replies")
    }),
    Test("a sample taf's page reads its chat, its Setup, its Activity, its runs, notes and work through the page's own decoders", awaiting: {
        let (_, cloud, _) = clients()
        let thread: Thread.Page = try await cloud.get("/v1/tafs/sample-support/conversation")
        try expectEqual(thread.items.count, 2)
        let setup = try await cloud.setup(of: "sample-support")
        try expectEqual(setup.workflow?.summary, english()("sample.support.job"))
        let activity = try await cloud.activity(of: "sample-parcels")
        try expectEqual(activity.groups.flatMap(\.entries).count, 2)
        let runs = try await cloud.runs(of: "sample-parcels")
        try expectEqual(runs, [])
        let notes = try await cloud.memory(of: "sample-parcels")
        try expectEqual(notes, [])
        let work = try await cloud.work(of: "sample-parcels")
        try expectEqual(work.requests, [])
    }),
    Test("no sample answer names a logo, so the app's one logo reader (tafs cloud's /v1/logos/) is never asked in the sample", awaiting: {
        let (_, _, transport) = clients()
        let paths = ["/v1/home", "/v1/me", "/v1/me/card-exceptions?status=held", "/v1/record", "/v1/usage/balance", "/v1/usage/credits",
                     "/v1/tafs/sample-support/conversation", "/v1/tafs/sample-support/setup", "/v1/tafs/sample-support/activity"]
        for path in paths {
            let (_, body) = try await transport.send(HTTPRequest(method: "GET", path: path, headers: [:], body: Data()))
            let text = String(decoding: body, as: UTF8.self)
            try expect(!text.contains("logo") && !text.contains("/v1/logos/"), "\(path) names no logo")
        }
        let window = try String(contentsOf: URL(fileURLWithPath: "Sources/App/shell/SignedInView.swift"), encoding: .utf8)
        try expect(window.contains("OverviewModel(cloud: cloud, remembered: inSample ? nil : .standard)"), "the sample's list is never kept")
        // Nothing alerts in the sample, and its Alerts keep nothing: macOS is never asked.
        try expect(window.contains("AlertsModel(account: account.session.tenant, inSample: inSample)"), "Alerts know the sample")
        try expect(window.contains("guard !inSample else { return }"), "no alert for the sample's held calls")
        let alerts = try String(contentsOf: URL(fileURLWithPath: "Sources/App/account/AlertsView.swift"), encoding: .utf8)
        try expect(alerts.contains("why = Sample.notInSample(words)") && !alerts.contains("\n        prefs.save(to: defaults, account: account)"), "Turn on refused, nothing saved")
    }),
    Test("Play the next sample actions plays each taf's next call, as the iPad's playNextDemoActions: new held calls, a refusal in the Record", awaiting: {
        let (account, cloud, transport) = clients()
        try expectEqual(transport.rounds, 2)
        try expect(transport.playNext(), "a third round")
        let held = try await account.heldCalls()
        // Access's elevated access and the leads' discount are held now too; the first three still wait.
        try expectEqual(held.count, 5)
        let record = try await cloud.record()
        try expectEqual(record.entries.count, 15)
        try expect(record.entries.contains { $0.kind == "refused" && $0.title == "DROP TABLE sessions_old" }, "the Card refused dropping a table")
        try expect(transport.playNext(), "a fourth round")
        try expect(!transport.playNext(), "every script played")
        let home = try await cloud.home()
        let allHeld = try await account.heldCalls()
        try expectEqual(home.tafs.map(\.waiting).reduce(0, +), allHeld.count)
    }),
    Test("every key the sample names is in English, so a sample line never reads as its key") {
        let words = english()
        var keys: [String] = []
        for taf in Sample.tafs {
            keys += ["sample.\(taf.key).name", "sample.\(taf.key).job"] + taf.tools + taf.rules.map(\.label)
            keys += taf.script.flatMap { call in (call.literal ? [] : [call.summary]) + [call.why] }
        }
        keys += ["record.decided.refused_by_card", "record.waiting_for_you", "record.done_within_card",
                 "needs_you.nothing", "card.window.a_day", "card.window.today", "settings.mode_sample", "sign_in.with_kiff"]
        for key in keys { try expect(words(key) != key, "\(key) is in English") }
        // The two counts are plural lines, read by their count.
        for key in ["home.working", "needs_you.count"] { try expect(words.count(key, 2) != key, "\(key) is in English") }
    },
]

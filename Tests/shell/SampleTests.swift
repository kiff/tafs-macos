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
        // Waiting where a call of its waits on the owner, as tafs cloud's stateOf; working otherwise.
        try expectEqual(home.tafs.map(\.state), home.tafs.map { $0.waiting > 0 ? "waiting" : "working" })
        try expectEqual(home.tafs.map(\.state), ["waiting", "waiting", "working", "waiting", "working"])
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
            try expectEqual(refusal.words, english()("sample.not_in_sample"))
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
        // Its hello, the sample question, and the taf's answer to it, as the iPad's `loadSample`.
        try expectEqual(thread.items.count, 3)
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
                 "needs_you.nothing", "card.window.a_day", "card.window.today", "settings.mode_sample", "sample.not_in_sample"]
        for key in keys { try expect(words(key) != key, "\(key) is in English") }
        // The two counts are plural lines, read by their count.
        for key in ["home.working", "needs_you.count"] { try expect(words.count(key, 2) != key, "\(key) is in English") }
    },
    Test("a language chosen in the sample answers in it, from each request's Accept-Language, with the rounds played kept", awaiting: {
        let folder = URL(fileURLWithPath: ".shared/app/strings")
        var asked: [String] = []
        let transport = SampleTransport(words: english(), now: { at }, load: { language in
            asked.append(language)
            return try? Words(language: language, folder: folder)
        })
        transport.playNext()
        let french = try Words(language: "fr", folder: folder)
        let held = try await AccountClient(transport: transport, session: Sample.session, language: "fr").heldCalls()
        try expectEqual(held.first?.title, french("sample.support.promise_7802"))
        try expectEqual(transport.rounds, Sample.firstRounds + 1)
        let again = try await AccountClient(transport: transport, session: Sample.session, language: "fr").heldCalls()
        try expectEqual(again.first?.title, held.first?.title)
        try expectEqual(asked, ["fr"])
        let back = try await AccountClient(transport: transport, session: Sample.session, language: "en").heldCalls()
        try expectEqual(back.first?.title, english()("sample.support.promise_7802"))
        // With no loader, every request is answered in the sample's own words.
        let plain = SampleTransport(words: english(), now: { at })
        let same = try await AccountClient(transport: plain, session: Sample.session, language: "fr").heldCalls()
        try expectEqual(same.first?.title, english()("sample.support.promise_7802"))
    }),
    Test("a sample taf answers in its chat from its own record, as the iPad's sampleReply: what it did, what waits, the note", awaiting: {
        let (_, cloud, transport) = clients()
        let words = english()
        let sent = try await cloud.send("How's it going?", to: "sample-support")
        try expectEqual(sent.session, "sample")
        let page = try await cloud.thread(of: "sample-support")
        let texts: [String] = page.items.compactMap { if case .message(let m, _) = $0 { return m.text } else { return nil } }
        try expect(texts.contains("How's it going?"), "what was said")
        let reply = texts.last ?? ""
        try expect(reply.hasPrefix(words("sample.reply.lately", ["done": ""]).components(separatedBy: "\n").first ?? "Lately"), "what it did lately")
        try expect(reply.contains(words.count("sample.reply.waiting", 1)), "what waits for the owner")
        try expect(reply.hasSuffix(words("sample.reply.note")), "the sample's note")
        // Support replies' sample question has its answer, as on the iPad.
        try expectEqual(texts.filter { $0 == words("sample.chat.question") }.count, 1)
        try expectEqual(transport.talk.said["support"]?.count, 1)
    }),
    Test("stop pauses a sample taf on Home and go brings it back; raise says only its Card gives room; nothing else is written", awaiting: {
        let (_, cloud, transport) = clients()
        let words = english()
        _ = try await cloud.send("Please stop for now", to: "sample-parcels")
        var home = try await cloud.home()
        let parcels = home.tafs.first { $0.name == words("sample.parcels.name") }
        try expectEqual(parcels?.paused, true)
        // The screens read the state: paused, unless a call of its waits on the owner, as tafs cloud's stateOf.
        try expectEqual(parcels?.state, parcels?.waiting == 0 ? "paused" : "waiting")
        _ = try await cloud.send("stop", to: "sample-access")
        let access = try await cloud.home().tafs.first { $0.name == words("sample.access.name") }
        try expectEqual(access?.state, "paused")
        try expectEqual(access?.now(words, time: { _ in "" }), words("taf.state.paused"))
        _ = try await cloud.send("carry on", to: "sample-access")
        _ = try await cloud.send("go", to: "sample-parcels")
        home = try await cloud.home()
        try expectEqual(home.tafs.first { $0.name == words("sample.parcels.name") }?.paused, false)
        try expectEqual(Sample.reply(to: "Can you raise your limit?", taf: Sample.tafs[0], words: words).0, words("sample.reply.more_room"))
        try expectEqual(Sample.reply(to: "gold", taf: Sample.tafs[0], words: words).1, .none)
        try expectEqual(transport.talk.paused, [])
        // Any other write is still refused, with the sample's own line.
        do { try await cloud.setPromise(of: "sample-support", hours: 4); throw Failure(description: "a write went through") } catch let r as CloudRefusal {
            try expectEqual(r.words, words("sample.not_in_sample"))
        }
    }),
    Test("the sample is kept between launches, as the iPad's SampleStore: rounds, chats and pauses come back; Clear forgets it", awaiting: {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sample-kept-\(UUID().uuidString)", isDirectory: true)
        let store = SampleStore(url: folder.appendingPathComponent("sample.json"))
        defer { try? FileManager.default.removeItem(at: folder) }
        try expectEqual(store.load(), nil)
        let first = SampleTransport(words: english(), now: { at }, store: store)
        first.playNext()
        _ = try await CloudClient(transport: first, session: Sample.session).send("stop", to: "sample-access")
        // A later launch: a new transport reads where the person left off.
        let again = SampleTransport(words: english(), now: { at }, store: store)
        try expectEqual(again.rounds, Sample.firstRounds + 1)
        try expectEqual(again.talk.paused, ["access"])
        try expectEqual(again.talk.said["access"]?.map(\.text), ["stop"])
        let home = try await CloudClient(transport: again, session: Sample.session).home()
        let access = home.tafs.first { $0.name == english()("sample.access.name") }
        try expectEqual(access?.paused, true)
        try expectEqual(access?.state, access?.waiting == 0 ? "paused" : "waiting")
        // Clear the sample: nothing is kept.
        again.forget()
        try expectEqual(store.load(), nil)
        try expectEqual(SampleTransport(words: english(), now: { at }, store: store).rounds, Sample.firstRounds)
    }),
    Test("a kept sample that doesn't read is as new; one with rounds past the scripts or a taf that isn't the sample's is held to them") {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sample-bad-\(UUID().uuidString)", isDirectory: true)
        let store = SampleStore(url: folder.appendingPathComponent("sample.json"))
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.url)
        try expectEqual(SampleTransport(words: english(), now: { at }, store: store).rounds, Sample.firstRounds)
        store.save(SampleStore.Saved(rounds: 99, said: [:], paused: ["access", "someone-else"]))
        let held = SampleTransport(words: english(), now: { at }, store: store)
        try expectEqual(held.rounds, Sample.lastRound)
        try expectEqual(held.talk.paused, ["access"])
    },
    Test("the window opens a kept sample at launch with no one signed in, forgets it on Clear and on a sign-in (sources)") {
        let app = try String(contentsOf: URL(fileURLWithPath: "Sources/App/entry/TafsApp.swift"), encoding: .utf8)
        try expect(app.contains("if signIn.session == nil, sample == nil, SampleStore.standard.load() != nil { sample = Self.sample(words) }"), "opened at launch")
        try expect(app.contains("signedOut: { transport.forget(); sample = nil }"), "Clear the sample forgets it")
        try expect(app.contains("SampleStore.standard.clear()"), "a sign-in forgets it")
    },
]

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
        try expectEqual(devices, [])
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
        try expectEqual(record.entries.first?.taf.name, "Support replies")
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
]

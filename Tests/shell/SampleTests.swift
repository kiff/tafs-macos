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
        let (status, _) = try await transport.send(HTTPRequest(method: "GET", path: "/v1/tafs/sample-support/memory", headers: [:], body: Data()))
        try expectEqual(status, 404)
        try expectEqual(Sample.session.deviceID, nil)
    }),
]

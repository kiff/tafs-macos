import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

/// A Mac whose key is in the Secure Enclave (or not), with Touch ID (or not), counting what it asks and sends.
@MainActor
private func make(enclave: Bool, touchID: Bool, passes: Bool = true) -> (ConnectAppsModel, CannedTransport, () -> [String], () -> [String]) {
    // The ending itself is `end`; planque's transport carries only the read again, a signed GET.
    let planque = CannedTransport([(200, #"{"grants":[]}"#)])
    var asked: [String] = []
    var ended: [String] = []
    let source = ConnectionsSource(transport: planque, tenant: "t1", proof: { "t=1,v1=c2ln,d=dev_1" }, enclaveKey: enclave, end: { ended.append($0) })
    let check = TouchIDOnly(available: { touchID }, confirm: { reason in
        asked.append(reason)
        if !passes { throw OwnerPrompt.Closed() }
    })
    let cloud = CannedTransport([(200, #"{"apps":[]}"#)])
    return (ConnectAppsModel(cloud: CloudClient(transport: cloud, session: session), connections: source, touchID: check), planque, { asked }, { ended })
}

/// Ending a connection from this Mac (`ConnectionEnding`, docs/approvals.md).
let connectionEndingMacTests: [Test] = [
    Test("a Mac without Touch ID, or whose key isn't in the Secure Enclave, asks nothing and sends nothing: the phone", awaiting: { @MainActor in
        for (enclave, touchID) in [(true, false), (false, true), (false, false)] {
            let (model, _, asked, ended) = make(enclave: enclave, touchID: touchID)
            try expectEqual(model.endRoute, .phone)
            await model.disconnect("g1", prompt: "Remove access to Qonto?", id: "g1|end")
            await model.clear(["g1"])
            try expect(asked().isEmpty && ended().isEmpty, "nothing asked or sent: \(enclave) \(touchID)")
            try expectEqual(model.notes, [:])
        }
        // No source that can end one: the phone too.
        let bare = ConnectAppsModel(cloud: CloudClient(transport: CannedTransport([]), session: session), touchID: TouchIDOnly(available: { true }, confirm: { _ in }))
        try expectEqual(bare.endRoute, .phone)
    }),
    Test("a Touch ID Mac asks Touch ID with the question, then ends the connection and reads them again", awaiting: { @MainActor in
        let (model, planque, asked, ended) = make(enclave: true, touchID: true)
        try expectEqual(model.endRoute, .touchID)
        await model.disconnect("g1", prompt: "Remove access to Qonto?", id: "g1|end")
        try expectEqual(asked(), ["Remove access to Qonto?"])
        try expectEqual(ended(), ["g1"])
        try expectEqual(model.notes["g1|end"], nil)
        try expect(model.ending.isEmpty, "done")
        try expectEqual(planque.sent.map { $0.method + " " + $0.path }, ["GET /v1/accounts/t1/grants"])
    }),
    Test("a finger added since the session began: Touch ID sends nothing, and the Mac goes to the phone", awaiting: { @MainActor in
        let store = MemoryStore()
        var enrolled: Data? = Data([1])
        var asked = 0
        var ended: [String] = []
        let check = TouchIDOnly.sealed(session: "t1|u1|dev_1", store: store, current: { enrolled }, evaluate: { _ in asked += 1; return enrolled })
        let source = ConnectionsSource(transport: CannedTransport([]), tenant: "t1", proof: { nil }, enclaveKey: true, end: { ended.append($0) })
        let model = ConnectAppsModel(cloud: CloudClient(transport: CannedTransport([]), session: session), connections: source, touchID: check)
        // The first set seen is kept.
        try expectEqual(model.endRoute, .touchID)
        enrolled = Data([1, 2])
        try expectEqual(model.endRoute, .phone)
        await model.disconnect("g1", prompt: "Remove access to Qonto?", id: "g1|end")
        try expect(asked == 0 && ended.isEmpty, "nothing asked or sent")
        // A finger added while the prompt was open: the set it passed with isn't the one kept.
        enrolled = Data([1])
        do { try await TouchIDOnly.sealed(session: "t1|u1|dev_1", store: store, current: { enrolled }, evaluate: { _ in Data([1, 2]) }).confirm("?"); throw Failure(description: "passed") }
        catch is TouchIDOnly.FingersChanged {}
        try expect(ended.isEmpty, "nothing sent")
        // The next sign-in keeps its own.
        try expect(TouchIDOnly.sealed(session: "t1|u1|dev_2", store: store, current: { Data([1, 2]) }, evaluate: { _ in nil }).available(), "a new session")
    }),
    Test("signed out while Touch ID was asking: nothing is sent and nothing read again", awaiting: { @MainActor in
        var ended: [String] = []
        let planque = CannedTransport([])
        let source = ConnectionsSource(transport: planque, tenant: "t1", proof: { "t=1,v1=c2ln,d=dev_1" }, enclaveKey: true, end: { ended.append($0) })
        var model: ConnectAppsModel?
        let check = TouchIDOnly(available: { true }, confirm: { _ in model?.endSession() })
        model = ConnectAppsModel(cloud: CloudClient(transport: CannedTransport([]), session: session), connections: source, touchID: check)
        await model?.disconnect("g1", prompt: "Remove access to Qonto?", id: "g1|end")
        try expect(ended.isEmpty && planque.sent.isEmpty, "nothing sent")
        try expectEqual(model?.notes ?? [:], [:])
        // Ended: nothing more starts.
        await model?.clear(["g1"])
        try expect(ended.isEmpty, "nothing sent")
    }),
    Test("a closed Touch ID prompt sends nothing and Disconnect says nothing", awaiting: { @MainActor in
        let (model, _, asked, ended) = make(enclave: true, touchID: true, passes: false)
        await model.disconnect("g1", prompt: "Remove access to Qonto?", id: "g1|end")
        try expectEqual(asked().count, 1)
        try expect(ended().isEmpty, "nothing sent")
        try expectEqual(model.notes["g1|end"], nil)
    }),
]

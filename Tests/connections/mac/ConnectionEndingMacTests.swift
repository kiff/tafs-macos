import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

/// A Mac whose key is in the Secure Enclave (or not), with Touch ID (or not), counting what it asks and sends.
@MainActor
private func make(enclave: Bool, touchID: Bool, passes: Bool = true) -> (ConnectAppsModel, CannedTransport, () -> [String], () -> [String]) {
    let planque = CannedTransport([(200, "{}"), (200, #"{"grants":[]}"#)])
    var asked: [String] = []
    var ended: [String] = []
    let source = ConnectionsSource(transport: planque, tenant: "t1", proof: { nil }, enclaveKey: enclave, end: { ended.append($0) })
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
        try expect(!planque.sent.isEmpty, "read again")
    }),
    Test("a closed Touch ID prompt sends nothing and Disconnect says nothing", awaiting: { @MainActor in
        let (model, _, asked, ended) = make(enclave: true, touchID: true, passes: false)
        await model.disconnect("g1", prompt: "Remove access to Qonto?", id: "g1|end")
        try expectEqual(asked().count, 1)
        try expect(ended().isEmpty, "nothing sent")
        try expectEqual(model.notes["g1|end"], nil)
    }),
]

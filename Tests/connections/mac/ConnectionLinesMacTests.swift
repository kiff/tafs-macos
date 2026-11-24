import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

let connectionLinesMacTests: [Test] = [
    Test("an app's connections read the Record's newest calls for the last failed call, only when they open; a failed read is none", awaiting: { @MainActor in
        let page = #"{"q":"","entries":[{"id":"e1","at":"2026-11-24T08:00:00Z","kind":"not_done","title":"Refund","detail":"Signed out of Stripe","time":"09:00","taf":{"id":"t1","name":"Refunds"},"call":{"action_name":"stripe_refund"}}],"groups":[]}"#
        let transport = CannedTransport([(200, page), (503, #"{"error":"down"}"#)])
        let model = ConnectAppsModel(cloud: CloudClient(transport: transport, session: session))
        await model.readCalls()
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["GET /v1/record?q="])
        try expectEqual(model.calls.map(\.action), ["stripe_refund"])
        await model.readCalls()
        try expectEqual(model.calls, [])
    }),
]

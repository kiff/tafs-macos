import Foundation

private func planque(_ answers: [(Int, String)]) -> (PlanqueClient, CannedTransport) {
    let transport = CannedTransport(answers)
    let client = PlanqueClient()
    client.tenant = "acme/1"
    client.deviceID = "dev_9"
    client.transport = transport
    return (client, transport)
}

let accountChromeTests: [Test] = [
    Test("Account › Chrome reads planque's Chromes on its safe route: a GET, empty, signed per call by the device key, no session token", awaiting: {
        let (client, transport) = planque([(200, #"{"chromes":[{"chrome_id":"chr_1","name":"Work Mac","browser":"Chrome 131","os":"macOS"},{"name":"no id"}]}"#)])
        var signed: [String] = []
        let chromes = try await client.chromes(signedBy: { signed.append($0); return "SIG" })
        try expectEqual(chromes?.map(\.id), ["chr_1"])
        try expectEqual(chromes?.first?.browser, "Chrome 131")
        let sent = transport.sent[0]
        try expectEqual(sent.method + " " + sent.path, "GET /v1/accounts/acme%2F1/chromes")
        try expectEqual(sent.body, Data())
        try expectEqual(sent.headers["Authorization"], nil)
        try expect(sent.headers["Planque-Device-Signature"]?.hasSuffix(",v1=SIG,d=dev_9") == true, "the device's signature")
        try expectEqual(signed, [PlanqueClient.message(base: PlanqueClient.baseURL, tenant: "acme/1", method: "GET", uri: "/v1/accounts/acme%2F1/chromes",
                                                       bodyHash: PlanqueClient.emptyBodyHash, signedAt: signed.first.map { String($0.split(separator: "\n").last ?? "") } ?? "")])
        // No signer is armed by it: the enrolment's stays the only one.
        try expect(client.signer == nil, "nothing armed")
    }),
    Test("planque not offering Chromes (404), or a person who may only view (403), shows no Chrome row; another refusal is a failed read", awaiting: {
        let (client, _) = planque([(404, #"{"error":"not_found"}"#), (403, #"{"error":"view_only"}"#), (500, #"{"error":"boom"}"#)])
        let off = try await client.chromes(signedBy: { _ in "SIG" })
        try expectEqual(off, nil)
        let view = try await client.chromes(signedBy: { _ in "SIG" })
        try expectEqual(view, nil)
        do { _ = try await client.chromes(signedBy: { _ in "SIG" }); throw Failure(description: "read") } catch PlanqueClient.PlanqueError.server(let status, _, _) {
            try expectEqual(status, 500)
        }
    }),
    Test("Unpair is a DELETE of that one Chrome on the safe route, empty, signed for it", awaiting: {
        let (client, transport) = planque([(200, #"{"removed":"chr/1"}"#)])
        _ = try await client.safe(.unpairChrome("chr/1"), signedBy: { _ in "SIG" })
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["DELETE /v1/accounts/acme%2F1/chromes/chr%2F1"])
        try expectEqual(transport.sent[0].body, Data())
    }),
]

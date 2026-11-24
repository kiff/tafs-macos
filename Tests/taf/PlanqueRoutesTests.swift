import Foundation

/// A planque client that would sign and send anything it was asked, counting what it signs.
private func armed(_ transport: CannedTransport, signs: @escaping () -> Void) -> PlanqueClient {
    let planque = PlanqueClient()
    planque.tenant = "acme-1"
    planque.deviceID = "dev_9"
    planque.transport = transport
    planque.signer = { _ in signs(); return "SIG" }
    planque.bodyHash = { _ in PlanqueClient.emptyBodyHash }
    return planque
}

let planqueRoutesTests: [Test] = [
    Test("send signs one route at planque, the enrolment: never a grant's approve, confirm or key") {
        try expectEqual(PlanqueClient.routes, ["enrolment"])
        // And its safe routes, each signed per call, never armed: Chrome's list and unpairing one, both taking nothing.
        try expectEqual([PlanqueClient.Safe.chromes, .unpairChrome("c/1")].map { $0.method + " " + $0.path }, ["GET chromes", "DELETE chromes/c%2F1"])
        for route in PlanqueClient.routes {
            try expect(!route.hasPrefix("grants"), "\(route) is a grant's route")
            try expect(!route.contains("approve") && !route.contains("confirm") && !route.contains("key"), "\(route) approves, confirms or keys")
        }
    },
    Test("the enrolment is one signed request: POST to the account's enrolment, signed once", awaiting: {
        let transport = CannedTransport([(200, #"{"tenant":"acme-1","device":"fp","kept":true}"#)])
        var signs = 0
        let planque = armed(transport, signs: { signs += 1 })
        _ = try await planque.enrol(deviceKey: Data([1, 2, 3]), connectorKey: nil)
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["POST /v1/accounts/acme-1/enrolment"])
        try expectEqual(signs, 1)
    }),
    Test("ending a connection is one DELETE of the grant, no body, signed v1 once by the signer it's given, with this device", awaiting: {
        let transport = CannedTransport([(200, #"{"id":"g 1","status":"disconnected"}"#)])
        let planque = PlanqueClient()
        planque.tenant = "t/1"
        planque.deviceID = "dev_9"
        var signed: [String] = []
        try await planque.disconnect(grantID: "g 1", signedBy: { signed.append($0); return "SIG" }, over: transport)
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["DELETE /v1/accounts/t%2F1/grants/g%201"])
        let request = transport.sent[0]
        try expect(request.body.isEmpty, "no body")
        try expect(request.headers["Content-Type"] == nil, "no Content-Type")
        try expect(request.headers["Authorization"] == nil, "no session goes to planque")
        try expectEqual(signed.count, 1)
        let lines = signed[0].components(separatedBy: "\n")
        try expectEqual(Array(lines.prefix(6)), ["planque.request.v1", PlanqueClient.baseURL, "t/1", "DELETE", "/v1/accounts/t%2F1/grants/g%201", PlanqueClient.emptyBodyHash])
        let header = request.headers["Planque-Device-Signature"] ?? ""
        try expect(header.hasPrefix("t=\(lines[6]),v1=SIG,d=dev_9") && !header.contains("w="), "v1, with this device and no window: \(header)")
        // The client's own signer was never armed for it.
        try expect(planque.signer == nil, "the shared signer stays unarmed")
    }),
    Test("ending a connection signs and sends nothing without a tenant or a device, and says planque's refusal", awaiting: {
        let none = CannedTransport([])
        var signs = 0
        let bare = PlanqueClient()
        bare.deviceID = "dev_9"
        do { try await bare.disconnect(grantID: "g1", signedBy: { _ in signs += 1; return "SIG" }, over: none); throw Failure(description: "sent") }
        catch PlanqueClient.PlanqueError.notSigning {}
        let nobody = PlanqueClient()
        nobody.tenant = "acme-1"
        nobody.deviceLoader = { nil }
        do { try await nobody.disconnect(grantID: "g1", signedBy: { _ in signs += 1; return "SIG" }, over: none); throw Failure(description: "sent") }
        catch PlanqueClient.PlanqueError.noDevice {}
        try expectEqual(signs, 0)
        try expect(none.sent.isEmpty, "nothing sent")
        let refusing = CannedTransport([(404, #"{"error":"no such grant","words":"That connection is gone."}"#)])
        do { try await armed(refusing, signs: {}).disconnect(grantID: "g1", signedBy: { _ in "SIG" }, over: refusing); throw Failure(description: "taken") }
        catch PlanqueClient.PlanqueError.server(404, "no such grant", "That connection is gone.") {}
    }),
    Test("a path other than the enrolment is refused before anything is signed or sent", awaiting: {
        // `send` is private, so no caller outside the client can reach it; its list is the guard
        // for a later method added inside it. The only ways in are `enrol` and `disconnect`, as above.
        try expect(!PlanqueClient.routes.contains("grants/g1/approve") && !PlanqueClient.routes.contains("grants/g1/confirm"), "approve and confirm aren't routes")
    }),
]

/// Account › How tafs works says where this Mac's approvals are signed.
let howItWorksTests: [Test] = [
    Test("How tafs works says approvals are signed on the phone, but on the security key's route, in all 8 languages") {
        try expectEqual(ApprovalRoute.phoneOrPasskey.howItWorksKey, "sign_in.every_action_taf_takes_goes_view")
        try expectEqual(ApprovalRoute.touchID.howItWorksKey, "sign_in.every_action_taf_takes_goes_view")
        try expectEqual(ApprovalRoute.passkey.howItWorksKey, "sign_in.every_action_taf_takes_goes")
        // A Mac with its security key signs here since kiff/cloud#96; one without approves on the phone.
        try expectEqual(ApprovalRoute.of(.passkey, securityKey: true).howItWorksKey, "sign_in.every_action_taf_takes_goes")
        try expectEqual(ApprovalRoute.of(.passkey, securityKey: false).howItWorksKey, "sign_in.every_action_taf_takes_goes_view")
        let folder = URL(fileURLWithPath: ".shared/app/strings")
        for language in try Words.shipped(folder: folder) {
            let words = try Words(language: language, folder: folder)
            for key in ["sign_in.every_action_taf_takes_goes_view", "sign_in.every_action_taf_takes_goes"] {
                let line = words(key, ["device": words("device.mac")])
                try expect(line != key && !line.isEmpty && !line.contains("{"), "\(key) in \(language): \(line)")
            }
        }
        try expectEqual(try Words(language: "en", folder: folder)("sign_in.every_action_taf_takes_goes_view"),
                        "Every action a taf takes goes through KIFF, which checks its Card before anything reaches an app. Your approvals are signed on your phone.")
    },
]

import Foundation

/// Every Swift file under `Sources`, as text: what the app is built from.
private func sources() throws -> [(path: String, text: String)] {
    let root = URL(fileURLWithPath: "Sources")
    guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { throw Failure(description: "no Sources") }
    return try walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        .map { ($0.path, try String(contentsOf: $0, encoding: .utf8)) }
}

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
    Test("this Mac signs one route at planque, its enrolment: never a grant's approve or confirm") {
        try expectEqual(PlanqueClient.routes, ["enrolment"])
        // And its safe routes, each signed per call, never armed: Chrome's list and unpairing one, both taking nothing.
        try expectEqual([PlanqueClient.Safe.chromes, .unpairChrome("c/1")].map { $0.method + " " + $0.path }, ["GET chromes", "DELETE chromes/c%2F1"])
        for route in PlanqueClient.routes {
            try expect(!route.hasPrefix("grants"), "\(route) is a grant's route")
            try expect(!route.contains("approve") && !route.contains("confirm"), "\(route) approves or confirms")
        }
    },
    Test("the enrolment is the one signed request: POST to the account's enrolment, signed once", awaiting: {
        let transport = CannedTransport([(200, #"{"tenant":"acme-1","device":"fp","kept":true}"#)])
        var signs = 0
        let planque = armed(transport, signs: { signs += 1 })
        _ = try await planque.enrol(deviceKey: Data([1, 2, 3]), connectorKey: nil)
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["POST /v1/accounts/acme-1/enrolment"])
        try expectEqual(signs, 1)
    }),
    Test("no source names planque's approve or confirm routes, or any grant's route but the grants read") {
        let all = try sources()
        try expect(all.count > 50, "the app's sources: \(all.count)")
        for (path, text) in all {
            for banned in ["grants/", "/approve", "/confirm"] {
                try expect(!text.contains(banned), "\(path) names \(banned)")
            }
        }
        // The grants proof stays a read: GET, over the grants list, and nothing else.
        let client = try String(contentsOf: URL(fileURLWithPath: "Sources/Core/taf/PlanqueClient.swift"), encoding: .utf8)
        try expect(client.contains(#"method: "GET", uri: path"#), "the grants proof signs a GET")
        // One request to planque's account routes in the client: the enrolment's.
        let planqueSends = try NSRegularExpression(pattern: #"send\("[A-Z]+", "[^/]"#)
        try expectEqual(planqueSends.numberOfMatches(in: client, range: NSRange(client.startIndex..., in: client)), 1)
    },
    Test("the PlanqueClient is made in one place, and armed to sign only around the enrolment, then cleared") {
        let made = try sources().filter { $0.text.contains("PlanqueClient()") }.map { URL(fileURLWithPath: $0.path).lastPathComponent }
        try expectEqual(made, ["SignedInView.swift"])
        let arming = try sources().filter { $0.text.contains("planque.signer = ") }
        try expectEqual(arming.map { URL(fileURLWithPath: $0.path).lastPathComponent }, ["SignedInView.swift"])
        let text = arming[0].text
        try expectEqual(text.components(separatedBy: "planque.signer = account.signMessage").count - 1, 1)
        try expectEqual(text.components(separatedBy: "defer { planque.signer = nil }").count - 1, 1)
        // Armed, then cleared on every path, around the enrolment alone.
        guard let armedAt = text.range(of: "planque.signer = account.signMessage"),
              let enrolAt = text.range(of: "PlanqueEnrolment.enrol(planque: planque") else { throw Failure(description: "the enrolment step") }
        let between = String(text[armedAt.upperBound..<enrolAt.lowerBound])
        try expect(between.contains("defer { planque.signer = nil }"), "cleared on every path once the enrolment ends")
    },
    Test("a path other than the enrolment is refused before anything is signed or sent", awaiting: {
        // `send` is private, so no caller outside the client can reach it; its list is the guard
        // for a later method added inside it. The only way in today is `enrol`, as above.
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

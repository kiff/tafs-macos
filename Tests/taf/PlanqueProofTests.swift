import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "acme-1", subject: "u1", deviceID: nil)

let tafPlanqueTests: [Test] = [
    Test("what the device signs for planque is planque's seven lines, as the iPad's PlanqueClient.message") {
        let message = PlanqueClient.message(base: "https://planque.kiff.dev//", tenant: "acme-1", method: "GET", uri: "/v1/accounts/acme-1/grants",
                                            bodyHash: PlanqueClient.emptyBodyHash, signedAt: "2026-11-15T14:00:00.123Z")
        try expectEqual(message, """
        planque.request.v1
        https://planque.kiff.dev
        acme-1
        GET
        /v1/accounts/acme-1/grants
        e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        2026-11-15T14:00:00.123Z
        """)
    },
    Test("the grants proof is the time, the signature over that message, and this device, as the iPad's grantsReadProof", awaiting: {
        let planque = PlanqueClient()
        var loads = 0
        planque.deviceLoader = { loads += 1; return "dev_9" }
        planque.tenant = "acme-1"
        var signed: [String] = []
        let proof = try await planque.grantsReadProof(signedBy: { signed.append($0); return "SIG" })
        let parts = proof.split(separator: ",").map(String.init)
        try expectEqual(parts.count, 3)
        try expect(parts[0].hasPrefix("t=") && parts[0].hasSuffix("Z") && parts[0].contains("."), "a time with its milliseconds")
        try expectEqual(Array(parts[1...]), ["v1=SIG", "d=dev_9"])
        let at = String(parts[0].dropFirst(2))
        try expectEqual(signed, [PlanqueClient.message(base: PlanqueClient.baseURL, tenant: "acme-1", method: "GET", uri: "/v1/accounts/acme-1/grants",
                                                       bodyHash: PlanqueClient.emptyBodyHash, signedAt: at)])
        // The device is read once, then kept.
        _ = try await planque.grantsReadProof(signedBy: { _ in "SIG" })
        try expectEqual(loads, 1)
    }),
    Test("no account, or no device, is no proof, and nothing is signed", awaiting: {
        var signs = 0
        let noAccount = PlanqueClient()
        noAccount.deviceID = "dev_9"
        do { _ = try await noAccount.grantsReadProof(signedBy: { _ in signs += 1; return "" }); throw Failure(description: "signed") } catch PlanqueClient.PlanqueError.notSigning {}
        let noDevice = PlanqueClient()
        noDevice.tenant = "acme-1"
        noDevice.deviceLoader = { nil }
        do { _ = try await noDevice.grantsReadProof(signedBy: { _ in signs += 1; return "" }); throw Failure(description: "signed") } catch PlanqueClient.PlanqueError.noDevice {}
        try expectEqual(signs, 0)
    }),
    Test("this device is the one KIFF marks this_device, and only a dev_ one", awaiting: {
        let list = #"{"devices":[{"id":"dev_1"},{"id":"pk_2","this_device":true},{"id":"dev_3","this_device":true}]}"#
        let transport = CannedTransport([(200, list), (200, #"{"devices":[{"id":"pk_2","this_device":true}]}"#)])
        let account = AccountClient(transport: transport, session: session)
        let first = try await account.thisDeviceID()
        try expectEqual(first, "dev_3")
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "GET /v1/me/devices")
        let none = try await account.thisDeviceID()
        try expectEqual(none, nil)
    }),
    Test("a taf's Setup carries the proof as Planque-Device-Signature, and none without one", awaiting: {
        let setup = #"{"workflow":{"title":"Workflow"}}"#
        let transport = CannedTransport([(200, setup), (200, setup)])
        let cloud = CloudClient(transport: transport, session: session)
        _ = try await cloud.setup(of: "taf-1", proof: "t=x,v1=y,d=dev_9")
        _ = try await cloud.setup(of: "taf-1")
        try expectEqual(transport.sent.map(\.path), ["/v1/tafs/taf-1/setup", "/v1/tafs/taf-1/setup"])
        try expectEqual(transport.sent[0].headers["Planque-Device-Signature"], "t=x,v1=y,d=dev_9")
        try expectEqual(transport.sent[1].headers["Planque-Device-Signature"], nil)
    }),
    Test("a signing time is RFC 3339 with milliseconds, and never the same twice", {
        let now = Date(timeIntervalSince1970: 1_794_752_400.5)
        let a = SigningTime.next(now: now), b = SigningTime.next(now: now)
        try expect(a != b, "two times in one millisecond differ")
        try expect(a.hasSuffix("Z") && a.contains("."), "milliseconds, UTC: \(a)")
    }),
]

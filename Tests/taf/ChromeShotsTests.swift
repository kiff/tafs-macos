import Foundation

/// The picture a paired Chrome kept before a taf's step (`ChromeShots`), as the iPad's `ChromeShotView` and planque's
/// screenshot reads: listed by operation, each shown only when it checks out.
private let webp = Data("RIFF".utf8) + Data([0x1a, 0, 0, 0]) + Data("WEBPVP8L".utf8) + Data(repeating: 7, count: 20)

private func answer(step: String = "s1", bytes: Data = webp, sha: String? = nil, takenAt: String? = "2026-11-22T20:00:00Z",
                    image: String? = nil) -> Data {
    var fields: [String: String] = ["step": step, "sha256": sha ?? Encoding.hex(testSHA256(bytes)), "image": image ?? Encoding.base64URL(bytes)]
    if let takenAt { fields["taken_at"] = takenAt }
    return (try? JSONSerialization.data(withJSONObject: fields)) ?? Data()
}

let tafChromeShotsTests: [Test] = [
    Test("the list reads planque's pictures for an operation, oldest first; an entry with no step or time is left out") {
        let list = Data(#"{"shots":[{"step":"s1","taken_at":"2026-11-22T20:00:00Z","sha256":"ab"},{"step":" "},{"step":"s2","taken_at":"2026-11-22T20:01:00.5Z"},{"step":"s3","taken_at":"yesterday"}]}"#.utf8)
        try expectEqual(ChromeShots.readList(list)?.map(\.step), ["s1", "s2"])
        try expectEqual(ChromeShots.readList(Data(#"{"shots":[]}"#.utf8)), [])
        try expectEqual(ChromeShots.readList(Data("not json".utf8)), nil)
    },
    Test("a picture is shown only when it checks out: the step asked, base64url, WebP, at most 120 KB, planque's hash, a time") {
        func read(_ data: Data, _ step: String = "s1") -> ChromeShots.Shot? { ChromeShots.read(data, step: step, sha256: testSHA256) }
        try expectEqual(read(answer())?.image, webp)
        try expectEqual(read(answer(), "s2"), nil)
        try expectEqual(read(answer(sha: String(repeating: "0", count: 64))), nil)
        let png = Data([0x89, 0x50, 0x4E, 0x47]) + Data(repeating: 0, count: 20)
        try expectEqual(read(answer(bytes: png)), nil)
        let big = webp + Data(repeating: 0, count: ChromeShots.largest)
        try expectEqual(read(answer(bytes: big)), nil)
        try expectEqual(read(answer(takenAt: nil)), nil)
        try expectEqual(read(answer(takenAt: "yesterday")), nil)
        // Padded or standard base64 isn't base64url as planque writes it.
        try expectEqual(read(answer(image: webp.base64EncodedString() + "=")), nil)
        try expectEqual(read(answer(image: webp.base64EncodedString().replacingOccurrences(of: "-", with: "+") + "+/")), nil)
        try expectEqual(read(Data("not json".utf8)), nil)
    },
    Test("a step's read: a 404 is none kept, any other refusal or a picture that doesn't check out failed") {
        try expectEqual(ChromeShots.read(status: 404, Data(), step: "s1", sha256: testSHA256), .none)
        try expectEqual(ChromeShots.read(status: 503, answer(), step: "s1", sha256: testSHA256), .failed)
        try expectEqual(ChromeShots.read(status: 200, answer(step: "s2"), step: "s1", sha256: testSHA256), .failed)
        if case .shown(let shot) = ChromeShots.read(status: 200, answer(), step: "s1", sha256: testSHA256) {
            try expectEqual(shot.step, "s1")
        } else {
            throw Failure(description: "a checked picture isn't shown")
        }
    },
    Test("both reads are planque's safe GETs, signed per request, the operation escaped inside the signed query", awaiting: {
        try expectEqual(PlanqueClient.Safe.chromeShots(operation: "prp_1&x=2#y").method, "GET")
        try expectEqual(PlanqueClient.Safe.chromeShots(operation: "prp_1&x=2#y").path, "chromes/screenshots?op=prp_1%26x%3D2%23y")
        try expectEqual(PlanqueClient.Safe.chromeShot(step: "s/1").path, "chromes/screenshots/s%2F1")
        try expectEqual(PlanqueClient.Safe.chromeShot(step: "s/1").method, "GET")
        // Sent as signed: the device's signature, no session token, the query in the signed path.
        let transport = CannedTransport([(200, #"{"shots":[{"step":"s1","taken_at":"2026-11-22T20:00:00Z"}]}"#), (404, "{}")])
        let client = PlanqueClient()
        client.tenant = "t1"
        client.transport = transport
        client.deviceID = "dev_1"
        var signed: [String] = []
        let shots = try await client.chromeShots(operation: "prp_1", signedBy: { signed.append($0); return "SIG" })
        try expectEqual(shots.map(\.step), ["s1"])
        try expectEqual(transport.sent.first?.path, "/v1/accounts/t1/chromes/screenshots?op=prp_1")
        try expect(transport.sent.first?.headers["Authorization"] == nil, "no session token goes to planque")
        try expect(transport.sent.first?.headers["Planque-Device-Signature"]?.contains("d=dev_1") == true, "signed by this device")
        try expect(signed.first?.contains("/v1/accounts/t1/chromes/screenshots?op=prp_1") == true, "the query is part of what's signed")
        // None kept, or planque keeps none: an empty list.
        let none = try await client.chromeShots(operation: "prp_2", signedBy: { _ in "SIG" })
        try expectEqual(none, [])
    }),
]

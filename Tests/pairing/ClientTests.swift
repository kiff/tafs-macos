import Foundation

/// Answers each request with the next canned answer, and keeps what was sent.
final class CannedTransport: Transport, @unchecked Sendable {
    var answers: [(Int, String)]
    private(set) var sent: [HTTPRequest] = []
    init(_ answers: [(Int, String)]) { self.answers = answers }

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        sent.append(request)
        let (status, body) = answers.isEmpty ? (500, "") : answers.removeFirst()
        return (status, Data(body.utf8))
    }
}

private let session = #"{"access_token":"tok","token_type":"Bearer","expires_in":7776000,"tenant":"t1","subject":"u1"}"#
private let start = #"{"device_code":"dc","user_code":"ABCD-EFGH","verification_uri":"https://app.kiff.dev/device","verification_uri_complete":"https://app.kiff.dev/device?code=ABCD-EFGH","expires_in":600,"interval":5}"#

private func fields(_ request: HTTPRequest) throws -> [String: String] {
    try JSONDecoder().decode([String: String].self, from: request.body)
}

let pairingClientTests: [Test] = [
    Test("a Mac with no approval key starts a sign-in as passkey-only, and never sends an approval key", awaiting: {
        let transport = CannedTransport([(200, start)])
        let answer = try await KIFFClient(transport: transport).startSignIn(
            publicKey: Data([1, 2, 3]), keyStore: "software", name: "A Mac", approval: .passkey)
        try expectEqual(answer.userCode, "ABCD-EFGH")
        try expectEqual(answer.interval, 5)
        let sent = transport.sent[0]
        try expectEqual(sent.method + " " + sent.path, "POST /v1/auth/device/start")
        try expectEqual(sent.headers["Authorization"], nil)
        try expectEqual(try fields(sent), ["public_key": "AQID", "key_store": "software", "device_name": "A Mac",
                                           "platform": "macos", "kind": "other", "approval": "passkey"])
    }),
    Test("a Mac with an approval key sends it, and no passkey flag", awaiting: {
        let transport = CannedTransport([(200, start)])
        _ = try await KIFFClient(transport: transport).startSignIn(
            publicKey: Data([1]), keyStore: "enclave", name: "A Mac", approval: .key(Data([9, 9])))
        let sent = try fields(transport.sent[0])
        try expectEqual(sent["approval_public_key"], "CQk=")
        try expectEqual(sent["approval"], nil)
    }),
    Test("the token's answers are read as the contract names them", awaiting: {
        let cases: [(Int, String, KIFFError)] = [
            (400, #"{"error":"authorization_pending"}"#, .authorizationPending),
            (400, #"{"error":"slow_down"}"#, .slowDown),
            (400, #"{"error":"expired_token"}"#, .expired),
            (403, #"{"error":"invalid_proof"}"#, .invalidProof),
            (403, #"{"error":"phone_session_forbidden"}"#, .refused(status: 403, code: "phone_session_forbidden")),
            (502, "<html>", .refused(status: 502, code: "")),
            (200, #"{"access_token":"tok"}"#, .unreadable),
        ]
        for (status, body, want) in cases {
            do {
                _ = try await KIFFClient(transport: CannedTransport([(status, body)])).token(deviceCode: "dc")
                throw Failure(description: "\(status) \(body) was taken as a session")
            } catch let error as KIFFError {
                try expectEqual(error, want)
            }
        }
        let got = try await KIFFClient(transport: CannedTransport([(200, session)])).token(deviceCode: "dc")
        try expectEqual(got, Session(accessToken: "tok", expiresIn: 7_776_000, tenant: "t1", subject: "u1", deviceID: nil))
    }),
    Test("a claim sends the nonce, the key and the proof, with no session", awaiting: {
        let paired = #"{"access_token":"tok","token_type":"Bearer","expires_in":1,"tenant":"t1","subject":"u1","device_id":"dev_1"}"#
        let transport = CannedTransport([(200, paired)])
        let got = try await KIFFClient(transport: transport).claimPairing(nonce: "n", publicKey: "PUB", proof: "PROOF")
        try expectEqual(got.deviceID, "dev_1")
        try expectEqual(transport.sent[0].path, "/v1/pair/claim")
        try expectEqual(transport.sent[0].headers["Authorization"], nil)
        try expectEqual(try fields(transport.sent[0]), ["nonce": "n", "pub": "PUB", "proof": "PROOF"])
    }),
    Test("waiting asks again while pending, slows down for good when told to, and stops on the answer", awaiting: {
        var slept: [TimeInterval] = []
        var answers: [Result<String, KIFFError>] = [.failure(.authorizationPending), .failure(.slowDown), .failure(.authorizationPending), .success("in")]
        let got: String = try await Waiting.until(interval: 5, expiresIn: 600, sleep: { slept.append($0) }, ask: { try answers.removeFirst().get() })
        try expectEqual(got, "in")
        try expectEqual(slept, [5, 5, 10, 10])
    }),
    Test("waiting never asks before the first interval, and ends as expired at the code's time", awaiting: {
        var asked = 0
        do {
            let _: String = try await Waiting.until(interval: 5, expiresIn: 12, sleep: { _ in }, ask: { asked += 1; throw KIFFError.authorizationPending })
            throw Failure(description: "it answered")
        } catch let error as KIFFError {
            try expectEqual(error, .expired)
            try expectEqual(asked, 2)
        }
    }),
    Test("waiting ends on any other refusal, and is capped at ten minutes", awaiting: {
        var asked = 0
        do {
            let _: String = try await Waiting.until(interval: 5, expiresIn: 600, sleep: { _ in }, ask: { asked += 1; throw KIFFError.invalidProof })
            throw Failure(description: "it answered")
        } catch let error as KIFFError {
            try expectEqual(error, .invalidProof)
            try expectEqual(asked, 1)
        }
        var total: TimeInterval = 0
        _ = try? await Waiting.until(interval: 60, expiresIn: 86_400, sleep: { total += $0 }, ask: { () -> String in throw KIFFError.authorizationPending })
        try expectEqual(total, Waiting.longest)
    }),
]

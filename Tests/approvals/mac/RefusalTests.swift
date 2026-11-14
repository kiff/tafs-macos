import Foundation

let approvalsRefusalTests: [Test] = [
    Test("a signed-in Mac's refusal verifies with its device key over KIFF's answer message", awaiting: {
        let key = try DeviceKey.load(from: MemoryStore(), enclave: false)
        let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
        let transport = CannedTransport([(200, #"{"exceptions":[{"id":"exc_1","subject":"a","action":"b","created_at":"2026-11-14T18:00:00Z","accounting_version":7}]}"#), (200, "{}")])
        let account = AccountClient(session: session, key: key, language: "en", transport: transport)
        let call = try await account.heldCalls()[0]
        try await account.refuse(call, at: Date(timeIntervalSince1970: 1_794_679_200))
        struct Body: Decodable { struct Signature: Decodable { let signed_at: String; let value: String }; let signature: Signature }
        let body = try JSONDecoder().decode(Body.self, from: transport.sent[1].body)
        let message = KIFFMessage.answer(tenant: "t1", callID: "exc_1", answer: .reject, nextStep: nil, accountingVersion: 7, signedAt: body.signature.signed_at)
        try expect(Signing.verifies(body.signature.value, over: message, publicKeyDER: key.publicKeyDER), "verifies")
        let approve = KIFFMessage.answer(tenant: "t1", callID: "exc_1", answer: .approveOnce, nextStep: nil, accountingVersion: 7, signedAt: body.signature.signed_at)
        try expect(!Signing.verifies(body.signature.value, over: approve, publicKeyDER: key.publicKeyDER), "it is not an approval's signature")
    }),
]

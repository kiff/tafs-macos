import CryptoKit
import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t_01", subject: "u1", deviceID: "dev_9")

let planqueEnrolMacTests: [Test] = [
    Test("the enrolment and the mint are signed by this device's key, over exactly what is sent, and checked as planque and KIFF check them", awaiting: {
        let key = SoftwareKey(key: .init())
        let planqueSent = CannedTransport([(409, #"{"code":"needs_key"}"#), (201, #"{"tenant":"t_01","device":"ab12"}"#)])
        let kiffSent = CannedTransport([(201, #"{"id":"key_c","plaintext":"kiff_live_connector","roles":["connector"]}"#)])
        let account = AccountClient(session: session, key: key, language: "en", transport: kiffSent)
        let planque = PlanqueClient(baseURL: "https://planque.test")
        planque.tenant = "t_01"
        planque.deviceID = "dev_9"
        planque.transport = planqueSent
        planque.bodyHash = Signing.sha256Hex
        planque.signer = { try key.sign(Data($0.utf8)).base64EncodedString() }
        let stop = await PlanqueEnrolment.enrol(planque: planque, account: account, deviceKey: key.publicKeyDER)
        try expectEqual(stop, nil)
        for sent in planqueSent.sent {
            let fields = Dictionary(uniqueKeysWithValues: (sent.headers["Planque-Device-Signature"] ?? "").split(separator: ",").compactMap { part -> (String, String)? in
                let pair = part.split(separator: "=", maxSplits: 1)
                return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
            })
            try expectEqual(fields["d"], "dev_9")
            let message = PlanqueClient.message(base: "https://planque.test", tenant: "t_01", method: "POST", uri: sent.path,
                                                bodyHash: Signing.sha256Hex(sent.body), signedAt: fields["t"] ?? "")
            try expect(Signing.verifies(fields["v1"] ?? "", over: message, publicKeyDER: key.publicKeyDER), "planque's signature verifies")
        }
        // The mint is a setup call, signed by the same key, as KIFF reads `kiff.request.v1`.
        let mint = kiffSent.sent[0]
        let header = mint.headers["KIFF-Device-Signature"] ?? ""
        let parts = Dictionary(uniqueKeysWithValues: header.split(separator: ",").compactMap { part -> (String, String)? in
            let pair = part.split(separator: "=", maxSplits: 1)
            return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
        })
        let request = KIFFMessage.request(tenant: "t_01", method: "POST", path: "/v1/keys", bodyHash: Signing.sha256Hex(mint.body), signedAt: parts["t"] ?? "")
        try expect(Signing.verifies(parts["v1"] ?? "", over: request, publicKeyDER: key.publicKeyDER), "the mint's signature verifies")
    }),
]

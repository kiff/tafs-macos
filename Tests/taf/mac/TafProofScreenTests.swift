import CryptoKit
import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "acme-1", subject: "u1", deviceID: nil)

/// A contract fixture's answer, as tafs cloud sends it.
private func contract(_ file: String) throws -> String {
    let root = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: ".shared/contracts/\(file)"))) as? [String: Any]
    guard let answer = root?["answer"] else { throw Failure(description: "\(file) has no answer") }
    return String(decoding: try JSONSerialization.data(withJSONObject: answer), as: UTF8.self)
}

let tafProofTests: [Test] = [
    Test("a read's body hash is the SHA-256 of nothing, as planque checks it") {
        try expectEqual(Signing.sha256Hex(Data()), PlanqueClient.emptyBodyHash)
    },
    Test("the device key's proof verifies against planque's message, with no prompt", awaiting: {
        let key = SoftwareKey(key: .init())
        let planque = PlanqueClient()
        planque.tenant = "acme-1"
        planque.deviceID = "dev_9"
        let proof = try await planque.grantsReadProof(signedBy: { try key.sign(Data($0.utf8)).base64EncodedString() })
        let parts = proof.split(separator: ",").map(String.init)
        let at = String(parts[0].dropFirst(2)), signature = String(parts[1].dropFirst(3))
        let message = PlanqueClient.message(base: PlanqueClient.baseURL, tenant: "acme-1", method: "GET", uri: "/v1/accounts/acme-1/grants",
                                            bodyHash: PlanqueClient.emptyBodyHash, signedAt: at)
        try expect(Signing.verifies(signature, over: message, publicKeyDER: key.publicKeyDER), "the device key's signature over the message")
    }),
    Test("a taf's Setup sends this device's proof and lists the connected apps tafs cloud read with it", awaiting: { @MainActor in
        let transport = CannedTransport([(200, try contract("taf-setup-connected.json")), (200, try contract("taf-setup.json"))])
        let model = TafPagesModel(cloud: CloudClient(transport: transport, session: session), taf: "taf-1", proof: { "t=x,v1=y,d=dev_9" })
        await model.loadSetup()
        try expectEqual(transport.sent[0].headers["Planque-Device-Signature"], "t=x,v1=y,d=dev_9")
        guard case .loaded(let setup) = model.setup else { throw Failure(description: "not read") }
        try expect(!setup.connections.isEmpty, "the connected apps")
        // No proof (no device, no key): the read goes without it, as the iPad's `try?`.
        let without = TafPagesModel(cloud: CloudClient(transport: transport, session: session), taf: "taf-1")
        await without.loadSetup()
        try expectEqual(transport.sent[1].headers["Planque-Device-Signature"], nil)
    }),
]

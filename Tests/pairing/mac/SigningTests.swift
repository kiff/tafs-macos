import CryptoKit
import Foundation

private let examplePublicKey = Data(base64Encoded: Example.publicKey)!

let pairingSigningTests: [Test] = [
    Test("the worked example's hashes are KIFF's") {
        try expectEqual(Signing.sha256Hex(Data(Example.body.utf8)), Example.bodyHash)
        try expectEqual(Signing.sha256Hex(Data(Example.message.utf8)), Example.messageHash)
        try expectEqual(Signing.sha256Hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    },
    Test("the worked example's signature verifies, and not over another message") {
        try expect(Signing.verifies(Example.signature, over: Example.message, publicKeyDER: examplePublicKey), "KIFF's signature")
        try expect(!Signing.verifies(Example.signature, over: Example.message + "\n", publicKeyDER: examplePublicKey), "a trailing line is refused")
    },
    Test("a request's header is signed by the key over the exact message, as DER") {
        let key = try DeviceKey.load(from: MemoryStore(), enclave: false)
        let at = Date(timeIntervalSince1970: 1_794_679_200)
        let header = try Signing.header(key: key, tenant: Example.tenant, method: "POST", path: "/v1/me/window",
                                        body: Data(Example.body.utf8), at: at)
        try expect(header.hasPrefix("t=\(Example.signedAt),v1="), header)
        let signature = String(header.dropFirst("t=\(Example.signedAt),v1=".count))
        try expect(Signing.verifies(signature, over: Example.message, publicKeyDER: key.publicKeyDER), "verifies")
        try expectEqual(Data(base64Encoded: signature)?.first, 0x30)
        try expect(!Signing.verifies(signature, over: Example.message, publicKeyDER: examplePublicKey), "another key refuses it")
    },
    Test("inside a window the header carries the window and signs the v2 message") {
        let key = try DeviceKey.load(from: MemoryStore(), enclave: false)
        let header = try Signing.header(key: key, tenant: "t", method: "POST", path: "/p", body: Data(),
                                        at: Date(timeIntervalSince1970: 0), window: "win_abc")
        let parts = header.split(separator: ",").map(String.init)
        try expectEqual(parts.count, 3)
        try expectEqual(parts[2], "w=win_abc")
        let message = KIFFMessage.request(tenant: "t", method: "POST", path: "/p", bodyHash: Signing.sha256Hex(Data()),
                                          signedAt: "1970-01-01T00:00:00Z", window: "win_abc")
        try expect(Signing.verifies(String(parts[1].dropFirst(3)), over: message, publicKeyDER: key.publicKeyDER), "v2 verifies")
    },
    Test("a claim's proof is the device key's, over the nonce and its own hash") {
        let key = try DeviceKey.load(from: MemoryStore(), enclave: false)
        let proof = try Signing.claimProof(key: key, nonce: "nonce-1")
        let message = KIFFMessage.pairClaim(nonce: "nonce-1", keyHash: Signing.sha256Hex(key.publicKeyDER))
        try expect(Signing.verifies(proof, over: message, publicKeyDER: key.publicKeyDER), "verifies")
        let other = KIFFMessage.pairClaim(nonce: "nonce-2", keyHash: Signing.sha256Hex(key.publicKeyDER))
        try expect(!Signing.verifies(proof, over: other, publicKeyDER: key.publicKeyDER), "another nonce is refused")
    },
    Test("the device key is made once and is the same at the next launch") {
        let store = MemoryStore()
        let first = try DeviceKey.load(from: store, enclave: false)
        let second = try DeviceKey.load(from: store, enclave: false)
        try expectEqual(first.publicKeyDER, second.publicKeyDER)
        try expectEqual(first.keyStore, "software")
        try expect(try DeviceKey.load(from: MemoryStore(), enclave: false).publicKeyDER != first.publicKeyDER, "another Mac's differs")
        // SPKI DER for P-256 is 91 bytes, within KIFF's 512.
        try expectEqual(first.publicKeyDER.count, 91)
    },
    Test("the check code is 6 base32 characters of both keys' hash") {
        let device = Data([1, 2, 3]), approval = Data([4, 5])
        let code = Signing.checkCode(deviceKey: device, approvalKey: approval)
        try expectEqual(code, String(Encoding.base32(Data(SHA256.hash(data: Data([1, 2, 3, 4, 5])))).prefix(6)))
        try expectEqual(code.count, 6)
        try expect(Signing.checkCode(deviceKey: device, approvalKey: nil) != code, "the device key alone differs")
    },
    Test("the check code matches the vector every tafs app shares") {
        // The P-256 keys of private keys 1 and 2, as KIFF's own test has them.
        func bytes(_ hex: String) -> Data {
            var out = Data(); var rest = Substring(hex)
            while !rest.isEmpty { out.append(UInt8(rest.prefix(2), radix: 16)!); rest = rest.dropFirst(2) }
            return out
        }
        let device = bytes("3059301306072a8648ce3d020106082a8648ce3d030107034200046b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5")
        let approval = bytes("3059301306072a8648ce3d020106082a8648ce3d030107034200047cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc4766997807775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1")
        try expectEqual(Signing.checkCode(deviceKey: device, approvalKey: approval), "H6SJNU")
        try expectEqual(Signing.checkCode(deviceKey: device, approvalKey: nil), "LTJFF6")
    },
    Test("a nonce is 32 random bytes in base64url") {
        let nonce = Signing.nonce()
        try expectEqual(Encoding.fromBase64URL(nonce)?.count, 32)
        try expect(Signing.nonce() != nonce, "random")
    },
    Test("the Keychain keeps a secret for this Mac, and forgets it when deleted") {
        let store = KeychainStore(service: "bot.tafs.macos.tests")
        let account = "test-\(UUID().uuidString)"
        defer { store.delete(account) }
        try expectEqual(store.load(account), nil)
        try store.save(Data([7, 7, 7]), for: account)
        try expectEqual(store.load(account), Data([7, 7, 7]))
        try store.save(Data([8]), for: account)
        try expectEqual(store.load(account), Data([8]))
        store.delete(account)
        try expectEqual(store.load(account), nil)
    },
]

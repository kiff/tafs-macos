import Foundation

/// The worked example of KIFF's `docs/desktop-client.md`, §2.4.
enum Example {
    static let tenant = "01exampletenant0000000000"
    static let signedAt = "2026-11-14T18:00:00Z"
    static let body = #"{"message":"kiff.window.v1","expires":"2026-11-14T18:05:00Z","nonce":"n0nce-example-0123456789"}"#
    static let bodyHash = "88c1f44661cc6ee2767971ef3fba6a8d71569987695534fbf2cb26ad434a3f72"
    static let message = """
        kiff.request.v1
        01exampletenant0000000000
        POST
        /v1/me/window
        88c1f44661cc6ee2767971ef3fba6a8d71569987695534fbf2cb26ad434a3f72
        2026-11-14T18:00:00Z
        """
    static let messageHash = "6190890c9dae8c613e2930d15dde98e98416dfd7074083219bdb017e5e6b74be"
    static let publicKey = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEuq6uAMg3330eLgKNwjg8RTxXLfC164Fzksg+3gI1gJsyV4iDPzJLgLSiMHvLSfKZg1w8QqHS5+XNYdilwVT9Yg=="
    static let signature = "MEUCIBHu5hb8DkEcTgrMlRGZAqi4CSYe4Pb2UyeFztiUNs9YAiEAgzTPpXwDIEthTaifyK8u12QGLKNBT94E3kSf7CQkyaw="
}

let pairingMessageTests: [Test] = [
    Test("a request's message is KIFF's worked example, with no trailing line") {
        let message = KIFFMessage.request(tenant: Example.tenant, method: "POST", path: "/v1/me/window",
                                          bodyHash: Example.bodyHash, signedAt: Example.signedAt)
        try expectEqual(message, Example.message)
        try expect(!message.hasSuffix("\n"), "no trailing line feed")
    },
    Test("inside a window the message is v2, with the window's id last") {
        let message = KIFFMessage.request(tenant: "t", method: "POST", path: "/p?a=1", bodyHash: "h", signedAt: "s", window: "win_abc")
        try expectEqual(message, "kiff.request.v2\nt\nPOST\n/p?a=1\nh\ns\nwin_abc")
    },
    Test("the header names the version, and the window inside one") {
        try expectEqual(KIFFMessage.header(signedAt: "T", signature: "SIG"), "t=T,v1=SIG")
        try expectEqual(KIFFMessage.header(signedAt: "T", signature: "SIG", window: "win_abc"), "t=T,v2=SIG,w=win_abc")
    },
    Test("a claim's message is the nonce and the key's hash") {
        try expectEqual(KIFFMessage.pairClaim(nonce: "n", keyHash: "ab12"), "kiff.pair.claim.v1\nn\nab12")
    },
    Test("a time is RFC 3339 in UTC, to the second") {
        try expectEqual(KIFFMessage.time(Date(timeIntervalSince1970: 1_794_679_200.7)), "2026-11-14T18:00:00Z")
    },
    Test("base32 is RFC 4648's, without padding") {
        let vectors = ["": "", "f": "MY", "fo": "MZXQ", "foo": "MZXW6", "foob": "MZXW6YQ", "fooba": "MZXW6YTB", "foobar": "MZXW6YTBOI"]
        for (plain, encoded) in vectors { try expectEqual(Encoding.base32(Data(plain.utf8)), encoded) }
    },
    Test("base64url has no padding and reads back") {
        let bytes = Data([0xFB, 0xFF, 0xFE, 0x01])
        try expectEqual(Encoding.base64URL(bytes), "-__-AQ")
        try expectEqual(Encoding.fromBase64URL("-__-AQ"), bytes)
    },
    Test("a fingerprint is the hash's first 8 bytes in four groups") {
        try expectEqual(Encoding.fingerprint(hashHex: "3f2a91c07b1e0d44aabbccdd"), "3f2a 91c0 7b1e 0d44")
    },
    Test("the QR code's text has the contract's fields, and no approval key for a passkey Mac") {
        let payload = PairingPayload(pub: "PUB", approvalPub: nil, name: "A Mac", kind: .passkey, nonce: "N", exp: "2026-11-14T18:05:00Z")
        try expectEqual(try payload.text(),
                        #"{"exp":"2026-11-14T18:05:00Z","kind":"passkey","name":"A Mac","nonce":"N","platform":"macos","pub":"PUB","v":"kiff.pair.v1"}"#)
        let enclave = PairingPayload(pub: "PUB", approvalPub: "APPROVAL", name: "A Mac", kind: .enclave, nonce: "N", exp: "E")
        try expect(try enclave.text().contains(#""approval_pub":"APPROVAL""#), "approval_pub")
        try expectEqual(try JSONDecoder().decode(PairingPayload.self, from: Data(try enclave.text().utf8)), enclave)
    },
]

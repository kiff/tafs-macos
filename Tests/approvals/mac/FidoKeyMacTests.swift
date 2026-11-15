import CFido
import Foundation

/// The libfido2 bridge, built from pinned source (scripts/fido.sh) and linked into the app: what
/// it asks of a key, read back from libfido2's own structures. No key is plugged into the CI's
/// Macs, so nothing here asks one; on a Mac with a key plugged in, the test that needs none says
/// so and asks nothing.

private func hash(_ byte: UInt8) -> Data { Data(repeating: byte, count: 32) }

private func bytes(_ pointer: UnsafePointer<UInt8>?, _ count: Int) -> Data {
    guard let pointer else { return Data() }
    return Data(bytes: pointer, count: count)
}

private func pin(_ text: String) throws -> SecurityKeyPIN {
    var typed = Array(text.utf8)
    return try SecurityKeyPIN(utf8: &typed)
}

let approvalsFidoMacTests: [Test] = [
    Test("an assertion asks libfido2 for kiff.dev with exactly the hash given") {
        let ask = try SecurityKeyAssertionAsk(clientDataHash: hash(9), credentialID: Data("this-mac".utf8))
        let assert = try FidoKey.prepared(ask)
        defer { FidoKey.free(assert: assert) }
        try expectEqual(fido_assert_rp_id(assert).map { String(cString: $0) }, "kiff.dev")
        try expectEqual(bytes(fido_assert_clientdata_hash_ptr(assert), fido_assert_clientdata_hash_len(assert)), hash(9))
        try expectEqual(fido_assert_count(assert), 0)
    },
    Test("the options reach libfido2 as asked: uv left out, presence true, not discoverable") {
        try expect(FidoKey.opt(.omit) == FIDO_OPT_OMIT, "omit")
        try expect(FidoKey.opt(.no) == FIDO_OPT_FALSE, "false")
        try expect(FidoKey.opt(.yes) == FIDO_OPT_TRUE, "true")
    },
    Test("a new credential asks libfido2 for ES256 on kiff.dev (KIFF), for the user given") {
        let ask = try SecurityKeyCredentialAsk(clientDataHash: hash(4), userID: Data("sub-1".utf8), userName: "rae@example.com")
        let cred = try FidoKey.prepared(ask)
        defer { FidoKey.free(cred: cred) }
        try expectEqual(fido_cred_type(cred), -7)
        try expectEqual(fido_cred_rp_id(cred).map { String(cString: $0) }, "kiff.dev")
        try expectEqual(fido_cred_rp_name(cred).map { String(cString: $0) }, "KIFF")
        try expectEqual(bytes(fido_cred_user_id_ptr(cred), fido_cred_user_id_len(cred)), Data("sub-1".utf8))
        try expectEqual(fido_cred_user_name(cred).map { String(cString: $0) }, "rae@example.com")
        try expectEqual(bytes(fido_cred_clientdata_hash_ptr(cred), fido_cred_clientdata_hash_len(cred)), hash(4))
    },
    Test("without a PIN the key isn't asked, and an ask that doesn't read never reaches it", awaiting: {
        do {
            _ = try await FidoKey().getAssertion(clientDataHash: hash(1), credentialID: Data([1]), pin: nil)
            throw Failure(description: "asked without a PIN")
        } catch let failure as SecurityKeyFailure {
            try expectEqual(failure, .pinMissing)
        }
        let given = try pin("1234")
        do {
            _ = try await FidoKey().getAssertion(clientDataHash: Data([1]), credentialID: Data([1]), pin: given)
            throw Failure(description: "asked with a 1-byte hash")
        } catch let refusal as PasskeyRefusal {
            try expectEqual(refusal, .unreadable)
        }
        try expect(!given.isHeld, "the PIN is cleared though nothing was asked")
    }),
    Test("with no key plugged in, the approval says so, and the PIN is cleared", awaiting: {
        guard FidoKey.plugged() == 0 else {
            print("      a key is plugged in: not asked, so its PIN tries aren't spent")
            return
        }
        let given = try pin("1234")
        do {
            _ = try await FidoKey().getAssertion(clientDataHash: hash(1), credentialID: Data([1]), pin: given)
            throw Failure(description: "answered with no key")
        } catch let failure as SecurityKeyFailure {
            try expectEqual(failure, .noKey)
        }
        try expect(!given.isHeld, "the PIN is cleared")
        do {
            _ = try await FidoKey().triesLeft()
            throw Failure(description: "tries read with no key")
        } catch let failure as SecurityKeyFailure {
            try expectEqual(failure, .noKey)
        }
    }),
]

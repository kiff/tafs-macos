import CFido
import Foundation

/// This Mac's USB security key, over libfido2: CTAP2 over USB HID, built from pinned source by
/// `scripts/fido.sh` (docs/building.md). It asks the one key plugged in for exactly a
/// `SecurityKeyAssertionAsk` or a `SecurityKeyCredentialAsk`, with the PIN, and returns the key's
/// raw answer. Core checks that answer whatever libfido2 says (`PasskeyApprover`,
/// `PasskeyRegistration`). Only `fido_dev_make_cred` and `fido_dev_get_assert` are asked of the
/// key, and its retry count read: it's never reset, and its PIN is never set or changed here.
final class FidoKey: PasskeyAuthenticator {
    private static let started: Void = fido_init(0)
    private let queue = DispatchQueue(label: "tafs.security-key")

    init() { _ = Self.started }

    /// One assertion, over the `clientDataJSON` hash this app built, with this Mac's credential.
    func getAssertion(clientDataHash: Data, credentialID: Data, pin: SecurityKeyPIN?) async throws -> PasskeyAssertion {
        defer { pin?.release() }
        let ask = try SecurityKeyAssertionAsk(clientDataHash: clientDataHash, credentialID: credentialID)
        guard let pin, pin.isHeld else { throw SecurityKeyFailure.pinMissing }
        return try await run { device in
            let assert = try Self.prepared(ask)
            defer { Self.free(assert: assert) }
            let code = try pin.use { fido_dev_get_assert(device, assert, $0) }
            try Self.check(code, device)
            guard fido_assert_count(assert) == 1 else { throw PasskeyRefusal.unreadable }
            // The raw authenticator data (libfido2's other getter gives it wrapped in CBOR).
            let used = Self.bytes(fido_assert_id_ptr(assert, 0), fido_assert_id_len(assert, 0))
            return PasskeyAssertion(
                authenticatorData: Self.bytes(fido_assert_authdata_raw_ptr(assert, 0), fido_assert_authdata_raw_len(assert, 0)),
                signatureDER: Self.bytes(fido_assert_sig_ptr(assert, 0), fido_assert_sig_len(assert, 0)),
                credentialID: used.isEmpty ? nil : used)
        }
    }

    /// One new credential for kiff.dev, ES256, the person verified. The attestation object is
    /// written from libfido2's three parts (`AttestationObject`).
    func makeCredential(clientDataHash: Data, userID: Data, userName: String, pin: SecurityKeyPIN?) async throws -> PasskeyMade {
        defer { pin?.release() }
        let ask = try SecurityKeyCredentialAsk(clientDataHash: clientDataHash, userID: userID, userName: userName)
        guard let pin, pin.isHeld else { throw SecurityKeyFailure.pinMissing }
        return try await run { device in
            let cred = try Self.prepared(ask)
            defer { Self.free(cred: cred) }
            let code = try pin.use { fido_dev_make_cred(device, cred, $0) }
            try Self.check(code, device)
            let authData = Self.bytes(fido_cred_authdata_raw_ptr(cred), fido_cred_authdata_raw_len(cred))
            let statement = Self.bytes(fido_cred_attstmt_ptr(cred), fido_cred_attstmt_len(cred))
            guard let format = fido_cred_fmt(cred).map({ String(cString: $0) }), !authData.isEmpty, !statement.isEmpty else {
                throw PasskeyRefusal.unreadable
            }
            return PasskeyMade(authenticatorData: authData,
                               attestationObject: AttestationObject.make(format: format, statement: statement, authenticatorData: authData))
        }
    }

    /// The PIN tries the key has left, for the PIN sheet; a key with none left is blocked.
    func triesLeft() async throws -> Int {
        try await run { device in
            var left: Int32 = 0
            if let failure = SecurityKeyFailure.of(fido_dev_get_retry_count(device, &left)) { throw failure }
            guard left > 0 else { throw SecurityKeyFailure.pinBlocked }
            return Int(left)
        }
    }

    /// How many FIDO keys are plugged in, without opening any: the PIN sheet says to plug one in,
    /// or to leave only one.
    static func plugged() -> Int {
        _ = started
        let most = 8
        guard let list = fido_dev_info_new(most) else { return 0 }
        defer {
            var pointer: OpaquePointer? = list
            fido_dev_info_free(&pointer, most)
        }
        var found = 0
        return fido_dev_info_manifest(list, most, &found) == FidoCode.ok ? found : 0
    }

    // MARK: What is asked

    /// The assertion libfido2 sends: kiff.dev, the hash, the one credential allowed, presence and
    /// verification required. The caller frees it (`free(assert:)`).
    static func prepared(_ ask: SecurityKeyAssertionAsk) throws -> OpaquePointer {
        guard let assert = fido_assert_new() else { throw SecurityKeyFailure.failed(code: FidoCode.internal) }
        let codes = [
            fido_assert_set_rp(assert, Passkeys.rpID),
            ask.clientDataHash.withUnsafeBytes { fido_assert_set_clientdata_hash(assert, $0.bindMemory(to: UInt8.self).baseAddress, $0.count) },
            ask.credentialID.withUnsafeBytes { fido_assert_allow_cred(assert, $0.bindMemory(to: UInt8.self).baseAddress, $0.count) },
            fido_assert_set_up(assert, FIDO_OPT_TRUE),
            fido_assert_set_uv(assert, FIDO_OPT_TRUE),
        ]
        if let bad = codes.first(where: { $0 != FidoCode.ok }) {
            free(assert: assert)
            throw SecurityKeyFailure.failed(code: bad)
        }
        return assert
    }

    /// The credential libfido2 asks for: ES256, kiff.dev ("KIFF"), the user, not discoverable,
    /// verification required. The caller frees it (`free(cred:)`).
    static func prepared(_ ask: SecurityKeyCredentialAsk) throws -> OpaquePointer {
        guard let cred = fido_cred_new() else { throw SecurityKeyFailure.failed(code: FidoCode.internal) }
        let codes = [
            fido_cred_set_type(cred, SecurityKeyCredentialAsk.es256),
            ask.clientDataHash.withUnsafeBytes { fido_cred_set_clientdata_hash(cred, $0.bindMemory(to: UInt8.self).baseAddress, $0.count) },
            fido_cred_set_rp(cred, Passkeys.rpID, SecurityKeyCredentialAsk.rpName),
            ask.userID.withUnsafeBytes {
                fido_cred_set_user(cred, $0.bindMemory(to: UInt8.self).baseAddress, $0.count, ask.userName, ask.userName, nil)
            },
            fido_cred_set_rk(cred, FIDO_OPT_FALSE),
            fido_cred_set_uv(cred, FIDO_OPT_TRUE),
        ]
        if let bad = codes.first(where: { $0 != FidoCode.ok }) {
            free(cred: cred)
            throw SecurityKeyFailure.failed(code: bad)
        }
        return cred
    }

    static func free(assert: OpaquePointer) {
        var pointer: OpaquePointer? = assert
        fido_assert_free(&pointer)
    }

    static func free(cred: OpaquePointer) {
        var pointer: OpaquePointer? = cred
        fido_cred_free(&pointer)
    }

    // MARK: The key

    /// Throws the key's failure for `code`. A wrong PIN reads the tries left, so the sheet can say.
    private static func check(_ code: Int32, _ device: OpaquePointer) throws {
        guard code != FidoCode.ok else { return }
        var left: Int32 = 0
        let tries: Int? = code == FidoCode.pinInvalid && fido_dev_get_retry_count(device, &left) == FidoCode.ok ? Int(left) : nil
        if let failure = SecurityKeyFailure.of(code, triesLeft: tries) { throw failure }
    }

    /// Opens the one FIDO2 key plugged in, with a PIN set: none, several, a U2F-only key or a key
    /// without a PIN is refused before anything is asked of it.
    static func openOnlyKey() throws -> OpaquePointer {
        let most = 8
        guard let list = fido_dev_info_new(most) else { throw SecurityKeyFailure.failed(code: FidoCode.internal) }
        defer {
            var pointer: OpaquePointer? = list
            fido_dev_info_free(&pointer, most)
        }
        var found = 0
        if let failure = SecurityKeyFailure.of(fido_dev_info_manifest(list, most, &found)) { throw failure }
        guard found > 0 else { throw SecurityKeyFailure.noKey }
        guard found == 1 else { throw SecurityKeyFailure.severalKeys }
        guard let info = fido_dev_info_ptr(list, 0), let path = fido_dev_info_path(info), let device = fido_dev_new() else {
            throw SecurityKeyFailure.failed(code: FidoCode.internal)
        }
        if let failure = SecurityKeyFailure.of(fido_dev_open(device, path)) {
            var pointer: OpaquePointer? = device
            fido_dev_free(&pointer)
            throw failure
        }
        let refusal: SecurityKeyFailure? = !fido_dev_is_fido2(device) ? .notFIDO2 : !fido_dev_has_pin(device) ? .pinNotSet : nil
        if let refusal {
            close(device)
            throw refusal
        }
        _ = fido_dev_set_timeout(device, SecurityKeyWait.milliseconds)
        return device
    }

    static func close(_ device: OpaquePointer) {
        _ = fido_dev_close(device)
        var pointer: OpaquePointer? = device
        fido_dev_free(&pointer)
    }

    /// Runs `body` with the open key, off the main thread: libfido2 blocks until the key answers.
    /// A cancelled task cancels the request at the key.
    private func run<T>(_ body: @escaping (OpaquePointer) throws -> T) async throws -> T {
        let open = OpenKey()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                queue.async { continuation.resume(with: Result { try open.run(body) }) }
            }
        } onCancel: {
            open.cancel()
        }
    }

    private static func bytes(_ pointer: UnsafePointer<UInt8>?, _ count: Int) -> Data {
        guard let pointer, count > 0 else { return Data() }
        return Data(bytes: pointer, count: count)
    }
}

/// The key while one request runs, so a cancel reaches it from another thread.
private final class OpenKey: @unchecked Sendable {
    private let lock = NSLock()
    private var device: OpaquePointer?
    private var cancelled = false

    func run<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        let opened = try FidoKey.openOnlyKey()
        lock.lock()
        let stop = cancelled
        if !stop { device = opened }
        lock.unlock()
        defer {
            lock.lock()
            device = nil
            lock.unlock()
            FidoKey.close(opened)
        }
        if stop { throw CancellationError() }
        do {
            return try body(opened)
        } catch {
            lock.lock()
            let wasCancelled = cancelled
            lock.unlock()
            throw wasCancelled ? CancellationError() : error
        }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if let device { _ = fido_dev_cancel(device) }
    }
}

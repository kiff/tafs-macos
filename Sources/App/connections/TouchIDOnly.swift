import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Touch ID, and only Touch ID, before this Mac ends a connection (`ConnectionEnding`): the
/// owner's rule is biometrics alone, never the Mac's password, so this is not
/// `NeedsYouModel.confirmOwner`, which lets the password in. The device key itself never
/// prompts (`DeviceKey`); this check is what the person confirms, as the iPad's Face ID before
/// `signConfirmed` and Windows Hello before the TPM key.
///
/// The check is the ending key's signature (`EndingKey`): a Secure Enclave key made at sign-in
/// that only Touch ID's fingers enrolled then can use. A finger added since (which on a Mac asks
/// only its password) invalidates it, and the Mac goes to the phone until the next sign-in.
struct TouchIDOnly {
    /// Whether this Mac can end a connection with Touch ID now: this sign-in's ending key, which
    /// loads, and Touch ID that can be checked. Reads only, and never prompts.
    var available: () -> Bool
    /// Asks for Touch ID with the reason (the question's title) by signing the message (the
    /// iPad's confirmation) with the ending key. Any failure throws, so nothing is sent; an ending
    /// key gone throws `ConnectionEnding.KeyGone`.
    var confirm: (String, Data) async throws -> Void

    /// This Mac's Touch ID for one session.
    static func system(session: Session, store: SecretStore = KeychainStore()) -> TouchIDOnly {
        checked(EndingKey.check(session: session, store: store))
    }

    /// Touch ID through an ending key's check.
    static func checked(_ check: ConnectionEnding.EndingKeyCheck) -> TouchIDOnly {
        TouchIDOnly(available: { check.available() }, confirm: { reason, message in try await check.confirm(reason, message) })
    }

    /// A Mac with no Touch ID: its connections end on the phone.
    static let none = TouchIDOnly(available: { false }, confirm: { _, _ in throw ConnectionEnding.KeyGone() })
}

/// The **ending key**: a second P-256 key in the Secure Enclave, made at sign-in, whose only use
/// is Touch ID's confirmation before this Mac ends a connection. Its access control is
/// `.privateKeyUsage` and `.biometryCurrentSet`: it signs only after Touch ID with the fingers
/// enrolled when it was made, never with the Mac's password, and the system invalidates it when
/// a finger is added or removed. The Keychain holds only its handle (the Secure Enclave's wrapped
/// reference, never the key), with the sign-in it was made for (`binding`).
enum EndingKey {
    static let account = "tafs.ending-key"

    /// The sign-in a key is for: the SHA-256 of the session's token, so another sign-in's key,
    /// even for the same account and device, is never this one's.
    static func binding(_ session: Session) -> String {
        Signing.sha256Hex(Data(session.accessToken.utf8))
    }

    /// Sign-in's hook (`SignInModel`): made when a session is kept, deleted when it's forgotten.
    static func hook(store: SecretStore) -> EndingKeyHook {
        EndingKeyHook(kept: { session, keyStore in
            ConnectionEnding.keepEndingKey(session: EndingKey.binding(session), enclave: keyStore == "enclave" && SecureEnclave.isAvailable,
                                           biometrics: EndingKey.biometrics, create: EndingKey.create,
                                           save: { try store.save($0, for: EndingKey.account) }, remove: { store.delete(EndingKey.account) })
        }, forgotten: { store.delete(EndingKey.account) })
    }

    /// The check for `session`, against the ending key kept in `store`.
    static func check(session: Session, store: SecretStore) -> ConnectionEnding.EndingKeyCheck {
        ConnectionEnding.EndingKeyCheck(session: binding(session), read: { store.load(EndingKey.account) }, remove: { store.delete(EndingKey.account) },
                                        biometrics: EndingKey.biometrics, loads: EndingKey.loads, sign: EndingKey.sign)
    }

    /// Whether Touch ID can be checked now, with no prompt: none, none set up, or locked out is false.
    static func biometrics() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// A new ending key, made with no prompt; its handle.
    static func create() throws -> Data {
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .biometryCurrentSet], nil) else {
            throw ConnectionEnding.KeyGone()
        }
        return try SecureEnclave.P256.Signing.PrivateKey(accessControl: access).dataRepresentation
    }

    /// Whether the handle loads, with no prompt: a context that may not ask anything.
    static func loads(_ handle: Data) -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        return (try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: handle, authenticationContext: context)) != nil
    }

    /// Touch ID: the key signs `message`, and the system asks for Touch ID with `reason`. Off the
    /// main thread, which the signature holds until Touch ID answers.
    static func sign(_ handle: Data, reason: String, message: Data) async throws {
        try await Task.detached(priority: .userInitiated) {
            try EndingKey.signNow(handle, reason: reason, message: message)
        }.value
    }

    private static func signNow(_ handle: Data, reason: String, message: Data) throws {
        let context = LAContext()
        context.localizedReason = reason
        // No password button: biometrics only, as the key's access control allows no other.
        context.localizedFallbackTitle = ""
        let key: SecureEnclave.P256.Signing.PrivateKey
        do {
            key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: handle, authenticationContext: context)
        } catch {
            throw ConnectionEnding.KeyGone()
        }
        let signature: P256.Signing.ECDSASignature
        do {
            signature = try key.signature(for: message)
        } catch where NeedsYouModel.closed(error) || EndingKey.notPassed(error) {
            throw OwnerPrompt.Closed()
        } catch {
            // Anything else: the key can't sign, as when the fingers changed and the system
            // invalidated it.
            throw ConnectionEnding.KeyGone()
        }
        // Defensive: a signature the key's own public half doesn't take confirms nothing.
        guard key.publicKey.isValidSignature(signature, for: message) else { throw ConnectionEnding.KeyGone() }
    }

    /// Touch ID didn't pass, the key still stands: only what says so. The system's own words
    /// (`LAError`, as thrown or beneath CryptoTokenKit's): a cancel, a failed match, a lockout, or
    /// Touch ID not there or not askable now; or CryptoTokenKit's cancel (-4). CryptoTokenKit's
    /// needs-authentication (-9) or failed (-5) with none of these beneath it is the usual error of
    /// a key whose access control can't be met, as one the system invalidated when the fingers
    /// changed: that is not this, so the key is deleted and the Mac goes to the phone.
    static func notPassed(_ error: Error) -> Bool {
        let ns = error as NSError
        if let la = laCode(error) ?? (ns.userInfo[NSUnderlyingErrorKey] as? Error).flatMap(laCode) {
            switch la {
            case .userCancel, .systemCancel, .appCancel, .userFallback, .authenticationFailed, .biometryLockout,
                 .biometryNotAvailable, .notInteractive:
                return true
            default:
                return false
            }
        }
        return ns.domain == "CryptoTokenKit" && ns.code == -4
    }

    /// The system's code for a LocalAuthentication error, whichever way it came.
    private static func laCode(_ error: Error) -> LAError.Code? {
        if let la = error as? LAError { return la.code }
        let ns = error as NSError
        guard ns.domain == LAErrorDomain else { return nil }
        return LAError.Code(rawValue: ns.code)
    }
}

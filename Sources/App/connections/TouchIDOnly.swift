import Foundation
import LocalAuthentication

/// Touch ID, and only Touch ID, before this Mac ends a connection (`ConnectionEnding`): the
/// owner's rule is biometrics alone, never the Mac's password, so this is not
/// `NeedsYouModel.confirmOwner`, which lets the password in. The device key itself never
/// prompts (`DeviceKey`); this check is what the person confirms, as the iPad's Face ID before
/// `signConfirmed` and Windows Hello before the TPM key.
///
/// A finger enrolled since the session first checked Touch ID is refused
/// (`ConnectionEnding.Fingers`): adding one on a Mac asks only its password.
struct TouchIDOnly {
    /// Whether this Mac can check Touch ID now: none, none set up, locked out, or fingers
    /// changed since this session began is false.
    var available: () -> Bool
    /// Asks for Touch ID with `reason`; a prompt the person closed, or its password button,
    /// throws `OwnerPrompt.Closed`, and fingers that changed throw `FingersChanged`.
    var confirm: (String) async throws -> Void

    /// Touch ID's enrolled fingers aren't the ones this session first saw: nothing is sent.
    struct FingersChanged: Error {}

    /// Where the fingers this session first saw are kept: this Mac only, never synced.
    static let account = "tafs.touch-id.fingers"

    /// This Mac's Touch ID for one session (`session`: its tenant, subject and device id).
    static func system(session: String, store: SecretStore = KeychainStore()) -> TouchIDOnly {
        sealed(session: session, store: store, current: TouchIDOnly.enrolled, evaluate: TouchIDOnly.check)
    }

    /// A Mac with no Touch ID: its connections end on the phone.
    static let none = TouchIDOnly(available: { false }, confirm: { _ in throw OwnerPrompt.Closed() })

    /// Touch ID held to the fingers this session first saw. `current` is the enrolled set now
    /// (nil when Touch ID can't be checked); `evaluate` asks Touch ID and gives the set it passed
    /// with. The first set seen is kept in `store`; any other refuses.
    static func sealed(session: String, store: SecretStore,
                       current: @escaping () -> Data?,
                       evaluate: @escaping (String) async throws -> Data?) -> TouchIDOnly {
        func same(_ now: Data?) -> Bool {
            switch ConnectionEnding.fingers(recorded: store.load(account), session: session, now: now) {
            case .same: return true
            case .changed: return false
            case .first:
                guard let now else { return false }
                do { try store.save(ConnectionEnding.fingersRecord(session: session, now: now), for: account) } catch { return false }
                return true
            }
        }
        return TouchIDOnly(available: { same(current()) }, confirm: { reason in
            guard same(current()) else { throw FingersChanged() }
            let passed = try await evaluate(reason)
            // The set Touch ID passed with must be the one kept: never recorded here.
            guard ConnectionEnding.fingers(recorded: store.load(account), session: session, now: passed) == .same else {
                throw FingersChanged()
            }
        })
    }

    /// The enrolled set now, read with no prompt; nil when Touch ID can't be checked.
    static func enrolled() -> Data? {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return nil }
        return context.evaluatedPolicyDomainState
    }

    /// Asks Touch ID alone, and gives the enrolled set it passed with.
    static func check(_ reason: String) async throws -> Data? {
        let context = LAContext()
        // No password button: biometrics only.
        context.localizedFallbackTitle = ""
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw error ?? LAError(.biometryNotAvailable)
        }
        do {
            guard try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) else {
                throw LAError(.authenticationFailed)
            }
        } catch where NeedsYouModel.closed(error) {
            throw OwnerPrompt.Closed()
        }
        return context.evaluatedPolicyDomainState
    }
}

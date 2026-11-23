import Foundation
import LocalAuthentication

/// Touch ID, and only Touch ID, before this Mac ends a connection (`ConnectionEnding`): the
/// owner's rule is biometrics alone, never the Mac's password, so this is not
/// `NeedsYouModel.confirmOwner`, which lets the password in. The device key itself never
/// prompts (`DeviceKey`); this check is what the person confirms, as the iPad's Face ID before
/// `signConfirmed` and Windows Hello before the TPM key.
struct TouchIDOnly {
    /// Whether this Mac can check Touch ID now: none, none set up, or locked out is false.
    var available: () -> Bool
    /// Asks for Touch ID with `reason`; a prompt the person closed, or its password button,
    /// throws `OwnerPrompt.Closed`.
    var confirm: (String) async throws -> Void

    static let system = TouchIDOnly(available: TouchIDOnly.canCheck, confirm: TouchIDOnly.check)

    /// A Mac with no Touch ID: its connections end on the phone.
    static let none = TouchIDOnly(available: { false }, confirm: { _ in throw OwnerPrompt.Closed() })

    static func canCheck() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    static func check(_ reason: String) async throws {
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
    }
}

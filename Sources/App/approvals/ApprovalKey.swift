import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// The **approval key**: it signs what grants authority, and only behind Touch ID.
///
/// It exists only in the Secure Enclave. Its own access control requires the fingerprints
/// enrolled when it was made, never the password, so the key checks the prompt itself: code
/// that skipped the prompt can't sign with it. A Mac with no Secure Enclave, or with no
/// fingerprint enrolled, has **no approval key**, and there is no software stand-in for one.
struct ApprovalKey {
    static let account = "tafs.approval-key"
    /// The fingerprints enrolled when the key was made: when they differ, the key no longer signs.
    static let domainAccount = "tafs.approval-key.domain"

    /// Private-key use, by the fingerprints enrolled now and nothing else.
    static let flags: SecAccessControlCreateFlags = [.privateKeyUsage, .biometryCurrentSet]

    private let handle: Data
    let publicKeyDER: Data

    enum Refused: Error, Equatable {
        /// A prompt must say what the fingerprint is for.
        case noReason
    }

    /// Whether this Mac can hold one at all: a Secure Enclave, and a fingerprint enrolled.
    static var available: Bool {
        SecureEnclave.isAvailable && LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// The approval key this Mac already has, or nil. **It never makes one**: a new key is
    /// the person's act, at sign-in or pairing (`make`), never a side effect of launching.
    ///
    /// Nil on a Mac that can't hold one, when none is kept, when the enrolled fingerprints
    /// changed since it was made, and when the kept handle no longer reads. In the last two
    /// cases what was kept is forgotten, and nothing takes its place.
    static func load(from store: SecretStore, available: Bool = ApprovalKey.available,
                     domain: Data? = ApprovalKey.biometricsDomain()) -> ApprovalKey? {
        guard available, let handle = store.load(account) else { return nil }
        if !changed(made: store.load(domainAccount), now: domain),
           let key = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: handle) {
            return ApprovalKey(handle: handle, publicKeyDER: key.publicKey.derRepresentation)
        }
        store.delete(account)
        store.delete(domainAccount)
        return nil
    }

    /// A new key in the Secure Enclave, kept with the fingerprints it was made under. Called
    /// only from the step where the person enrols this Mac. It makes none without those
    /// fingerprints' value to keep: a later change could not be told to the person otherwise.
    static func make(in store: SecretStore, available: Bool = ApprovalKey.available,
                     domain: Data? = ApprovalKey.biometricsDomain()) -> ApprovalKey? {
        guard available, let domain,
              let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, nil),
              let key = try? SecureEnclave.P256.Signing.PrivateKey(accessControl: access) else { return nil }
        do {
            try store.save(key.dataRepresentation, for: account)
            try store.save(domain, for: domainAccount)
        } catch {
            store.delete(account)
            store.delete(domainAccount)
            return nil
        }
        return ApprovalKey(handle: key.dataRepresentation, publicKeyDER: key.publicKey.derRepresentation)
    }

    /// Asks for Touch ID, saying what the fingerprint is for, then signs. Every signature asks
    /// again: nothing is kept between two. A prompt with nothing to say is never shown.
    func sign(_ message: Data, reason: String) throws -> Data {
        try Self.check(reason: reason)
        let context = LAContext()
        context.localizedReason = reason
        // No reuse of an unlock given before, and no password in place of the fingerprint.
        context.touchIDAuthenticationAllowableReuseDuration = 0
        context.localizedFallbackTitle = ""
        defer { context.invalidate() }
        let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: handle, authenticationContext: context)
        return try key.signature(for: message).derRepresentation
    }

    /// A prompt's reason must say something. Checked before any prompt or key is touched.
    static func check(reason: String) throws {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Refused.noReason }
    }

    /// Whether the enrolled fingerprints changed since the key was made. Only two known values
    /// that differ say so: none now may be a lockout after a few misses, which leaves a good key alone.
    static func changed(made: Data?, now: Data?) -> Bool {
        guard let made, let now else { return false }
        return made != now
    }

    /// The enrolled fingerprints, as an opaque value that changes when they do.
    static func biometricsDomain() -> Data? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        return context.evaluatedPolicyDomainState
    }
}

extension ApprovalMeans {
    /// How this Mac approves: with its approval key when it has one **and** its device key is
    /// in hardware too; otherwise on the phone or with a passkey.
    static func of(deviceKey: SigningKey, approvalKey: ApprovalKey?) -> ApprovalMeans {
        guard deviceKey.keyStore != "software", let approvalKey else { return .passkey }
        return .key(approvalKey.publicKeyDER)
    }
}

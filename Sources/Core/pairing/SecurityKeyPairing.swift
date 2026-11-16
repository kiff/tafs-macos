import Foundation

/// Registering this Mac's USB security key through pairing, as the public spec's "A security key
/// goes with its computer" (kiff/tafs `docs/computer-passkeys.md`) and Windows' own passkey
/// (tafs-windows `PairingAttempt`, `PairingOffer`, `PairingClaim`, `WindowsHello.CreateAsync`):
///
/// 1. the key makes a new credential for kiff.dev, ES256, the person verified by its PIN;
/// 2. the pairing QR (`kind: "passkey"`) names it as `credential {id, public_key}`, and the check
///    code covers its key in the approval key's place;
/// 3. the phone's one pairing approval registers it for this Mac;
/// 4. with the creation proof on, the claim carries `credential_proof`, and the credential's
///    challenge holds the pairing's nonce and device key.
///
/// **Off:** nothing is asked of the key while `Features.macPasskeyApprovals` is off, and nothing
/// in the app calls this yet. The PIN sheet comes with the switch (part 4).
extension Features {
    /// Whether the claim proves the credential (`credential_proof`), as Windows'
    /// `Features.PairingPasskeyProof`: off until KIFF takes it.
    static let macPairingPasskeyProof = false
}

/// What the creation returned, kept as it is for KIFF's creation proof: the `clientDataJSON` this
/// app wrote, and the attestation object.
struct CredentialProof: Equatable {
    let clientDataJSON: Data
    let attestationObject: Data

    /// The claim's `credential_proof`, each part base64url without padding, as Windows sends it.
    var fields: [String: String] {
        ["client_data_json": Encoding.base64URL(clientDataJSON), "attestation_object": Encoding.base64URL(attestationObject)]
    }
}

/// The security key's new credential, ready for the QR: what KIFF registers, and the creation's
/// proof.
struct PairingPasskey: Equatable {
    let passkey: NewPasskey
    let proof: CredentialProof?

    /// The QR's `credential`: the id and the SPKI DER, base64url as the QR writes keys.
    var credential: PairingPayload.Credential {
        PairingPayload.Credential(id: Encoding.base64URL(passkey.credentialID), publicKey: Encoding.base64URL(passkey.publicKeyDER))
    }
}

enum SecurityKeyPairing {
    /// A credential id is at most 1023 bytes (WebAuthn's own bound, and the phones' check).
    static let longestID = 1023

    /// The credential's `clientDataJSON`, which this app writes, as Windows' does: `webauthn.create`,
    /// the challenge, kiff.dev's origin, not cross-origin, in that order.
    static func clientDataJSON(challenge: String) -> Data {
        Data(#"{"type":"webauthn.create","challenge":"\#(challenge)","origin":"\#(Passkeys.origin)","crossOrigin":false}"#.utf8)
    }

    /// The credential's user id: sha256 of the device key, the same on every attempt with that key, so a
    /// credential made again for this Mac is for the same user, as Windows' `PasskeyUserId`.
    static func userID(deviceKeyDER: Data, sha256: (Data) -> Data) -> Data { sha256(deviceKeyDER) }

    /// The challenge a creation's `clientDataJSON` holds, or nil, as Windows' `ProofChallenge`.
    static func proofChallenge(_ proof: CredentialProof) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: proof.clientDataJSON) as? [String: Any] else { return nil }
        return object["challenge"] as? String
    }

    /// The challenge for a creation: the pairing's (`PasskeyRegistration.pairingChallenge`) when the
    /// claim proves it, else 32 random bytes, as Windows' `CreateAsync`.
    static func challenge(proving: Bool, nonce: String, deviceKeyDER: Data, sha256: (Data) -> Data,
                          random: () -> Data) -> String {
        proving ? PasskeyRegistration.pairingChallenge(nonce: nonce, deviceKeyDER: deviceKeyDER, sha256: sha256)
            : Encoding.base64URL(random())
    }

    /// Asks the key for a new credential with `challenge`, and reads it as KIFF registers it.
    ///
    /// - Refused before the key is asked while `enabled` is off (`PasskeyRefusal.off`).
    /// - The key's answer is checked as an approval's is (kiff.dev, present and verified, not synced),
    ///   then ES256 on P-256, an id of 1 to 1023 bytes, and a key that isn't the device key.
    /// - The attestation object sent is `none`, as Windows asks for no attestation
    ///   (`AttestationNone`): the key's own statement and certificate, which name its model, never
    ///   leave this Mac.
    static func make(challenge: String, deviceKeyDER: Data, name: String, authenticator: PasskeyAuthenticator,
                     pin: SecurityKeyPIN?, sha256: (Data) -> Data, isOnCurve: (Data, Data) -> Bool,
                     enabled: Bool = Features.macPasskeyApprovals) async throws -> PairingPasskey {
        guard enabled else { pin?.release(); throw PasskeyRefusal.off }
        let clientData = clientDataJSON(challenge: challenge)
        let made = try await authenticator.makeCredential(clientDataHash: sha256(clientData),
                                                          userID: userID(deviceKeyDER: deviceKeyDER, sha256: sha256),
                                                          userName: name, pin: pin)
        let passkey = try PasskeyRegistration.read(made.authenticatorData, sha256: sha256, isOnCurve: isOnCurve)
        guard (1...longestID).contains(passkey.credentialID.count), passkey.publicKeyDER != deviceKeyDER else {
            throw PasskeyRefusal.unreadable
        }
        let none = AttestationObject.make(format: "none", statement: Data([0xa0]), authenticatorData: made.authenticatorData)
        return PairingPasskey(passkey: passkey, proof: CredentialProof(clientDataJSON: clientData, attestationObject: none))
    }

    /// One pairing attempt's credential, as Windows' `PairingAttempt.OfferAsync`:
    ///
    /// - **Without the proof,** a credential kept from the last attempt is used again, so a new code
    ///   asks the key for nothing and leaves no extra credential on it.
    /// - **With it,** the challenge holds the nonce, so each attempt makes it again, and one whose
    ///   challenge isn't this pairing's is refused here, before the QR is shown.
    /// - **A refused or unread credential, or a key not touched or declined,** pairs without one
    ///   (the Mac then approves on the phone), as Windows pairs when Windows Hello is closed. Any other
    ///   failure (no key, a wrong PIN, a blocked key) is thrown, for the PIN sheet to say why.
    static func credential(kept: PairingPasskey?, proving: Bool, nonce: String, deviceKeyDER: Data,
                           make: (_ challenge: String) async throws -> PairingPasskey,
                           sha256: (Data) -> Data, random: () -> Data) async throws -> PairingPasskey? {
        if !proving, let kept { return kept }
        let challenge = challenge(proving: proving, nonce: nonce, deviceKeyDER: deviceKeyDER, sha256: sha256, random: random)
        let made: PairingPasskey
        do {
            made = try await make(challenge)
        } catch is PasskeyRefusal {
            return nil
        } catch SecurityKeyFailure.timedOut {
            return nil
        } catch SecurityKeyFailure.denied {
            return nil
        }
        if proving {
            let pairing = PasskeyRegistration.pairingChallenge(nonce: nonce, deviceKeyDER: deviceKeyDER, sha256: sha256)
            guard let proof = made.proof, proofChallenge(proof) == pairing else { throw PasskeyRefusal.unreadable }
        }
        return made
    }
}

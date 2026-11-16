import CSecp256k1
import Foundation

/// The receipt check's recovery: libsecp256k1's own, with its recovery module only, built from pinned
/// source as the security key's library is (scripts/fido.sh, docs/building.md). It's the release the
/// iPad's swift-secp256k1 vendors, so the Mac and the iPad recover a receipt's signer with the same C
/// code (the iPad's `ReceiptCheck.recoverAddress`).
enum ReceiptRecovery {
    /// The key's X ‖ Y that signed `digest`, from r ‖ s and the recovery id 0–3, or nil
    /// (`ReceiptRecover`; `ReceiptSigner.address` reads v and refuses any other id first).
    static func recover(digest: Data, compact: Data, recoveryID: Int32) -> Data? {
        guard digest.count == 32, compact.count == 64, (0...3).contains(recoveryID) else { return nil }
        // Recovery needs no randomized context: the library's static one, as its docs allow.
        guard let context = secp256k1_context_static else { return nil }
        var signature = secp256k1_ecdsa_recoverable_signature()
        let compactBytes = [UInt8](compact), digestBytes = [UInt8](digest)
        // r or s at or above the group's order isn't read.
        guard secp256k1_ecdsa_recoverable_signature_parse_compact(context, &signature, compactBytes, recoveryID) == 1 else {
            return nil
        }
        // A high s is taken, as the iPad (this same library) and Linux take it: the same key signs with
        // s or n − s, and a receipt's signature only says who signed it. It's never an id or a key for
        // telling receipts apart, so its malleability changes nothing a receipt proves. KIFF's signer
        // writes a low s anyway.
        var key = secp256k1_pubkey()
        guard secp256k1_ecdsa_recover(context, &key, &signature, digestBytes) == 1 else { return nil }
        var out = [UInt8](repeating: 0, count: 65)
        var length = 65
        guard secp256k1_ec_pubkey_serialize(context, &out, &length, &key, UInt32(SECP256K1_EC_UNCOMPRESSED)) == 1,
              length == 65, out[0] == 0x04 else { return nil }
        return Data(out[1...])
    }
}

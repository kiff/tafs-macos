# Keys and signatures

KIFF acts on a request from this app only when it carries a signature it can check. This
page says which keys a Mac holds, what they sign, and where the code is. The contract is
KIFF's `docs/desktop-client.md`; its worked example is one of this app's tests.

## The keys

| Key | What it signs | Where its private half is |
|---|---|---|
| **Device key** | Ordinary requests, with no prompt: reads, Refuse, sign-out, a pairing's claim. Never an approval. | The Secure Enclave on a Mac that has one. Otherwise the login Keychain, for this Mac only, never synced. |
| **Approval key** | What grants authority, behind Touch ID. | The Secure Enclave only. A Mac without one has **no approval key**. |

- **A Mac without a Secure Enclave** (most Intel Macs without Touch ID) says its device key
  is `software`. KIFF refuses that key on every route that grants authority. On that Mac an
  approval is signed on the phone, or by a passkey.
- **A private key is never** written to a file, a log, a screenshot or a setting. The
  Keychain holds the software key's bytes, or the Secure Enclave key's handle.

`DeviceKey.load(from:)` (`Sources/App/pairing/Keys.swift`) makes the key at first launch and
reads the same one afterwards.

## What is signed

Every signature is ECDSA over P-256 and SHA-256, written as ASN.1 DER in standard base64.

| Message | Made by | For |
|---|---|---|
| `kiff.request.v1` | `Signing.header` | A signed request: the tenant, the method, the path and query, the body's hash, the time. |
| `kiff.request.v2` | `Signing.header(… window:)` | The same inside an approval window, with the window's id. |
| `kiff.pair.claim.v1` | `Signing.claimProof` | Claiming a pairing: proof that this Mac holds the device key the phone approved. |
| `planque.request.v1` | `PlanqueClient.enrol`'s `send` | This device's enrolment at planque (`POST /v1/accounts/{tenant}/enrolment`), over the exact body sent, as `Planque-Device-Signature: t={time},v1={signature},d={dev_…}`: the device key, as the iPad's `planque.signer` (`signConfirmed`). See [connections.md](connections.md), "Setting planque up". |
| `planque.request.v1` | `PlanqueClient.grantsReadProof` | planque's proof that this device reads its own account's grants (`GET /v1/accounts/{tenant}/grants`, an empty body), sent with a taf's Setup read as `Planque-Device-Signature: t={time},v1={signature},d={dev_…}`. It reads; it grants nothing, so it asks no one, as the iPad's `signConfirmed`. |

- **The exact bytes sent are the bytes signed.** The body is hashed as it goes on the wire.
- **A message's fields** are joined by a line feed, with none after the last
  (`KIFFMessage`, `Sources/Core/pairing/Messages.swift`).

## Pairing's code and QR

- **The QR code** holds `PairingPayload` (`kiff.pair.v1`): this Mac's public keys, its name,
  a nonce and when the code expires, at most 5 minutes ahead. No secret is in it.
- **`key_store`**: a Mac whose device key isn't in hardware writes `"key_store": "software"` in
  the QR code, and sends it when it signs in. The phone's signature covers it, so KIFF never
  lets that key approve, open an approval window or take a tap inside one. Such a Mac never
  puts an approval key in its code. A Mac whose key is in the Secure Enclave leaves the field out.
- **The check code** (`Signing.checkCode`) is 6 characters made from the public keys. This
  Mac and the phone both show it before the phone asks for a fingerprint, so a page that
  shows its own QR code can't have its key approved in this Mac's place. A test holds it to the
  vector every tafs app and KIFF share.

## Tests

`scripts/test.sh pairing` checks, among others:

- the worked example's message, both hashes and KIFF's own signature;
- that a trailing line feed, another key or another nonce is refused;
- that a signature is DER, and that the header inside a window signs the `v2` message;
- that the device key is made once and stays the same;
- the Keychain: save, replace, delete.

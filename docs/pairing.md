# Signing in and adding this Mac

How a Mac gets a session with KIFF, and how it gets the right to ask for approvals. The
contract is KIFF's `docs/desktop-client.md` (§1.1 and §5). The keys are in
[signing.md](signing.md).

## Two ways in

| | When | What the Mac gets |
|---|---|---|
| **Sign in in the browser** | The account's first device, or to look without approving | A session. On an account that already has a device that approves, it is **view-only**. |
| **Add this Mac with a phone** | The account already has a device that approves | A session that may ask for approvals, once that phone has signed this Mac's keys. |

A code typed from an authenticator app only ever signs in. It never adds a Mac for approvals
and never approves an action.

## Signing in (`KIFFClient.startSignIn`, `token`)

1. The Mac sends its device key's public half, its name, `platform: macos`, and how it
   approves: its approval key's public half, or `approval: passkey` when it has none.
2. KIFF answers a code and a page. The person opens the page, checks the code and approves.
3. The Mac asks for its session every few seconds (`Waiting.until`) until it is handed over.

## Adding this Mac with a phone (`PairingPayload`, `KIFFClient.claimPairing`)

1. The Mac shows a QR code with its public keys and name, and a 6-character check code.
2. The phone scans it, shows the same check code, and signs the Mac's keys behind the
   person's fingerprint or face.
3. The Mac asks for its session with a proof that it holds the device key the phone approved.

A code lasts at most 5 minutes. A session is handed over once.

**This Mac's security key** (not shown yet: it comes with the switch, [approvals.md](approvals.md)):
- **The QR** names the key's new credential as `credential {id, public_key}`, base64url, the key
  as SPKI DER. It goes only with `kind: "passkey"`, never beside an approval key or with a
  software device key, which pairs as view.
- **The check code** covers the credential's key in the approval key's place
  (`PairingPayload.checkedKeyDER`), so the code covers the key the phone registers. It's tested on
  the phones' vector: `H6SJNU` for the public keys of private keys 1 and 2, `LTJFF6` for the first
  alone.
- **With the creation proof on,** the claim adds
  `credential_proof {client_data_json, attestation_object}`, each base64url. Without it, the claim
  is as before.
- **Signing out forgets the key's credential id** with the session.

## Waiting

`Waiting.until` paces every ask as the contract says:

- it waits one interval before the first ask, and between asks;
- "not yet" asks again; "slow down" adds 5 seconds to the interval for the rest of the wait;
- it stops at the code's expiry, and never waits more than 10 minutes;
- any other answer ends the wait and is shown to the person.

## What is never kept or shown

- The session's token is kept in the Keychain only.
- No request, answer, token or signature is logged.
- `NetworkTransport` sends to `https://api.kiff.dev` only, and refuses any other host.

## Tests

`scripts/test.sh pairing`: the exact fields each route is sent, that a Mac with no approval
key never sends one, every answer the contract names, and the waiting's pace with a clock
the test controls. No test reaches the network. For the security key: the credential's client
data, user id and challenge, the attestation sent as `none`, each refusal, the kept and remade
credential, the QR's `credential`, the check code's vector, and the claim's `credential_proof`.
On a Mac, a real P-256 key's credential against CryptoKit's SPKI, and sign-out forgetting it.

## The screens

A Mac with no session opens on sign-in (`SignInView`, driven by `SignInModel`).

| Step | What it shows |
|---|---|
| Welcome | What tafs is, **Sign in with KIFF**, and "Already use tafs on your phone? Add this Mac with it." |
| The browser's code | The code KIFF's page must show, and that the Mac is waiting. KIFF's page opens by itself. |
| The pairing code | The QR code, where to scan it on the phone, the 6-character check code, and that the Mac is waiting. |
| The code ran out | "This code expired." and **Show a new code**. Each code has a new nonce. |
| It didn't work | KIFF's own code for why, and **Try again**. |

- **Only KIFF's page is ever opened**: `https`, on `kiff.dev`. Any other address in the answer is ignored.
- **Cancel** stops the waiting, and a late answer to a cancelled attempt is dropped.
- **The QR code** (`QRCode`) is the pairing text as bytes with error correction M. A test reads
  it back from the image, as a phone's camera would.
- **The session** goes to the Keychain as soon as it is handed over, and the next launch opens
  signed in.

`scripts/test.sh pairing` writes the screens to `build/screenshots/sign-in-*.png` in English,
French and Portuguese.

## Adding a Mac that is already signed in

A Mac that signed in through the browser on an account that has a device is view-only. It
shows "View only" in Account, with **Add this Mac**. KIFF refuses a pairing for a key that is
already a device's, so:

1. The Mac makes a **new device key**, kept apart from the one in use, and shows the pairing
   code with that key.
2. When the phone has approved and the Mac has claimed the pairing, the new session and the
   new key are kept **first**.
3. **Then** the Mac signs its old view-only session out at KIFF, with the old key.

If the pairing doesn't happen (the code runs out, KIFF refuses the claim, the person
cancels), the new key is forgotten, nothing is signed out, and the Mac stays signed in as it
was. There is no upgrade of a device in place.

The pairing steps name the phone's own button, from the shared words
(`settings.devices.pair`).

## The Keychain

The session, the device key (or its Secure Enclave handle), a pairing's new key and the
security key's credential id are kept by `KeychainStore`, in the login Keychain, under the service `bot.tafs.macos`.

- **A save replaces this app's own item.** It adds the item; if one is there already, it
  updates it; if that is refused, it deletes the item and adds it again. A re-pair writes over
  the session and key an earlier pairing kept.
- **Why that matters for an unsigned build.** The Keychain ties an item to the build that made
  it, and each unsigned build is a new app to it. An earlier build's item may refuse to be
  changed or deleted by the next build. Saving used to delete without reading the answer, then
  add, so the add failed as a duplicate (`errSecDuplicateItem`, -25299) once the phone had
  already approved, and KIFF was left with a Mac device that this Mac couldn't keep.
- **A pairing checks first.** Before it shows its code, it writes the device key and the
  session over themselves (`SecretStore.checkWritable`). If the Keychain refuses, the pairing
  stops there: no code, no claim, and nothing for the phone to approve.
- **An item this build can't read is replaced by the check.** When the Keychain won't hand an
  earlier build's session or key to this one, the check writes over it and deletes what it
  wrote. Nothing usable is lost: this build couldn't use that item anyway.
- **An update keeps the item's strength.** It sets the data and "when unlocked, this device
  only" together, so an item an earlier build kept with a weaker setting is brought up to it.
- **A refused delete is the number shown**, since it is the step that ended the save.
- **A refusal carries the Keychain's status number only** (`KeychainStore.Refused`), never the
  item. The screen says "This Mac wasn't added: -25299. Show a new code and try again." and
  never the error's type.

`scripts/test.sh pairing` on a Mac writes over an item kept with none of this build's
attributes, pairs and then re-pairs at a new launch against a test service in the real
Keychain, and checks that a Keychain that refuses stops the pairing before its code.

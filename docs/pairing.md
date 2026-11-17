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

**This Mac's security key** ([approvals.md](approvals.md), "Passkeys on macOS 12"). Asked only
while passkey approvals are on (`Features.macPasskeyApprovals`, off for now): until then this Mac
pairs as today, with no credential, and approves on the phone.
- **The PIN sheet first** (`SignInModel.pair`, `PairingSecurityKey`): before the code is shown,
  the sheet asks for the key's PIN, then the key makes the credential for this pairing. A wrong
  PIN, no key or a locked key says why in the sheet's shared lines, and the person tries again or
  closes it. **Closing it pairs without the key,** as Windows pairs when Windows Hello is closed:
  this Mac then approves on the phone. Cancelling the pairing closes the sheet, and nothing is
  asked or claimed.
- **The sheet's own words while pairing** (`SecurityKeySheetPurpose.addKey`): "Add your security
  key to this computer" (`approval.security_key.add_title`), what it asks
  (`add_enter_pin`), **Add key** (`add`) and **Pair without a key** (`pair_without`, the sheet's
  close and Esc). An approval's sheet keeps its own title, lead, Approve and Cancel. The PIN, the
  touch and every failure line are the same for both.
- **The QR** names the key's new credential as `credential {id, public_key}`, base64url, the key
  as SPKI DER. It goes only with `kind: "passkey"`, never beside an approval key or with a
  software device key, which pairs as view.
- **The check code** covers the credential's key in the approval key's place
  (`PairingPayload.checkedKeyDER`), so the code covers the key the phone registers. It's tested on
  the phones' vector: `H6SJNU` for the public keys of private keys 1 and 2, `LTJFF6` for the first
  alone.
- **The creation proof is on** (`Features.macPairingPasskeyProof`): KIFF checks it, and requires
  it on a passkey computer's claim from 1 Dec 2026. The credential's challenge holds the pairing's
  nonce and device key, so each code asks the key again, and the claim adds
  `credential_proof {client_data_json, attestation_object}`, each base64url: the client data this
  app wrote, and attestation `none` with an empty `attStmt`. A claim with no credential carries no
  proof.
- **Kept only once claimed:** the credential id is saved (`SecurityKeyStore`) once the pairing is
  claimed, never while the phone hasn't approved. A pairing that names no key forgets an earlier
  one, which went with another device key. The store is checked writable before the code, with
  the session's, and the id is saved last, once the screen holds the new session: a store that
  refuses it then keeps none (this Mac approves on the phone), and the pairing stands.
- **One sheet at a time:** a new ask closes a sheet still up, so its own ask resumes as cancelled.
- **Signing out forgets the key's credential id** with the session.

## Waiting

`Waiting.until` paces every ask as the contract says:

- it waits one interval before the first ask, and between asks;
- "not yet" asks again; "slow down" adds 5 seconds to the interval for the rest of the wait;
- it stops at the code's expiry, and never waits more than 10 minutes;
- any other answer ends the wait and is shown to the person.

## A sign-in KIFF no longer accepts

A session can end while the Mac still keeps it: signed out on another device, this Mac removed
from the account, or kept from an older build. KIFF then refuses every read with 401, and
tafs cloud says "KIFF did not accept this sign-in".

- **The first refused read ends it** (`SessionWatch`, `WatchedTransport`). Every read the signed-in
  window makes, to KIFF or tafs cloud, goes through the session's watch. The first read sent with
  the stored session that's refused with 401 forgets the session, as Sign out does, and sign-in
  opens, once (`SignInModel.sessionRefused`).
- **Nothing is ended at KIFF,** which ended it already.
- **Only reads count.** A request that changes something can be refused for its own signature,
  which says nothing about the session.
- **A newer session stays:** a read refused for a session the Mac has since replaced (a new
  pairing) changes nothing.
- **No screen says "unauthorized".** Until the window ends, Needs you says "Signed out of KIFF.
  Sign in again." (`error.signed_out`), never KIFF's code.
- **Account never says Signed in** while reads are refused, since the signed-in window ends.

The iPad does the same (kiff/tafs#1307, `AppModel.refresh`).

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
The offer for one attempt (`SecurityKeyPairing.offer`): the proof with the credential, none
without it, none for a software key, a closed sheet pairing without the key, and the claim's body
as KIFF reads it. On a Mac, a real P-256 key's credential against CryptoKit's SPKI; the screen
(`KeyPairingScreenTests`): the PIN sheet, the QR naming the key, the claim proving it, the id kept
only once claimed and forgotten at sign-out; a wrong PIN and no key kept in the sheet; the sheet
closed; approvals off; a cancelled pairing; two asks in a row both resuming; a store refusing the
key's id leaving the new session standing; and screenshots `pairing-pin-sheet-en`,
`pairing-pin-sheet-fr` and `pairing-key-en`.

## The screens

A Mac with no session opens on sign-in (`SignInView`, driven by `SignInModel`): the whole window
in two halves, as the iPad's regular width, with very little text. What each half shows, and
when the phone's code starts by itself, is `SignInPlan` (Core).

| Half | What it shows |
|---|---|
| **Left: Sign in with KIFF** | An illustration, **Sign in with KIFF** and **Continue**. After Continue: what signing in does, the browser's code to check, that the Mac is waiting, the agreement with its Terms and Privacy policy links, and **Cancel**. KIFF's page opens by itself. |
| **Right: Sign in with your phone** (on `raised`) | An illustration with the title, the QR, **Scan with tafs**, where to scan it on the phone (Account → Devices → Add a device), and a panel: **Your code**, the 6-character check code, then this Mac's name, and that it's waiting for the phone. |

- **The QR is shown as the window opens**, with nothing to press (`SignInModel.showPhoneCode`).
- **It's renewed silently.** A code lasts at most 5 minutes; when it runs out, a new one with a
  new nonce takes its place, with no message and nothing to press.
- **No prompt.** Showing and renewing the code signs only the claim's proof with the device key
  (`Signing.claimProof`), which is made with no access control: no Touch ID, no password.
  - The one exception is this Mac's security key, once passkey approvals are on: its PIN sheet
    is a prompt, so the code is then shown on **Continue** and isn't renewed by itself.
- **The check code comes first**, before this Mac's name. The name is the one this Mac gives
  itself in the QR, shown as its own claim, which the phone shows too. There's no "Show the
  code" (Windows only).
- **One sign-in at a time.** Continue on KIFF's half stops the phone's code; the phone's half then
  offers **Continue** to show it again, which stops the browser's wait. Cancel on KIFF's half brings
  the code back by itself.
- **A failure** says why in its own half, with **Try again**. A failed pairing isn't started again
  by itself.
- **A view-only Mac adding itself** sees the phone's half alone, titled "Add this Mac with your
  phone", with **Cancel**.
- **The illustrations** are shapes only, never a letter, number or word, and hidden from
  VoiceOver. KIFF's half draws the approved board 1, first run (`Illustration.firstRun`,
  docs/window.md › Illustrations); the phone's half and Connected keep `SignInArt`, shapes and SF
  Symbols, which no board covers. Every word is a shared line: `sign_in.*` and lines already used.
- **Connected.** A session just gained, on either path, is celebrated once over home
  (`ConnectedView`): "You're connected. Let's build great things together." and **Let's go**
  (`sign_in.connected`, `connected_line`, `lets_go`). A session kept from the last launch isn't.
- **Only KIFF's page is ever opened**: `https`, on `kiff.dev`. Any other address in the answer is ignored.
- **Cancel** stops the waiting, and a late answer to a cancelled attempt is dropped.
- **The QR code** (`QRCode`) is the pairing text as bytes with error correction M. A test reads
  it back from the image, as a phone's camera would, and from the drawn window.
- **The session** goes to the Keychain as soon as it is handed over, and the next launch opens
  signed in.

`scripts/test.sh pairing` writes the window to `build/screenshots/sign-in-{en,fr}.png` (the two
halves, the QR on load), `sign-in-browser-*`, `sign-in-adding-*` (a Mac adding itself) and
`sign-in-connected-*`, in English and French. Its tests (`SignInPlanTests`, `SignInScreenTests`):
the QR on load and its renewal each sign only the claim with the device key, with no PIN sheet; no
pairing source names `LocalAuthentication`, `LAContext` or `SecAccessControl`; nothing starts by
itself on a still picture, while signed in or after a failure; the QR reads back off the drawn
window, beside the two halves' colours; and the check code comes before the name, in English and
French.

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

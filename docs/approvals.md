# Needs you: held calls and answers

When a taf's call goes past its Card, KIFF holds it and asks the person. This page says how
this app reads those calls and answers them. The keys are in [signing.md](signing.md).

## What is drawn

`AccountClient.heldCalls()` reads `GET /v1/me/card-exceptions?status=held`. A held call's
words are KIFF's (`title`, `reason_text`) and the taf's own (`taf_about`, `taf_reason`),
drawn as sent. The app never words a hold itself.

- The taf's own words are unsigned and may come from a customer's text. They are drawn plain
  and never decide anything.
- Words that aren't text are left out. A hold without its id or its time makes the whole
  answer unreadable: a hold is never dropped silently.
- **A call's name** (`HeldCall.summary`), on its card and in the sidebar, is the iPad's
  `proposed.summary` (`KIFFMapping.held`, `KIFFMapping.swift:283-285`): KIFF's title, with the
  action in words when the title doesn't say it (`CallNames.says`: "Write Stripe API data ·
  refund payment", while "Refund a payment" stays alone); the action in words without a title
  ("refund payment", past a server's prefix and the grant's own, `CallNames.toolWords`); then
  what the call is on (`entity_id`) for a call KIFF keeps no arguments for. A gateway call is
  filed under its tool call's id, which says nothing, so it has none.
- **The amount** is KIFF's own number: the first of the call's `parameters` that KIFF names a
  unit for in `parameter_units`, written in the app's language ("€640"). A number KIFF names
  no unit for is never shown as money, and a call without one shows none.

## Answers

Every answer is a signature over `kiff.answer.v1`: the account, the hold's id, the answer,
the next step, the note's hash, the hold's accounting version, and the time. The version
makes an answer count only for the hold as the person saw it.

| Answer | Grants authority? | Who signs on a Mac |
|---|---|---|
| **Refuse** (`reject`) | No: it takes authority away | The device key, once the person confirms with Touch ID or the Mac's password. Any signed-in Mac may refuse. |
| **Approve once** (`approve-once`) | Yes | **This Mac's security key** (`PasskeySession.approveOnce`, below), on the security key's route. Without a key, the phone. |
| **Extra room** (`change-card`) | Yes | The phone, for now. KIFF takes it from the security key as it takes Approve once; it comes with Allow from now on. |

- **A Mac without a Secure Enclave never signs an approval.** `ApprovalRoute.of` says where
  an approval goes; KIFF also refuses that Mac's key on every route that grants authority.
- **A refusal is not sent** without the device key, without the hold's accounting version,
  or with a next step that isn't one of the hold's own.
- **A refusal is confirmed before it's signed**, as the iPad's `answer(_:with:)` signs with
  `signer.sign(_:reason:)` (`AppModel.swift:2917-2990`): after the checks above, the person
  confirms with Touch ID or the Mac's login password (`.deviceOwnerAuthentication`, which every
  Mac has), prompted "Answer {summary}" (`needs_you.prompt.answer`). A prompt the person
  closed keeps the call and says nothing was approved
  (`approval.cancelled_nothing_approved_request_kept`); any other failure says it wasn't sent
  (`common.not_sent_unconfirmed`). Neither signs nor sends. Those words show as they are:
  only KIFF's own refusal reads "KIFF didn't take the answer: …" (`needs_you.refused.other`), as
  the iPad's `lastError` (`AppModel.swift:2972-2979` against `:2994`).
  - **Mac difference:** the summary is the call's title, else its action, as its card shows
    it. The iPad's own naming (`KIFFMapping.says`, `KIFFMapping.swift:58-80`, and the entity
    for a call without arguments) isn't ported yet.

**Approve once on the security key** (kiff/cloud's `checkPasskeyAnswer`, `mandate_exceptions.go`): a session that
approves with this Mac's own passkey answers `approve-once` with that passkey's assertion in place of a device key's
signature. The card's **Approve once** (`needs_you.approve_once`, the shared primary button, above Refuse) shows only
where this Mac has its key on the security key's route, for a call KIFF says can be approved once
(`can_approve_once`) and that carries its accounting version. A click opens the PIN sheet, named as the iPad's prompt
("Answer {summary}", `needs_you.prompt.answer`), and then:
- **The message:** one fresh assertion over the answer's `kiff.answer.v1` (the account, the hold, `approve-once`, no
  next step, no note, the hold's accounting version, and `signed_at` now, RFC 3339 to the second, within KIFF's
  5 minutes). The challenge is `base64url(sha256(message))`, as for any of the key's approvals
  (`PasskeyApprover.answer`, in the same file as the request's: the signing stays private).
- **The request:** `POST /v1/me/card-exceptions/{id}/approve-once` with
  `{"signature":{"passkey":{"credential_id","client_data_json","authenticator_data","signature"},"signed_at":"…"}}`,
  the session's bearer and no `KIFF-Passkey-Assertion` header. Never the device key's signature, never a window: one
  approval for this one call. KIFF checks that the passkey is the one this Mac's pairing registered
  (`passkey_not_this_device` otherwise), and that it isn't synced.
- **Refused here first, with nothing asked of the key:** a call KIFF says can't be approved once, one without its
  accounting version, or an answer that grants nothing (a refusal is the device key's: `PasskeyRefusal.notAnApproval`).
- **Then:** the list is read again (KIFF's list is the truth). A closed sheet sends nothing and says nothing; **Approve
  on your phone instead** says to approve on another device; KIFF's refusal is the card's line, "KIFF didn't take the
  answer: {why}".

Extra room, next steps and Allow from now on come in their own pull request.

## Nothing is approved at planque from this Mac

This Mac signs two kinds of request at planque. The first is its own enrolment
(`PlanqueClient.routes`), armed only inside Coach's Start after its approval and cleared when it
ends. The second is ending a connection (`PlanqueClient.disconnect`), and only on a Touch ID Mac
(below). It never calls a grant's `approve`, `confirm`, `connect-fresh` or key route.
`send` refuses any path but the enrolment before anything is signed or sent, and
`PlanqueRoutesTests` pins it:
- `send`'s list of routes is only the enrolment, and it is one POST, signed once;
- the one grant route is `DELETE /v1/accounts/{tenant}/grants/{id}`: one request, no body and no
  `Content-Type`, signed v1 once (`t=…,v1=…,d=dev_…`) over the empty body's hash, by a signer
  passed with the call;
- no file under `Sources` names `/approve`, `/confirm`, `/connect-fresh`, a path under a grant or a
  POST to the grants; `grants/` is named once, in the DELETE's path;
- the client is made in one place and its own signer is armed only around the enrolment: the
  DELETE never arms it;
- the DELETE is called from one place (`ConnectionsSource`), and only after Touch ID
  (`ConnectionEnding.end`).

The grants proof (`grantsReadProof`) is a read: it signs `GET …/grants` and nothing else.

### Ending access with Touch ID

The owner's decision (22 Nov): ending access is signed here on a Mac with Touch ID, and only
ending access. This covers **Remove access**, **Cancel the request**, **Cancel the sign-in** and
**Clear** (the removed tafs' connections), on a connection's row and on its page. It works as the
iPad's `disconnect(grantID:)` and `clearRemovedConnections`, and as Windows' `EndAsync`
(`ConnectionEnding`, `ConnectAppsModel.disconnect`, `clear`):

1. **The route** (`ConnectionEnding.route`). It is Touch ID only when the session's device key is
   in the Secure Enclave (`AccountClient.keyStore == "enclave"`, from `SigningKey.keyStore`) **and**
   `LAContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` is true now. Anything
   else goes to the phone: a software key, a Mac without Touch ID, Touch ID not set up or locked
   out. That Mac asks nothing, sends nothing and shows "This device can't approve. Approve on
   another device signed in to your account." (`approval.device_can_not_approve_approve`), as
   before. planque and KIFF would take a software key's DELETE too (a safe route takes any device
   key), so this rule is the app's own.
2. **The question first**, the iPad's (`GateQuestion`). Then **Touch ID alone** (`TouchIDOnly`):
   `.deviceOwnerAuthenticationWithBiometrics` with `localizedFallbackTitle = ""`, so there's no
   password button. Its reason is the question's title ("Remove access to Stripe for Rae?",
   "Clear 2 connections from removed tafs?"). It is never `.deviceOwnerAuthentication` and never
   `NeedsYouModel.confirmOwner`, which let the Mac's password in. A closed prompt, or its fallback,
   counts as closed. "Approve on your phone instead" (`approval.security_key.on_phone`) shows beside
   the action.
3. **Then planque's DELETE**, one per connection, signed by the device key with no prompt. The key
   has no access control (`DeviceKey`): the Touch ID check is the confirmation, as Windows Hello is
   before the TPM key. Clear asks Touch ID once for all of them. A refusal is counted and the next
   connection is still tried. Once the session changes, nothing more is sent.
4. **Then the connections and the removed tafs are read again.** What's said:
   - Disconnect says nothing when the prompt was closed (the iPad's choice; Windows says "not done").
     A refusal says `connect.not_disconnected` ("Access not removed. {why}").
   - Clear says "Not done: it wasn't confirmed." (`common.not_done_unconfirmed`) when the prompt was
     closed. Otherwise it says how it went (`connect.clear_removed.cleared`, `connect.kept.for_card(s)`,
     `connect.could_not_cleared_try_again`).

The iPad also signs `tafs.disconnect.v1|{tenant}|{ids}` as its Face ID step and then throws the
signature away. This Mac doesn't: its device key never prompts, so that signature would prove
nothing. Windows doesn't sign it either.

Nothing that grants access changes. Connecting, **Sign in again**, **Replace the key**, a key, and
every approval and confirmation stay the phone's or the security key's, on every Mac.

**Account › How tafs works** says where approvals are signed (`ApprovalRoute.howItWorksKey`).
Only the security key's route keeps "Your answers are signed on this Mac."
(`sign_in.every_action_taf_takes_goes`). Every other Mac, which is every Mac while
`macPasskeyApprovals` is off, says "Your approvals are signed on your phone."
(`sign_in.every_action_taf_takes_goes_view`), as a computer that only views.

## Did this happen?

As the iPad's `DidThisHappenCard` and `loadUnproven` (`NeedsYouView.swift:22-23, 95-136`,
`AppModel.swift:2125-2136`, `KIFFClient.swift:1625-1670`): KIFF's money calls whose outcome
it can't prove (`GET /v1/me/did-this-happen`), read when Needs you opens, only for someone
who answers held calls (KIFF's `holds.answer`; a KIFF that doesn't say leaves it to KIFF). A
read that fails keeps the list.

- Each is drawn above the held calls, edged in amber: "Did this happen?", KIFF's sentence for
  the call (else its title, and its amount), and KIFF's words for why it asks.
- **The answer is signed like an approval**, which this Mac can't do yet. So for someone who
  answers held calls, the card says to approve on another device
  (`approval.device_can_not_approve_approve`, the iPad's `Biometry.short` where an approval
  can't be made), as the held calls do, and has no Yes or No. The line shows only on a Mac
  that approves elsewhere (`.phoneOrPasskey`), where the iPad's `ApprovalGate` would show
  `ApprovalNotReady`; a Mac with its own approval key shows neither until its Yes or No is ported.
- An amount with no unit is drawn whole, "725 (no currency)", as the iPad's `Money` keeps it.
- "Nothing waiting" shows only when there's nothing to say about either.

## Your step

As the iPad's `YourStepCard`, `answerYourStep`, `showSteps` and `drop`
(`YourStepCard.swift:6-46`, `AppModel.swift:6816-6820, 6832-6834, 6843-6896, 6898-6903` at
`d14217f1`, `TafsCloud+YourStep.swift`, `KIFFClient.swift:895-967`): the steps the tafs handed their owner, from Home's `your_steps`
(each read strictly: one that doesn't read makes Home unreadable, as on the iPad), drawn
first on Needs you, oldest first.

- Each card: tafs cloud's title, the taf, what to do (16 semibold) and why; the vendor's page
  as an outlined button only as tafs cloud vouched for it (https, its host apart and the
  link's own, and the button's words), with the host under it; then Done and Skip, in tafs
  cloud's words, only for someone who answers the account's held calls (KIFF's `holds.answer`)
  with a device key; else answering says to answer in KIFF, or to sign in again.
- **Answering** reads the hand-off from KIFF first (`GET /v1/me/handoffs/{id}`); one KIFF no
  longer waits on isn't sent ("This step was already answered or has ended."). The answer,
  `done` or `skipped`, is signed with the device key over `kiff.handoff.v1` (tenant, hand-off,
  answer, version, the time to the millisecond, never the same twice) **after the person
  confirms with Touch ID or the Mac's password**, as the iPad's `sign(_:reason:)` asks for
  Face ID or the passcode; the prompt is tafs cloud's words, "Done · {what}". It's never the
  approval key. A closed prompt sends nothing and keeps the step ("Cancelled, so nothing was
  approved"); any other failure says it wasn't confirmed. A 409 says it ended. A refusal says
  KIFF's `error`, else its `reason`, in the iPad's words, else "KIFF didn't take the answer"
  with the app's own line for the status (a 401 is "Signed out of KIFF", as the iPad's
  `KIFFError.unauthorized`): never KIFF's code.
- An answer on its way stops at sign-out: nothing is signed or posted for a session that
  ended.
- An answered or ended step leaves the list at once, and stays off while Home still lists it;
  the lists are then read again.

## Passkeys on macOS 12

This app never holds an approval key, Touch ID or not. A Mac with Touch ID uses it only to end
access (above, "Ending access with Touch ID"). An approval on this Mac can be the person's
passkey: a USB security key signing the exact request, sent as
`KIFF-Passkey-Assertion`. The route is the public spec's "A Mac without Touch ID, and Linux", in
[How a computer approves with a passkey](https://github.com/kiff/tafs/blob/main/docs/computer-passkeys.md);
KIFF's checks are as `docs/secure-connection.md` describes them. Anything else is
approved on the phone ("Approve on your phone"). macOS 12 has no system cross-device passkey (it
came in macOS 13), and its platform authenticator needs Touch ID, so neither is used.

**A security key goes with its computer.** It's registered through pairing, and KIFF lists it
with that computer ("Goes with its computer", no Remove of its own): signing the computer out in
Devices removes it. The key itself can be plugged in elsewhere, so its PIN is asked for each
approval.

**On since kiff/cloud#96** (`Features.macPasskeyApprovals = true`; the PM's decision (i), 22 Nov): a Mac
whose device key is in software (no Secure Enclave) pairs its security key too, with
`kind: passkey`, `key_store: software`, its credential in the QR and `credential_proof` always, and
the key is kept only when KIFF's claim answers `approval_mode: passkey`. Then that key alone
approves for this Mac: the device key grants nothing.

## Approving with the security key (`KeyAct`, `PasskeySession.approved`)

Each act this Mac draws whose whole request the app writes is approved by one fresh assertion of
the key over that request's `kiff.request.v1` (UP, and UV from its PIN), sent with
`KIFF-Passkey-Assertion` only: never a window, never two requests under one, never the device
key's signature. The PIN sheet names the act first, in the iPad's own words for it:

| Act | Request | Named |
|---|---|---|
| Signing another device out | `DELETE /v1/me/devices/{id}` | "Sign {device} out of your account" |
| The account's time zone | `PUT /v1/me/time-zone`, the device key's exact bytes | "Set your account's time zone to {zone}" |
| Resume after a halt | `POST /v1/agents/{agent}/resume` or `/v1/resume`, `{}`; then tafs cloud's `DELETE …/halt` | "Resume {taf}", "Resume all your tafs" |
| Remove for good | the key first, then each Card revoked, then tafs cloud's `DELETE /v1/tafs/{id}` with that assertion (`TafRemoval`) | "Remove {taf} for good" |

The sheet's lead is the shared line "This needs your security key: {act}. Plug it in, then touch
it and enter its PIN." (`approval.security_key.before`, tafs#1718). **Approve on your phone
instead** (`on_phone`) is in the sheet for every act on the key: it sends nothing and hands nothing
to the phone, and the act's line then says to approve on another device (`ApproveOnPhone`). Where
this Mac has no key, the approve-elsewhere line first says what a security key is
(`none_paired`). A closed sheet sends nothing and says nothing. **Revoke** needs no key: it's the iPad's plain
session call (`POST /v1/me/mandates/{id}/revoke`), and a view-only Mac gets the shared line instead.
Sharing and groups come with their own screens ("People and sharing"). A held call's **Approve once** is the
key's too (above, "Answers"); its other answers that grant authority, and planque's acts, stay the phone's. The
one exception is planque's disconnect, which takes access away: on a Touch ID Mac it is signed here
(above, "Ending access with Touch ID").

**In Core now** (`PasskeyApproval.swift`), as Windows' `PasskeyApprover`, `RequestsTogether` and
`PasskeyRegistration`:
- **The message:** a request's `kiff.request.v1` (the body's hash, a `signed_at` from
  `SigningTime.next()`, never the same twice), or two requests' `kiff.requests.v1` with the two
  hashes sorted.
- **`clientDataJSON`**, which this app writes, as Windows does over raw CTAP2:
  `{"type":"webauthn.get","challenge":base64url(sha256(message)),"origin":"https://kiff.dev","crossOrigin":false}`.
  The security key is given its SHA-256 (`clientDataHash`), never the JSON.
- **Checked here before sending, whatever the key says:** rpIdHash is `sha256("kiff.dev")`; UP and
  UV are set (the key's PIN was checked); the credential is the one asked for; and the passkey
  isn't a synced one (BE and BS are 0, as Windows refuses). A USB key reports neither, and can
  still be used from another computer with its PIN: the check refuses a synced passkey, nothing
  more. Each is its own refusal (`PasskeyRefusal`).
- **Only two ways in:** `approve` for one request and `RequestsTogether.approve` for the pair,
  each with the `signed_at` that went into its message. The signing itself is private.
- **The header:** `t=<signed_at>,a=<base64url of {credential_id, client_data_json,
  authenticator_data, signature}>`; for the pair, each request's header adds
  `with=sha256:<the other request's hash>`.
- **A new credential** (`PasskeyRegistration.read`): its id and its ES256 COSE key as SPKI DER.
  Another algorithm or curve, a point off P-256, another RP, BE or BS, or no verification is
  refused. Its creation's challenge is the pairing's
  `base64url(sha256("kiff.passkey.pair.v1\n<nonce>\n<device key>"))`.
- **`ApprovalRoute.passkey`:** the route of a Mac with a registered key.
- **Hashing is passed in** (`sha256`): Core builds on Linux, and the app gives CryptoKit's
  (`PasskeyCrypto`).
- **A new key's point is checked on P-256 by the curve's equation** (`P256Curve.contains`:
  `y² ≡ x³ − 3x + b (mod p)`, both coordinates below `p`), in Core, so Linux tests it too.
  CryptoKit's key init isn't used as the check: on macOS it takes a point off the curve.

**The security key** (`FidoKey`, in the app), over libfido2: CTAP2 over USB HID.
- **Built from pinned source** by `scripts/fido.sh`, never a prebuilt binary: libfido2 1.17.0,
  libcbor 0.13.0 and OpenSSL 3.5.9's libcrypto, each checked against its pinned SHA-256 before
  it's unpacked, as static libraries for each architecture ([building.md](building.md)). zlib is
  the SDK's. Their three licences ship in the app (`Contents/Resources/licenses/`).
- **Only two requests reach the key:** `fido_dev_get_assert` and `fido_dev_make_cred`, and its PIN
  retry count is read. It's never reset, its PIN is never set or changed, and its credentials are
  never listed or deleted.
- **An assertion** (`SecurityKeyAssertionAsk`) is kiff.dev, the `clientDataHash` this app computed,
  the one credential this Mac approves with in the allow list, and presence required. **A new
  credential** (`SecurityKeyCredentialAsk`) is ES256 on kiff.dev ("KIFF"), not discoverable,
  with Windows' two minutes to answer.
- **UV comes from the PIN:** the key is always asked with its PIN, so the `uv` option is left out
  (`SecurityKeyVerification`), as some CTAP2.0 keys refuse it alongside a PIN token. Core still
  requires the UV flag. Without a PIN, the key isn't asked at all.
- **Core checks what comes back**, whatever libfido2 says: the raw authenticator data
  (`fido_assert_authdata_raw_ptr`, not the CBOR-wrapped one) goes through `PasskeyApprover`'s
  checks, and the DER signature is sent as the key gave it.
- **The PIN** (`SecurityKeyPIN`) is one buffer the app owns: made from the bytes typed, which it
  clears; handed to libfido2 once as a C string; then cleared (`memset_s`) and freed, whatever
  happens. One that's never handed over is cleared too. It's never kept, logged or sent. A PIN
  under 4 characters, over 63 bytes or with a NUL is refused before the key is asked.
- **Which key:** exactly one FIDO2 key with a PIN set. None, several, a U2F-only key or a key
  without a PIN is refused before anything is asked of it (`SecurityKeyFailure`).
- **Its failures, by libfido2's code** (`SecurityKeyFailure.of`): a wrong PIN with the tries left
  (`triesLeft()` reads them before asking), a blocked key (no tries left), three wrong in a row
  (unplug it and plug it in again), another key than this Mac's, not touched in time, refused or
  cancelled at the key, and unplugged. A cancelled task cancels the request at the key.

**Registering the key through pairing** (`SecurityKeyPairing`, part 3; the screen, part 5), as
Windows' own passkey (`PairingAttempt`, `PairingOffer`, `PairingClaim`, `WindowsHello.CreateAsync`).
The pairing screen asks the key through the PIN sheet only while passkey approvals are on
([pairing.md](pairing.md)); switched off it asks the key nothing:
- **The credential:** `make` asks the key for one with the `clientDataJSON` this app writes,
  `{"type":"webauthn.create","challenge":…,"origin":"https://kiff.dev","crossOrigin":false}`, its
  user id sha256 of the device key (the same on every attempt), and this Mac's name. What comes
  back is checked as an approval's is, then as a new credential (`PasskeyRegistration.read`):
  ES256 on P-256, an id of 1 to 1023 bytes, and not the device key.
- **The challenge:** with the creation proof on (`Features.macPairingPasskeyProof`, **on**, as
  KIFF requires it on a passkey computer's claim from 1 Dec 2026), the pairing's `base64url(sha256("kiff.passkey.pair.v1\n<nonce>\n<device key>"))`,
  so each attempt makes the credential again, and one made for another pairing is refused before
  the QR is shown. Without it, 32 random bytes, and a new code keeps the last credential, so the
  key isn't asked again.
- **Attestation `none`,** the only format KIFF takes: exactly `{fmt: "none", attStmt: {}, authData}`,
  as Windows asks for none. The key's own statement and certificate, which name its model, never
  leave this Mac.
- **The QR** names it as `credential {id, public_key}`, only with `kind: "passkey"`, never beside
  an approval key or a software device key ([pairing.md](pairing.md)). The check code covers its
  key in the approval key's place.
- **The claim** carries `credential_proof {client_data_json, attestation_object}` with the proof on.
- **A refused credential, a key not touched or declined, or the PIN sheet closed,** pairs without
  one: this Mac then approves on the phone, as Windows pairs when Windows Hello is closed. No key,
  a wrong PIN or a blocked key is said in the PIN sheet, which stays open to try again.
- **One attempt's offer** (`SecurityKeyPairing.offer`): the payload, the credential it names, and
  the claim's proof, only with the proof on and a credential in the QR. A software device key is
  never asked for one.
- **Kept:** only the credential id (`SecurityKeyStore`), in the Keychain beside the session, saved
  once the pairing is claimed and never before. A pairing that names no key forgets an earlier one.
  Signing this Mac out forgets it, as signing it out in Devices removes the key at KIFF.

**The PIN sheet and Start Coach on the key's route** (part 4). Still off: nothing gives the
route while `Features.macPasskeyApprovals` is off.
- **The route** (`ApprovalRoute.of(_:securityKey:)`): `.passkey` for a passkey session whose
  security key goes with this Mac (`SecurityKeyStore`), once the switch is on; else the phone.
- **The PIN sheet** (`PINSheet`, `PINSheetModel`): "Approve with your security key", what it asks
  (it's asked each time and never stored), the tries left when the key says (read before the PIN
  is asked), the PIN field, Cancel (Esc) and Approve; then "Touch your security key." while the
  key waits. Each failure says its shared line (`SecurityKeyWords`, `approval.security_key.*`):
  a wrong PIN with the tries left, a PIN too short or too long, three in a row, a locked key, no
  PIN set, no key, several keys, a key that can't check a PIN, another key, not touched in time,
  the key's decline (`not_allowed`), unplugged, and anything else. **Authenticator data KIFF would
  refuse, no user verification among them, says the key couldn't sign (`failed`), never the
  key's decline.** The sheet stays open to try again, but for a locked key.
- **The PIN never becomes a Swift `String`:** `PINReader` reads the secure field's own storage
  straight into UTF-8 bytes (CoreFoundation's `CFStringGetBytes`) and empties the field at once.
  The bytes become one `SecurityKeyPIN`, which clears them, is handed to the key once, then is
  cleared and freed, whatever the key answered. What's left: AppKit's field editor held the
  characters while they were typed, and the app can't zero that memory; it's emptied, never
  copied.
- **Start Coach** ([coach.md](coach.md), "Starting Coach"): Setup's draft approved by the key
  through the sheet, sent as `KIFF-Passkey-Assertion` (`PasskeySession`), as Windows' passkey
  route.
- **The key's name** for its credential, when it's made in pairing: the session's email when it's
  known, else this Mac's name (`SecurityKeyPairing.userName`).

**Before the switch is turned on:**
1. **The origin** for a computer that writes its own client data (`https://kiff.dev`), agreed
   with KIFF's side.
2. **Confirmed on a real Mac:** an unsigned app reads a FIDO HID device on macOS 12 without an
   Input Monitoring prompt. libfido2 opens the key's FIDO interface (usage page `0xF1D0`), which
   isn't a keyboard, so none is expected.
3. **One real pairing end to end** with a USB security key on a macOS 12 Mac with a Secure
   Enclave: the PIN sheet, the key's touch, the phone's approval, and KIFF taking the claim's
   `credential_proof`. The screen and the proof are in (part 5); a real key can't run in CI.
4. tafs cloud's first start's pair (`RequestsTogether` on the key), with the tools step.

## Tests

`scripts/test.sh approvals`: the hold as KIFF sends it, the answer's message line by line,
a step's message against KIFF's pinned vector (its signature checked on a Mac),
the refusal's exact body, each case where a refusal is not sent, and that a refusal's
signature verifies with the device key and is not an approval's.

## The Needs you screen

`NeedsYouView`, driven by `NeedsYouModel`, draws each held call as the iPad's
`HeldCallCard`, on a panel edged in amber (radius 18):

- **the taf**, by the KIFF agent the call is for: its coloured square and its name, or "A taf"
  when the list doesn't have it; and at the right **the time left, counting down every
  second** as a clock ("8:06 left", or "1:02:05 left"), then "expired";
- **the amount** in large rounded figures, when KIFF gives one, then KIFF's name for the call;
- **KIFF's reason on an amber pill**;
- "The taf says", then the taf's own words **in a box of their own**, apart from KIFF's and
  drawn plain;
- "Nothing is sent until you approve.";
- **Refuse**, as an outlined red button the card's width;
- on a Mac with no approval key, "This device can't approve. Approve on another device
  signed in to your account."

The title is the iPad's, large and rounded, with no count under it. With no call, "Nothing
needs you." and its hint sit on a panel.

After a refusal the list is read again from KIFF: its list is the truth, not the screen's.
A refusal KIFF doesn't take stays on the card with KIFF's reason, and the call stays listed.
A list that can't be read says so and is never shown as "Nothing needs you."

### Coach waiting (`CoachWaiting`, `CoachWaitingCard`, `SetAllAsideButton`)

Ported from the iPad's `TafsCloud+CoachWaiting.swift` and `NeedsYouView.swift:16-19, 484-600`.
A Coach chat paused on a card its person answers (an approval, a sign-in, questions, a
confirm) is listed by Home (`coach_waiting`), oldest first, and counted in Needs you.

- **Read** with each list read, leniently: only one with its chat (`session`) and both of
  tafs cloud's lines (`words.line`, `words.open`) is drawn; one that doesn't read, or a
  `coach_waiting` that isn't a list, is left out, never Home with it.
- **Drawn** after the steps, on a panel edged in amber: Coach's sparkle and tafs cloud's line
  ("Support: Coach is waiting for your approval since 09:12."), then **Open Coach**, for
  someone who may use Coach, which opens the Mac's Coach on that chat (on Coach alone with no
  chat). Before Coach is read, it opens on that chat once read.
- **Set aside**, an outlined button, only when tafs cloud sends its words (`words.set_aside`).
  The iPad also has a swipe; the button is its other way. **Set all aside**
  (`coach_waiting_clear`), above two or more, asks once in tafs cloud's words (its title names
  the count it ends), then ends every chat Home listed in one call. "Cancel" is the app's own
  (`common.cancel`) when tafs cloud sends no `no`.
- **Neither is signed.** Setting aside is tafs cloud's "not now", never an approval: the iPad
  signs nothing (`POST /v1/home/coach-waiting/{session}/set-aside`, or `…/set-aside` for all,
  the session escaped). Only this device's signed read of its connections goes with it
  (`Planque-Device-Signature`, the same no-prompt proof as Coach's thread read), so tafs cloud
  can withdraw a connection the chat asked for. So this Mac sends it as the iPad does.
- **One call per chat at a time:** a second click, or Set all aside over a chat already on its
  way, sends nothing. The row goes once tafs cloud says it ended; Coach leaves a chat shown
  that was set aside for a new conversation, and never opens on one by itself again this
  session; then the list is read again for its count. A refusal keeps the row and says tafs
  cloud's words above the chats.
- **The chat open in Coach** is left out of the rows and the count while Coach shows it.

### Needs you's count

The sidebar's number, the Overview's NEEDS YOU and the brief's link are the iPad's
`needsYouCount` (`AppModel.swift:73-84`, `NeedsYouCount`): tafs cloud's `needs_you.count` when
it sends one, less the steps answered here it still counts and the Coach chats left out; else
the app's own count of held calls, Card unit requests (`card_unit_exceptions`), steps, "Did
this happen?" and Coach's waiting chats. Its line is tafs cloud's words while they still say
what's counted, else "N need you." or "Nothing needs you.". What the brief doesn't show counts
Card unit requests and Coach's chats too, as the iPad's `briefNeedsYouLine` (`:2478-2483`).

`scripts/test.sh approvals` writes `build/screenshots/needs-you-*.png`, with
`needs-you-coach-waiting-en.png` and its `-dark` twin for Coach's waiting chats.

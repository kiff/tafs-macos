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
| **Approve once** (`approve-once`) | Yes | Touch ID's approval key on a Mac that has one. Otherwise the phone, or a passkey. |
| **Extra room** (`change-card`) | Yes | The same as Approve once. |

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

Approving with Touch ID, on the phone and with a passkey each arrive in their own pull request.

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

This app is for Macs without Touch ID, so it never holds an approval key. An approval on such a
Mac can be the person's passkey: a USB security key signing the exact request, sent as
`KIFF-Passkey-Assertion`. The route is the public spec's "A Mac without Touch ID, and Linux", in
[How a computer approves with a passkey](https://github.com/kiff/tafs/blob/main/docs/computer-passkeys.md)
(in review); KIFF's checks are as `docs/secure-connection.md` describes them. Anything else is
approved on the phone ("Approve on your phone"). macOS 12 has no system cross-device passkey (it
came in macOS 13), and its platform authenticator needs Touch ID, so neither is used.

**A security key goes with its computer.** It's registered through pairing, and KIFF lists it
with that computer ("Goes with its computer", no Remove of its own): signing the computer out in
Devices removes it. The key itself can be plugged in elsewhere, so its PIN is asked for each
approval.

**Off for now** (`Features.macPasskeyApprovals = false`): a switched-off `PasskeyApprover` refuses
before the security key is asked, and nothing gives `ApprovalRoute.passkey` yet.

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
- **Hashing is passed in** (`sha256`, and `isOnCurve` for a new key): Core builds on Linux. The app
  gives CryptoKit's (`PasskeyCrypto`).

**Next, each its own change:**
1. **The security key over libfido2**, behind `PasskeyAuthenticator`, on the review's conditions:
   - libfido2 and its CBOR and crypto libraries pinned, built from source in CI with their source
     checksums checked, never a prebuilt binary; their licence notices shipped;
   - only `make_cred` and `get_assert`, given the `clientDataHash` this app computes; never
     credential management, reset or enrolment;
   - the PIN asked in the app's own prompt for each approval, handed over once, its buffer zeroed;
     never kept, logged or sent; the tries left said, and a blocked key said to be blocked;
   - confirmed on a real Mac: an unsigned app reads a FIDO HID device on macOS 12 without an
     Input Monitoring prompt.
2. **Registering the key through pairing** (the public spec's pairing): the Mac makes the
   credential, shows the `kind: "passkey"` pairing QR naming it, the phone approves the pairing,
   and the claim proves it with `credential_proof`. The key then goes with this Mac: signing
   this Mac out in Devices removes it.
3. **Start Coach and the first start's pair** on `ApprovalRoute.passkey`, and the switch turned on
   once the public spec's route has merged.

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

`scripts/test.sh approvals` writes `build/screenshots/needs-you-*.png`.

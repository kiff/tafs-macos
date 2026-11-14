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

## Answers

Every answer is a signature over `kiff.answer.v1`: the account, the hold's id, the answer,
the next step, the note's hash, the hold's accounting version, and the time. The version
makes an answer count only for the hold as the person saw it.

| Answer | Grants authority? | Who signs on a Mac |
|---|---|---|
| **Refuse** (`reject`) | No: it takes authority away | The device key. Any signed-in Mac may refuse. |
| **Approve once** (`approve-once`) | Yes | Touch ID's approval key on a Mac that has one. Otherwise the phone, or a passkey. |
| **Extra room** (`change-card`) | Yes | The same as Approve once. |

- **A Mac without a Secure Enclave never signs an approval.** `ApprovalRoute.of` says where
  an approval goes; KIFF also refuses that Mac's key on every route that grants authority.
- **A refusal is not sent** without the device key, without the hold's accounting version,
  or with a next step that isn't one of the hold's own.

Approving with Touch ID, on the phone and with a passkey each arrive in their own pull request.

## Tests

`scripts/test.sh approvals`: the hold as KIFF sends it, the answer's message line by line,
the refusal's exact body, each case where a refusal is not sent, and that a refusal's
signature verifies with the device key and is not an approval's.

## The approval key (`ApprovalKey`)

The key that signs what grants authority on a Mac with Touch ID.

- **Only in the Secure Enclave.** There is no software stand-in: a Mac with no Secure
  Enclave, or with no fingerprint enrolled, has no approval key and approves on the phone or
  with a passkey.
- **Its own access control** is private-key use by the fingerprints enrolled when it was
  made: never the password, never a fingerprint enrolled later. The key checks the prompt
  itself, so code that skipped the prompt can't sign with it.
- **Every signature asks for Touch ID again.** No unlock given before is reused.
- **Changed fingerprints end it.** The kept key is forgotten and none takes its place by
  itself: a new one must be approved again by a device that can approve.
- **A software device key never approves**, even with an approval key beside it
  (`ApprovalMeans.of`).

It is not used by any screen yet. It has **not run on a Mac with Touch ID**: its tests cover
the rules above and a Mac that can't hold one.

## The Needs you screen

`NeedsYouView`, driven by `NeedsYouModel`, draws each held call as a card:

- KIFF's name for the call and its reason, as sent;
- "The taf says", then the taf's own words, apart from KIFF's and drawn plain;
- the time left, or "expired";
- "Nothing is sent until you approve.";
- **Refuse**;
- on a Mac with no approval key, "This device can't approve. Approve on another device
  signed in to your account."

After a refusal the list is read again from KIFF: its list is the truth, not the screen's.
A refusal KIFF doesn't take stays on the card with KIFF's reason, and the call stays listed.
A list that can't be read says so and is never shown as "Nothing needs you."

`scripts/test.sh approvals` writes `build/screenshots/needs-you-*.png`.

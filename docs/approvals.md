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

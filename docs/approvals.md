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
| **Extra room** (`change-card`) | Yes | **This Mac's security key** (`PasskeySession.extraRoom`), over a total approving once can't pass, for whoever manages the Cards. Without a key, the phone. |

- **A held step that fills a field in Chrome is never allowed from this Mac** (kiff/tafs `docs/chrome.md`: "never an
  allowing answer without its release"). Only the paired phone's own release opens a fill, and this Mac holds no approval
  key to make one. So a held call whose `browser` block carries `fill` or `sealed_fill` (`HeldCall.fillsInChrome`; any
  value but null, and a block that doesn't read counts as one) offers no Approve once and no Extra room. Asked directly,
  nothing is asked of the key or sent (`answerOnKey`). The card says "Approve on your phone instead", and Refuse stays.
  planque or KIFF refusing an allow without a release is the server's half, which every app relies on.

### Allow this from now on (`HoldAllow`, `AllowSheetView`)

The held card's third answer, as the iPad's (kiff/tafs `docs/allow-from-now-on.md`): a Card change so calls like this
one go on their own.
- **Offered** (`NeedsYouModel.offersAllow`) only:
  - once tafs cloud lists `holds.allow` in the account's capabilities (`Me.allowIsLive`; none listed, no button);
  - to someone who manages the Cards, on a Mac with its security key;
  - for a call whose taf tafs cloud holds;
  - on a hold every one of whose breaches a Card change can lift (`HoldAllow.allowable`). Never Coach's install, a Card
    unit request, or a fill in Chrome (that would skip the phone's release).
- **Read on the tap, never before:** tafs cloud's offer (`POST /v1/tafs/{id}/holds/{exception}/allow`, `{}` or
  `{"round":true}` for Round up), then KIFF's draft, read by this Mac itself. A `none` says tafs cloud's words, and
  nothing is signed.
- **Signed only when the draft is what was offered** (`HoldAllow.matches`, every term the iPad compares: actions, caps,
  scopes, states, next steps, totals with their window, measure and per-item parameter, what happens past a limit,
  holders, where it applies, and when it starts and ends; no Card retired or added; this call's agent, and from this
  hold when KIFF says). Each Card in force the draft shows must be the one it revises: when KIFF names it
  (`current.id`), the two must agree, for a changed Card and one marked unchanged alike. KIFF sends no `current.id`
  today, so this holds until it does. Otherwise "This change isn't what was offered", and nothing is signed.
- **And only when every key of its Cards is one the check reads** (`HoldAllow.keysKnown`, over the draft's bytes as
  KIFF sent them, `AccountClient.draftRaw`): a term KIFF adds later is never signed unseen. The keys are kiff/tafs
  `vectors/agent-draft-keys.json`'s, by object (a Card, the Card in force, a grant, a per-call cap, a total, a scope, a
  `quantity_of`). A key whose value is null sets nothing. A Card's `id`, when sent, is the Card it revises, and a
  `quantity_of` says what its `quantity` says. The vector's cases, over KIFF's own draft pinned in kiff/tafs
  `contracts/kiff-agent-draft-from-hold.json`, are this Mac's tests, as they are the iPad's, Android's and tafs cloud's.
- **One approval on the security key** (`KeyAct.confirmDraft`): KIFF's plain draft confirm at the version this Mac read,
  the same request as installing a tried version.
- **The held call itself:** KIFF answers a held call inside a confirm only for Coach's install (`confirm_hold.go`), so
  the confirm never names it. With "Let this one go out too" on, Needs you reads again once the Card has changed, and
  the call, if it's still waiting and can be approved once, gets its own Approve once on the key, named "Answer
  {summary}". Otherwise its card stays with its own answers. Nothing is shown as sent that KIFF didn't take.

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
  the iPad's `lastError` (`AppModel.swift:2972-2979` against `:2994`). Its why is never KIFF's
  code: a reason the iPad names (`refusalWords`: `self_review`, the approver rules, …) in its
  words, else the app's line for the status, as the iPad's `KIFFError.server` reads through
  `PlainError.words(status:)` (`StepRefusal.plainKey`). The same for Approve once, Extra room
  and "Did this happen?" (`answerRefusedWords`).
  - **Mac difference:** the summary is the call's title, else its action, as its card shows
    it. The iPad's own naming (`KIFFMapping.says`, `KIFFMapping.swift:58-80`, and the entity
    for a call without arguments) isn't ported yet.
- **The paused run goes on at once** (`HeldContinue`, as the iPad's `continueHeld`, kiff/tafs#206, and Windows'): once
  KIFF takes any answer (Refuse, Approve once, Extra room), tafs cloud is asked to continue that taf's run, `POST
  /v1/tafs/{taf}/holds/{hold}/continue`, the taf found by the call's agent in Home (`NeedsYouModel.tafOf`), then the list
  is read again. A refusal isn't swallowed: a run that had already ended says so at the top of Needs you, in tafs cloud's
  words (`run_ended`), and another refusal, or tafs cloud not reached, says what didn't go through and why. A run KIFF's
  alert continued first answers 409 (`not_paused`): it went on, so nothing is said. KIFF's alert and the hold's expiry
  still continue a run this missed. An agent tafs doesn't run has no run to continue, so nothing is asked.

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

**Extra room** (`change-card`, the iPad's `answer(_:with: .extraRoom)`, kiff/tafs#211 6.13) is the same request with
`change-card` in the message and the path, `POST /v1/me/card-exceptions/{id}/change-card`. It's offered over a total
approving once can't pass (KIFF's `can_approve_once` false, so that isn't asked; the accounting version is), to someone
who manages the Cards (KIFF's `cards.manage`), on a Mac with its key. **Its button** is the shared primary one
under the over-total line, "Extra room" (`needs_you.extra_room`, tafs#1747, a plain word beside the iPad's "Extra
room with {biometry}"), with the key's mark; its PIN sheet names the call.

**Over a total**, as the iPad's: the card says approving once can't pass it, in the words for whoever manages the Cards
("Extra room lets only this call through", `needs_you.over_total_manager`) or for anyone else ("Someone who manages
the Cards can give it extra room, or you can refuse it", `needs_you.over_total`).

**Next steps**, as the iPad's: each of the call's `next_steps` is an outlined button in its own words, above Refuse. It
refuses the call with that step for the taf, signed by the device key once the person confirms, as Refuse is (a
refusal takes authority away: never the security key's). Only the call's own steps are sent (`not_a_next_step`).

Allow from now on comes in its own pull request.

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
- no file names any grant's sub-route (`/key`, `/approve`, `/confirm`, `/connect-fresh`,
  `/sign-in`, `/tools` and the rest of planque's), however a path is put together, and every line
  of code that names `/v1/accounts/` or `/grants` is one of a fixed few: the enrolment's root, the
  grants read, the DELETE's path, and KIFF's read of a taf's shares;
- the client is made in one place and its own signer is armed only around the enrolment: the
  DELETE never arms it;
- the DELETE is called from one place (`ConnectionsSource`), and only after Touch ID
  (`ConnectionEnding.end`).

The grants proof (`grantsReadProof`) is a read: it signs `GET …/grants` and nothing else.

### Ending access with Touch ID

The owner's decision (22 Nov): ending access is signed here on a Mac with Touch ID. **The same check confirms a
change to the account's groups** (docs/account.md › People & groups): the ending key signs the
iPad's `tafs.people.v1|{tenant}|{what}` there, then KIFF's group request goes signed by the device key. Adding someone
or changing their role is the exception: it grants access, so it goes on the security key, as sharing does (`KeyAct.setMember`). What follows
is written for ending access; groups take the same route, key and Touch ID. This covers **Remove access**, **Cancel the request**, **Cancel the sign-in** and
**Clear** (the removed tafs' connections), on a connection's row and on its page. It works as the
iPad's `disconnect(grantID:)` and `clearRemovedConnections`, and as Windows' `EndAsync`
(`ConnectionEnding`, `ConnectAppsModel.disconnect`, `clear`):

1. **The route** (`ConnectionEnding.route`). It is Touch ID only when the session's device key is
   in the Secure Enclave (`AccountClient.keyStore == "enclave"`, from `SigningKey.keyStore`), this
   sign-in has an **ending key** that loads (below), **and**
   `LAContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` is true now. Anything
   else goes to the phone: a software key, a Mac without Touch ID, Touch ID not set up or locked
   out, no ending key (a session from before the ending key has none and uses the phone until the
   next sign-in), or an ending key the system invalidated. That Mac asks nothing, sends nothing
   and shows "This device can't approve. Approve on another device signed in to your account."
   (`approval.device_can_not_approve_approve`), as before; a click that finds the route is no
   longer Touch ID shows that line under the action too, never nothing. planque and KIFF would
   take a software key's DELETE too (a safe route takes any device key), so this rule is the
   app's own. Reading the route writes nothing.
2. **The ending key** (`EndingKey`, `ConnectionEnding.EndingKeyCheck`). At sign-in, next to where
   the session is kept (`SignInModel`, through `EndingKeyHook`), a Mac whose device key is in the
   Secure Enclave and that can check Touch ID makes a second Secure Enclave key, with
   `SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
   [.privateKeyUsage, .biometryCurrentSet], nil)` and nothing else. Making it never prompts and
   never stops a sign-in: if anything fails there is no ending key, and the Mac uses the phone.
   It is bound to the fingers enrolled at that moment. On a Mac anyone who knows its password can
   add a finger in System Settings, which asks only that password; the system then invalidates
   the key, so a finger added (or removed) since sign-in can never pass, and the Mac uses the
   phone until the next sign-in. The Keychain holds only the key's handle (the Secure Enclave's
   wrapped reference, never the key), under `tafs.ending-key`, for this Mac only, with the
   SHA-256 of the session's token: a handle kept for another sign-in is no key. Each sign-in
   deletes the one before it and makes its own; sign-out deletes it.
3. **The question first**, the iPad's (`GateQuestion`). Then **Touch ID alone** (`TouchIDOnly`):
   the ending key is loaded with an `LAContext` whose `localizedReason` is the question's title
   ("Remove access to Stripe for Rae?", "Clear 2 connections from removed tafs?") and whose
   `localizedFallbackTitle = ""`, and signs the iPad's own confirmation,
   `tafs.disconnect.v1|{tenant}|{ids joined by ,}`. The system asks for Touch ID to sign;
   `.biometryCurrentSet` allows no password. The signature is checked against the key's public
   half, then thrown away, as the iPad's: it is never sent. It is never
   `.deviceOwnerAuthentication` and never `NeedsYouModel.confirmOwner`, which let the Mac's
   password in. **Any failed or closed Touch ID check sends nothing**: a closed prompt, a failed
   match, a lockout. A key the system invalidated (the fingers changed) is found at the click, as
   the signature fails; it is deleted, and the action says to approve on the phone. Any failure
   the app can't place is taken as that: the key goes, never a way around it. "Approve on your phone instead" (`approval.security_key.on_phone`)
   shows beside the action.
4. **Then planque's DELETE**, one per connection, signed by the device key with no prompt. The key
   has no access control (`DeviceKey`): the Touch ID check is the confirmation, as Windows Hello is
   before the TPM key, and the ending key's signature is that check. Clear asks Touch ID once for
   all of them. A refusal is counted and the next connection is still tried. Once the session changes, nothing more is sent: the window ends the
   model's session on sign-out and when it goes (`ConnectAppsModel.endSession`, as the iPad's
   `accountGeneration`), and an ending checks it after Touch ID and after each DELETE, even one
   whose prompt was still open.
5. **Then the connections and the removed tafs are read again.** What's said:
   - Disconnect says nothing when the Touch ID check failed or was closed (the iPad's choice;
     Windows says "not done").
     A refusal says `connect.not_disconnected` ("Access not removed. {why}").
   - Clear says "Not done: it wasn't confirmed." (`common.not_done_unconfirmed`) when the check
     failed or was closed. Otherwise it says how it went (`connect.clear_removed.cleared`, `connect.kept.for_card(s)`,
     `connect.could_not_cleared_try_again`).
   - Either says "This device can't approve. Approve on another device signed in to your
     account." when the ending key was gone (invalidated, or no longer this sign-in's).

The iPad signs `tafs.disconnect.v1|{tenant}|{ids}` as its Face ID step and then throws the
signature away. This Mac does the same with its ending key, whose `.biometryCurrentSet` makes the
signature Touch ID's own; the device key, which never prompts, signs only the DELETE. Windows
doesn't sign it.

Nothing that grants access changes. Connecting, **Sign in again**, **Replace the key**, a key, and
every approval and confirmation stay the phone's or the security key's, on every Mac.

**Account**, under Your account's sign-in, says where approvals are signed (`ApprovalRoute.howItWorksKey`).
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
- **The answer is an approval** (kiff/cloud's `PhoneApprovalRules`: No gives a Card its room
  back), so on a Mac with its security key the card has the iPad's No and Yes, with "No gives
  the Card its room back. Yes keeps it counted." under them. Each is `KeyAct.happened`: KIFF's
  `POST /v1/me/did-this-happen/{proposal}` with `{"happened":true}` or `false`, the iPad's
  request, approved by the key once for this one answer through its PIN sheet, which names it
  as the iPad's prompt ("Say it happened: {title}", "Say it didn't happen: {title}"). Then the
  call leaves the list and the list is read again; the first answer stands. A closed sheet
  sends nothing and says nothing, "Approve on your phone instead" says to approve on another
  device. KIFF's refusal reads the list again, so a call answered elsewhere leaves at once,
  and while the call is still listed it says "KIFF didn't take the answer" with why, in the
  app's words. One answer at a
  time, as the held calls'. Offered only for someone who answers held calls
  (`NeedsYouModel.offersHappened`).
- On a Mac without the key, for someone who answers held calls, the card says to approve on
  another device (`approval.device_can_not_approve_approve`, the iPad's `Biometry.short`
  where an approval can't be made), as the held calls do, and has no Yes or No. The line
  shows only on a Mac that approves elsewhere (`.phoneOrPasskey`), where the iPad's
  `ApprovalGate` would show `ApprovalNotReady`.
- KIFF's "Not sure" (`…/check`, the device key alone) isn't on the iPad's card at the pin, so
  it isn't here.
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

**On since kiff/cloud#96** (`Features.macPasskeyApprovals = true`): a Mac
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
- **Details ▾**, open until the person folds it, with **every argument KIFF keeps for the call, in full**
  (`HeldArguments.lines`, kiff/tafs `contracts/held-arguments.json`): one line each, nested values two
  spaces deeper below their name (a list's items numbered 1, 2…), keys sorted by code point at every
  level, the gateway's own (`kiff_operation_id`, `kiff_reason`, `kiff_about`) left out, a number written
  out without an exponent or trailing zeros from its own digits (never through `Double`; one longer than 100
  digits written out is shown as sent, `1e400`), a control character as a space, a direction mark dropped,
  and nothing ever shortened to "…". A held browser call's `steps` (each fill's field and value, each
  click's button) are what the person reads before approving. Arguments that aren't an object show no
  Details;
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

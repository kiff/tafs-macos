# Plan & usage

The balance now and the period's credits, in tafs cloud's words, then members' requests to the
account's admins. Nothing is bought or raised from the Mac: a member asks an admin, takes the
request back, and an admin declines one.

## What is read (`Usage`, `CloudClient`)

| Call | Route | What |
|---|---|---|
| `balance()` | `GET /v1/usage/balance` | The balance's words, its meter (0 to 100), a detail line, a warning, and the plan's line. |
| `credits(previous:)` | `GET /v1/usage/credits`, or `?period=previous` | The period's total in words, a line for each taf that used credits, Coach's own use, what wasn't counted, and a note. |

- Every amount and every line is tafs cloud's. The app works out nothing.
- **The meter is how much is used**, as tafs cloud's own page says, kept within 0 to 100 as
  the phones keep it. With no number there is no bar.
- The balance also says whether the First month pack can be bought now
  (`buy.first_month.ready`): the packs a member may ask for list it first only then.
- A balance without its state or its words is unreadable. A credits row that doesn't read is
  left out; the period is still drawn.

## Members' requests (`KIFFUsage`, `PackRequest`, `AccountClient`)

Ported from the iPad's `KIFFClient.Usage` and `PackRequest` (`KIFF/KIFFClient.swift:629-755`),
its routes (`:768-799`), and `askAdmin`, `withdrawRequest` and `declineRequest`
(`App/AppModel.swift:3581-3605`, `3672-3696`).

| Call | Route | What |
|---|---|---|
| `usage()` | `GET /v1/me/usage` | KIFF's plan (`team` is Company), who bills it (`billing`), the packs it sells, and the requests: every open one for someone who manages billing, the person's own otherwise. |
| `askAdmin(raise:pack:reason:)` | `POST /v1/me/pack-requests` | `{"kind": "raise", "reason"}`, no pack, or `{"pack", "reason"}`, where no `kind` means a pack. |
| `withdrawRequest(_:)` | `POST /v1/me/pack-requests/{id}/withdraw` | `{}`. |
| `declineRequest(_:note:)` | `POST /v1/me/pack-requests/{id}/decline` | `{"note"}`, **signed** by the device key (`KIFF-Device-Signature`). |

- A pack or a request that doesn't read is left out, never the list. A request from a KIFF
  that doesn't say its kind is for a pack.
- **Who manages billing** is KIFF's `billing.manage` (`Me.managesBilling`); a KIFF that lists no
  capabilities leaves it on.
- **Asking**, for someone who doesn't manage billing, where the plan lets them (`asks`): a raise
  of the spend limit on Company, a pack on Solo while packs are on sale. Their request waiting
  shows with Withdraw; else the last answer (raised, a pack added, declined with its note,
  ended), then **Ask an admin**, filled while the tafs wait. The sheet takes a pack, for a pack,
  and a reason of at most 500 characters.
- **Declining**, for someone who manages billing: each open request's line ("Someone asks for
  Rayo.") and reason, with **Decline**. Its sheet asks the question and takes a note. The person
  confirms with Touch ID or the Mac's password (`billing.request.decline_prompt`), then the
  device key signs, as the iPad's `signer.sign`. A prompt closed or failed sends nothing:
  closed, it says "Cancelled. Nothing changed." (`approval.cancelled`), since nothing waits on
  it after; failed, "Not sent: it wasn't confirmed." (`common.not_sent_unconfirmed`). Without a
  device key it says to sign in again. The model owns the decline, and
  sign-out cancels it (`cancelAnswers`): one whose session ended while the prompt was up sends
  nothing, and one that ended while it went says nothing, as the iPad's `accountGeneration`
  (`AppModel.swift:3681`, `:3689`).
- After an ask, a withdrawal or a decline, everything is read again. One KIFF doesn't take says
  why over the screen (`planMessage`), in the shared words (`billing.request.not_sent`,
  `not_withdrawn`, `not_declined`), with the app's plain line for why, never KIFF's code, as the
  iPad's `KIFFError.errorDescription` and `PlainError.words`: a 401 is "Signed out of KIFF",
  any other refusal is its status's line (`error.changed`, `error.down`, `error.ours`…). The
  usage read that fails says the same.
- **KIFF's read failing** keeps what was read and says so once, under the credits.

### Who bills the plan (`billingPanel`)

As the iPad's `billingPanel` (`UsageView.swift:121-182`), the first of KIFF's panels, before
asking and requests, for anyone who reads Plan & usage:

- **One line, by `billing.source`:**
  - `apple`: "Billed by Apple" (`billing.by_apple`).
  - `google`: "Billed by Google Play".
  - `stripe`: "Billed by KIFF".
  - `contract`: "Managed by your company's agreement".

  With no billing, or a source this app doesn't know, there's no panel. A billing with no
  source, or with a date that doesn't read, is none, as the iPad reads it, and never the rest
  of the usage.
- **Manage**, beside Apple's line, opens the Apple account's subscriptions in the App Store
  (`https://apps.apple.com/account/subscriptions`), where the iPad opens the same page from
  StoreKit (`manageSubscriptions`).
- **After a move from Solo to Company**, which KIFF bills (`stripe`), while Solo bought in the
  App Store still renews, the panel adds a line: "Company is billed by KIFF now. The Solo bought
  in the App Store renews on {date} unless it's cancelled…"
  (`usage.company_billed_kiff_solo_bought`, `apple_solo_until` as a long date). Beside it,
  **Cancel Solo** opens the same Apple page.
- **Nothing to buy:** the app never points anywhere else to buy.

## The screen (`UsageView`, `UsageModel`)

Laid out as the iPad's: the screen's name small and centred at the top, then panels (radius
18, as `Look.panelRadius`). The balance's panel is edged in red while the tafs wait and in
amber with a warning, and the warning takes the same colour.

- **Balance**, a panel: the words (red while the tafs wait), the meter (the iPad's `Meter`: a
  5-high capsule on ink at 10%, green when fine, amber otherwise), then the detail and the warning.
  **No plan line here**: the iPad draws `plan_line` only on Account's Plan card, and under the
  headline it said the headline again ("No limit · 9,872 credits used" twice).
- **Credits**, a panel: its heading, Last period and This period as the iPad's two-part
  switch, and the total.
- **Each taf's line** is its own panel, with its pace under it. A listed taf's line opens its runs in
  the period shown (`GET /v1/usage/credits/tafs/{taf}`, with `?period=previous` on the last period), as
  the iPad's `TafCreditsView(taf:previous:)`; the line for tafs removed since doesn't open.
- **Coach's use past what's included** (`coach`) is a panel of its own after the tafs' rows,
  as on the iPad. It is counted, so it is never under what wasn't.
- **What wasn't counted**, a panel: tafs cloud's total line, then **why each wasn't**, a line
  each (`not_counted.lines[].words`: "Coach, included · 3 runs"). A reason with no words, or
  one that doesn't read, is left out, never the others.
- tafs cloud's note under them.
- **Where to buy on a computer**, in the balance's panel, for whoever manages billing, only as
  tafs cloud's balance `buy` offers it (`Usage.whereToBuy`), as the other desktops and the iPad:
  "Buy Solo or credits in the tafs app on your phone." (`billing.buy_on_phone`) when `buy` offers
  packs or Solo (`true`, or set and not `false` or null), and then **Get Company on kiff.dev**
  (`billing.team_on_web`, opening `kiff.dev/dashboard/checkout`, `Usage.teamCheckout`) unless the
  plan is Team already. With `buy` null (a company's agreement) or nothing offered, neither.
  Nothing is bought here.
- Every line is drawn as sent (`Text(verbatim:)`).
- **Each half is read on its own.** One that can't be read says so and leaves the other.

## Raise the limit (`UsageModel.raiseLimit`)

As the iPad's `raiseLimit` (`AppModel.swift:4613-4650`): for someone who manages billing, where
tafs cloud's balance offers it (`balance.raise`: its words, "Raise the spend limit to €2,000",
and the limit now, `from_cents`). It's on the balance's panel, and on a member's raise request
in place of buying, since one raise answers every open one.

- **The owner confirms first, every time**: Touch ID or the Mac's password, never cached, the
  prompt naming the new limit. Closed, nothing is built or sent.
- **Then KIFF's `PUT /v1/me/usage/limit`** with `{"from_cents":…,"raise":true}`, **signed by the
  device key**. KIFF lists it in `PhoneSignedRules`, not `PhoneApprovalRules`, and its handler
  takes only someone who manages billing, so no security key is asked for (kiff/cloud main).
- **KIFF sets the new limit**, one step up from `from_cents`, the limit the screen read, which is
  what's signed: the body names no target. The prompt's figure is tafs cloud's offer words
  (`raise.words`), so it names KIFF's step only as long as those words describe it. The limit now
  (below) is on screen before the click, written from that signed value.
- **After it goes,** the balance is read again. Until a read works, only Read it again is offered
  (`usage.raised_unread`), so a second click never raises it again for a balance the screen no
  longer shows.
- **KIFF's refusals:** `limit_changed` (the limit moved meanwhile) reads the balance again and
  says so; `limit_ceiling` says to contact KIFF; anything else is "The limit wasn't raised", with
  why in the app's words.
- **The limit now**, above the button, as the iPad's: "The spend limit is €1,500 now."
  (`usage.raise_limit.from`). It's written from the signed `from_cents` in the currency tafs cloud
  sends beside it (`raise.currency`, ISO 4217) by this Mac's own formatter, in the app's language,
  with the currency's own decimals (ISO 4217's minor unit: 2 for EUR, 0 for JPY, 3 for KWD).
  Without a currency, or with anything that isn't a code (a tafs cloud from before it), there's no
  line: a currency is never assumed. The prompt and what's signed are unchanged.

## Not on the Mac

Buying credits or a plan and restoring purchases. The phones do these through their stores; the
Mac has no store, so it says where to buy (above). So Approve on a member's pack request (buying
the pack) isn't on the Mac. A taf's runs behind its line are not built.

## Tests

`scripts/test.sh usage`: the balance and the credits as tafs cloud sends them, a meter out of
range, unreadable answers, a 503's code, each half failing alone, the period asked for, and
that tafs cloud is only ever read (`GET`). For the requests: KIFF's usage as sent, the packs
offered, each route's path, body and signature (only a decline is signed), a decline without
a key, the prompt closed, KIFF's refusals, the reads after, and the lines both apps share. For
who bills: each source's line, Manage only for Apple, Solo still renewing only after a move to
Company, and a billing that doesn't read as none (`usageBillingTests`). It
writes `build/screenshots/usage-*.png`, a member's and an admin's requests and both sheets
among them, and `usage-light.png` and `usage-dark.png` with a plan line the screen leaves out.

# The Record

Every call the person's tafs made, newest first, found by what it is about, its action or
its amount. tafs cloud finds, words and decides; this app sends what is typed and draws the
answer as sent.

## What is read (`CloudClient`, `Record`)

| Call | Route | What |
|---|---|---|
| `record(_:cursor:)` | `GET /v1/record?q=&cursor=` | One page of a search: entries, tafs cloud's groups, and its own words for the search box, "nothing matched" and the end. |
| `recordCase(_:)` | `GET /v1/record/cases/{about}` | Every call about one thing, oldest first, with the step that failed in tafs cloud's words. |
| `calls(_:)` | `GET /v1/tafs/{id}/calls` | One taf's calls, `{calls:[{invocation, value}]}`: what names a line's payment (below). Read whole or not at all, as the iPad's `TafsCloud.calls`. |
| `exportReceipts(from:to:)` | `GET /v1/record/receipts?from=&to=` | The receipts of some days (YYYY-MM-DD, at most 92), for an accountant: tafs cloud's answer byte for byte, its CSV, and how many calls have no receipt yet. |

- tafs cloud is at `https://cloud.tafs.kiff.dev` and takes the person's KIFF session.
- What is typed is escaped and cut at 100 characters, tafs cloud's limit.
- An entry's title, detail, time and amount are tafs cloud's text, drawn as sent.
- An entry's `call` is KIFF's: besides its receipt, amount, answer and read, the Record reads its
  `proposal_id`, `entity_id`, `on_hash`, `on_arg`, `reason` and the answer's `signed` and `device`;
  KIFF's key and reason are drawn without direction or control characters (`Record.visible`, the
  iPad's `KIFFMapping.visible`). Its `next` (`{kind, words, tool?, taf?, message?}`) is tafs cloud's
  next step; one without its kind or words isn't one. A case's `failed` carries its own `next`,
  decoded as the iPad's and, as there, not drawn.
- KIFF's held list (`GET /v1/me/card-exceptions?status=held`, the request Needs you sends) is read
  by the Record itself, for "no longer waiting" (below), after each page of lines it reads, the
  first page read again after a refused cursor included: so it is never older than the lines it is
  held against.
- A page whose entries don't read is unreadable. It is never shown as an empty Record.

## The screen (`RecordView`, `RecordModel`)

- To the iPad's layout: the title and its line, the search box across the screen, then the
  filters as pills.
- The search box shows tafs cloud's hint. **What's typed is searched once the person
  pauses** (400 ms after the last key, the iPad's `recordQueryTyped`), so a word typed letter
  by letter is one search; words already searched, or being searched, aren't searched again.
  Return searches at once. **An emptied box shows the list again at once**, with nothing read.
- **A search is kept apart from the list** (`RecordModel.Found`, the iPad's `RecordSearch`)
  and stands in for it: its calls as tafs cloud found them, never narrowed by the list's taf
  chips or filters; tafs cloud's "nothing matched" once no page held a call; why it couldn't
  be read (tafs cloud's words, else its error, else "tafs cloud answered {status}"). Each page
  is drawn as tafs cloud sent it, after the ones before, so a day split across two pages is two
  groups. **Its next page is read on More**, never by itself (a refused cursor searches again);
  with no next page, the last page's end line shows, dim. Each call found has what
  it's about as a link,
  "Order 4471 ›", that **opens its case** (the iPad's `RecordHitRow` and `RecordCaseSheet`):
  every call about the same thing, oldest first (`GET /v1/record/cases/{about}`), the step
  that didn't go through named first in red, in tafs cloud's words. The Record never sends
  anything again itself.
- **A call found, and a case's step, is drawn as its taf's Activity draws it** (`RecordStepRow`,
  the iPad's `RecordHitRow` and `SourceActivityRow`): its taf's name (11 medium monospaced
  capitals, `dim`), then, for a taf the person lists, a plain row, not boxed: title (15 semibold)
  over detail (13 `soft`), its time (12 `dim`) over its amount (13 semibold) at the right, padded 5;
  a call whose KIFF call names its taf (`call.actor_id`, the iPad's `evidence`) opens its sheet,
  receipt or not ("Shows the receipt"). Under it, **its own next step**, in tafs
  cloud's words (13 `soft`), as the iPad shows it to anyone it gives no button (below, Not yet).
  A taf the person only oversees shows the call boxed (title, detail, amount in 14 medium, time),
  with no next step, as the iPad's. A case's sheet keeps its spinner until a step or an error comes,
  as the iPad's.
- **A case's step opens its receipt over the case's sheet** (a sheet on the sheet); from the list
  or a search, over the screen. The receipt from a case or a search is the step's own line, never
  named (below), as the iPad's evidence: so no payment is compared there.
- **Filters** (`Record.Filter`), the iPad's: All, Money moved (done or approved, with an
  amount), Stopped (refused, not done, revoked) and Waiting (held, sending, unknown). They
  choose among the calls already read; a group left with none is left out.
- The list is by day (below); each row has a dot for how it went, in the iPad's kind
  colours (`Record.tone`, the iPad's `RecordEntry.Kind.color`: done, approved and started green;
  refused, not done and revoked red; in tafs dim; any other kind amber), the call, its taf, its
  amount and its time, then the iPad's second line (below). **Every row but one done in tafs opens
  its sheet** (`Record.opensSheet`), receipt or not, as the iPad's `RecordRow`; "KIFF receipt" shows
  under it only once KIFF says the receipt is signed.
- **A day's reads fold into one line**, as the iPad's list (`RecordView.swift:44-63`): a call KIFF
  marks a read (`call.read_only`, as the iPad's `ActivityCall.readOnly`) goes under its day's
  calls as "· 3 reads of data, within its Card · Show" (`record.reads`, `record.show`), in 13 `ok`
  green; Show draws them under the day's calls and Hide (`record.hide`) folds them again. Only
  under All, as on the iPad: a filter shows reads as calls. A day of reads alone is its title and
  the fold.
- **A row's second line is the iPad's** (`RecordRow.detail`, `decidedLine`, `resultLine`,
  RecordView.swift:206-212, 216-259, 314-329), joined with " · ". **First, what the call acted
  on**, "payment …QbstR" (`onText`): the argument's name with spaces (`on_arg`, else `record.on.it`),
  and the value's last 5 when it's longer than 6, else the whole. The value is never in the Record:
  after each page is read, each of the person's listed tafs (never one they only oversee, as the
  iPad's `cloudTaf(for:)`) with a line whose call has an `on_hash` and no value yet has its
  calls read from tafs cloud (`GET /v1/tafs/{id}/calls`, by the taf's id there), and a line takes the
  value its `entity_id` names **only when "sha256:" and the lowercase hex SHA-256 of its UTF-8 bytes
  is the line's `on_hash` exactly** (untrimmed, in its own case: `Record.isOn`, `Record.naming`, the
  iPad's `nameRecordLines`, `KIFFMapping.naming` and `isOn`). Best effort: a taf whose calls can't
  be read keeps its lines unnamed, and a newer read of the list drops the answer. Search hits and
  a case's steps aren't named, as on the iPad. **Then, for a held call KIFF no longer holds,
  "no longer waiting · nothing sent"** (`record.no_longer_waiting`, `record.nothing_sent`): the
  Record reads KIFF's held list itself, and a held line is no longer waiting once that list is read
  and none of its calls (by `proposal_id`, else the hold's own id; a `card_unit` request isn't one)
  is the line's `proposal_id` (`Record.isWaiting`, `HeldCall.heldProposals`, the iPad's
  `isWaiting`). **Until the list is read, or when it can't be, every held line still waits**, as the
  iPad's, and a line without a `proposal_id` always does. Otherwise, for a call with a KIFF receipt or an owner's answer, who
  decided, then what became of it at the tool, "within its Card · done", "refused by its Card ·
  nothing sent", "approved by you · done", "refused by an admin · nothing sent" (`record.decided.*`,
  `record.result.*`, `record.nothing_sent`, `card.card_revoked`, the answerer as `record.answerer.*`
  or `people.role_phrase.*`), a held one still waiting "waiting for you · nothing sent yet". Any
  other call reads as tafs cloud words it.
- **Export receipts** (`ExportReceiptsRow`, the iPad's, RecordSearchViews.swift:128-191 and
  RecordView.swift:19-23): under the search box, in 15 semibold `amberText`, for whoever oversees or
  manages every taf on tafs cloud (`Record.seesEveryTaf`, the iPad's `seesEveryTaf`, from KIFF's
  `GET /v1/me/access`; unread, it isn't shown; tafs cloud still decides, 403). It opens Last 7, 30
  and 90 days (`record.export_last_days`), the account's calendar days with today; "Preparing
  receipts…" while tafs cloud makes them; then **a save panel** asks where, and a folder named
  `receipts-<from>-to-<to>` gets the two files the iPad shares, `.json` (tafs cloud's answer as it
  came, so KIFF's receipts are as issued) and `.csv`. Nothing else in the folder is touched, and
  nothing is kept elsewhere on this Mac. Calls with no receipt yet are counted under it
  (`record.export_missing`); a refusal says why (`record.export_not_exported`, with tafs cloud's
  words). It only reads: nothing is signed or sent.
- The list (not a search) reads its next page when its end comes into view, and joins its group.
- A cursor tafs cloud no longer takes (a call was made since) starts the search again.
- A slower answer to an older search is dropped.

## A line's KIFF receipt (`ReceiptSheet`, `ReceiptCheck`)

As the iPad's `ReceiptView` and `ReceiptCheck`: a line whose call has a KIFF receipt (its `call.receipt`,
`trace_id` and `status`) shows **KIFF receipt**, which opens the receipt in a sheet and checks it on
this Mac. Nothing opens outside the app.

- **Read from KIFF as it wrote it:** `GET /v1/receipts/{trace_id}` (the id escaped), with the session.
  The signed chain (`causal_chain`) is taken byte for byte from the answer (`ReceiptJSON`), never
  decoded and written again, as KIFF hashed it.
- **The check:** the digest is keccak256 of the chain's SHA-256 in hex; the signer recovered from the
  65-byte secp256k1 signature must match the receipt's `wallet_address`, and must be KIFF's own
  signer, `0x2f297affd7b62ef712a1e3158421ccb4bf2efcbe` (the iPad's and Linux's). secp256k1 isn't in
  CryptoKit:
  - **The recovery is libsecp256k1's own** (`ReceiptRecovery`), with its recovery module only, built
    from pinned source by `scripts/fido.sh` (docs/building.md). It's the release the iPad's
    swift-secp256k1 vendors, so both recover with the same C code. Core takes the recovery as a
    function (`ReceiptRecover`), as it builds on Linux without the library.
  - **Keccak-256 is the iPad's own file** (`ios/Tafs/KIFF/Keccak.swift`), fetched at the pin and
    compiled into Core as it is (`scripts/shared.sh sources`): one Keccak for the Apple apps.
  - **SHA-256** is CryptoKit's.
  - **v** is read as the iPad reads it: 27 and up has 27 taken off, and the recovery id must be 0–3,
    so v is 0–3 or 27–30. Any other v is refused before the library is asked. **A high s is taken**,
    as on the iPad and Linux: a receipt's signature only says who signed it, so s or n − s proves the
    same.
- **Refused as "couldn't be read":** a receipt that writes any key twice, at its top or in its
  attestation. A repeated key could make the hash and the screen read different values.
- **Not signed yet** (no attestation) isn't a failure: KIFF signs within a minute. After ten minutes the
  sheet adds the receipt's id to quote.
- **Each failure** says why in the shared words (`receipt.check.*`), under "This receipt was changed…".
- **Held to the line**, only on a receipt this Mac verified, in the iPad's order
  (`ReceiptSteps.mismatchKey`, RecordView.swift:489-553): **its payment first**: a named line's value
  (above) against the `on_hash` of the first signed step that has one, by the same SHA-256 rule
  ("The payment on this line doesn't match KIFF's receipt.", `receipt.check.payment_mismatch`); then
  its amount, as a number in the same unit; then the owner's answer ("reject" is a refusal). Each
  draws "KIFF's receipt doesn't check out" with why, never the check. A line not named, or a chain
  that signed no `on_hash`, compares no payment, and nothing says the payment was checked (the iPad
  has no such words): the check is KIFF's signature.
- **What happened**, the receipt's steps, is drawn **only** once this Mac checked the receipt as KIFF's
  and it matches the line (payment, amount and answer). Unsigned, failed, still checking, or another
  line's, it isn't.
- **The facts are the iPad's** (RecordView.swift:385-402, 689-731): above the title, how it went in
  its kind's colour (`Record.tone`; `receipt.label.*`, or who answered, `receipt.approved_once_by`,
  `receipt.refused_by`); then a panel of lines, name (13 `dim`, 90 wide) and value (14 `ink`): Taf
  (the listed taf's name, "–" for one the person doesn't list),
  When (abbreviated date and time, in the account's zone, with its short name when it isn't this
  Mac's), On (`receipt.fact.on`, the argument and the whole value, only on a named line), Outcome in
  semibold (`receipt.outcome.*`), Why (KIFF's `reason`, only when it gave one) and Decided by
  (`receipt.decided_by.*`, KIFF's mode, with "signed on {device}" for an answer KIFF says was signed).
- **Open in the taf's chat** (`record.open_taf_chat`), full width, for a line whose taf the person
  lists: it closes the sheet (and a case's) and opens the taf's page on its chat, through the shell's
  own `open` (`EnvironmentValues.openTaf`, set by `ShellView` on the screen it draws).
- **The receipt's facts line**, in the checked and the failed panel, as the iPad's `receiptFacts`
  (RecordView.swift:569-576): its decision (`receipt.decision.*`, `Record.Entry.decisionWords`: who
  answered a held call, else what its Card did) and when KIFF issued it (`receipt.issued`), 11.5
  monospaced `dim`, selectable.
- **The full receipt** (each step's hash, the signature's ends) and **Copy receipt**.
- **A line without a KIFF receipt opens its facts only**, with Open in the taf's chat: no check, and
  nothing KIFF signed, as the iPad's.
- **Mac differences:** Open in the taf's chat sits under the facts, where the iPad has it last; no
  Share. A receipt opened from inside a case's sheet is a sheet on that sheet.

## The page before a Chrome step (`ChromeShots`, `ChromeShotSheet`)

As the iPad's `ChromeShotView` and its receipt: a Record line whose operation a paired Chrome acted for lists "See the page
before this step", one per picture planque kept (with its time when there's more than one), and each opens "Before this
step": the picture, when it was taken in the account's time zone, and "Kept for 30 days, then deleted."
- **The reads:** planque's safe routes, signed by this Mac's device key for that one request, with no session token
  (`PlanqueClient.Safe.chromeShots`, `.chromeShot`): `GET /v1/accounts/{t}/chromes/screenshots?op={proposal_id}` and
  `…/chromes/screenshots/{step}`. The operation is escaped inside the signed query, so it can't add a parameter. None
  signed out. A list that can't be read, or a 404 (planque keeps none, or its switch is off), shows no link.
- **The picture is shown only if it checks out** (`ChromeShots.read`): base64url without padding, 12 bytes to 120 KB,
  RIFF/WEBP, the SHA-256 planque kept, the step asked for, and an RFC 3339 time. Anything else says "The picture
  couldn't be loaded", and a 404 says "No picture is kept for this step".
- **It's decoded on this Mac at most 2048 on its longest side** (`ChromeShotSheet.decoded`, ImageIO's thumbnail of the
  whole picture), whatever size the file declares, and the bytes are never written to disk.

## Not yet

A next step's buttons (Connect again, signing in again where the vendor signed tafs out; Ask
Coach; Connect apps) for someone who manages the taf: they are the iPad's `NextStepRow`, under
TafPresentationViews.swift, and need the shell's Coach and Connect apps. Until then the Record
draws the step's words, as the iPad does for anyone it gives no button.

A receipt's Chrome shots: the iPad reads the pictures a paired Chrome kept before the call's steps
(`chromeShots(op:)`) and offers each with "See the page before this step" (`chrome.shot_open`), opening
`ChromeShotView`; they come with ChromeViews.swift. **Report this payment** is at the foot of the
sheet (`RecordModel.report`; ReportPaymentSheet.swift's row in the checklist).

## Tests

`scripts/test.sh record` checks the page as tafs cloud sends it, the escaping and the limit,
an ungrouped page, an unreadable one, a refusal's code, a case, the paging and the restart;
on a Mac, a search once typing pauses and at once on Return, and a case opened and closed.
The receipt: Keccak-256's vectors (the empty string, "abc", 135, 136, 200 and 300 bytes, either
side of the 136-byte rate); v read as the iPad reads it; the iPad's fixture signed by KIFF's own
signer; a repeated key, a changed byte, another signer, a malformed signature, not signed yet. On
Linux the recovery is a test oracle in plain Swift (`Tests/record/Secp256k1.swift`), checked against
python-ecdsa's signatures. On a Mac, libsecp256k1 and the oracle agree on the fixtures (a high s, and
v as 0–1 or 27–28) and on 1,600 random inputs, and both refuse r or s at n, zero or all ones; the
fixture checks out through libsecp256k1 and each failure fails; and the read, a refusal, and when
what happened shows.
Naming and waiting (`RecordNamingTests`): `isOn` against the iPad's fixture (another case, a trailing
space, no prefix and uppercase hex all fail), a line named only by the value KIFF hashed and only by
its key, `onText`'s noun and its 6-character rule, the tafs read (only listed ones), the kinds'
colours, which lines open a sheet, `calls` (its escaped path, a GET
with no body, read whole or not at all), `visible`; `HeldCall`'s `proposal_id` and `kind`, a held
line waiting until the list is read, no longer waiting without its proposal, a `card_unit` ignored,
a hold matched by its own id; the payment check on a receipt signed by a test key the way KIFF signs
(verified over this payment, a mismatch over another, nothing compared unnamed), the mismatches'
order and "What happened" hidden; the receipt's state, Outcome and Decided by, in every language;
`next` decoded, a blank one none, a case's steps' and its failed step's. On a Mac: the list named
from its listed tafs' calls, best effort, never an overseen taf's, and a taf listed later named then;
the held list read after the lines, after a refused cursor too, and a failed read waiting again; a
line without a receipt opening its facts and reading nothing; and the
screenshots `record-row-on-en`, `receipt-facts-en`, `receipt-payment-mismatch-en` and
`record-case-steps-en`.
Reads: `call.read_only` decoded (absent or not a bool is a call), the pinned Activity contract's
entry read as a Record line, a day's reads folded apart under All and not under a filter, and
Show and Hide; a day's spend summed per currency at the larger decimals; each row's second line
by kind and answer, its words in all 8 languages; Export's request (`/v1/record/receipts`, the
account's days), its bytes kept, both files written beside what's there, a cancel saving nothing,
a refusal's words; and who sees it.
It writes `build/screenshots/record-*.png` and `receipt-*.png`, among them
`record-reads-folded-{light,dark}.png`, `record-reads-shown-{light,dark}.png`,
`record-export-{light,dark}.png` and `record-export-row-{light,dark}.png`. There is no fixture for the Record in kiff/tafs's
`contracts/` yet: the shape is taken from kiff/tafs's `docs/api.md` and the iPad app's reader.

## The layout, as the iPad's

- **Taf chips** above the filters: "All tafs", then one pill a taf with its colour's dot. A
  taf's pill keeps that taf's calls (`Record.only(taf:in:)`), with the filter.
- **A day** is the iPad's (`RecordView.days` and `dayTitle`, RecordView.swift:134-151): the
  calls shown, whichever group tafs cloud sent them in, by the day they were made in the
  account's time zone (KIFF's `time_zone`), newest first (`Record.days`). Its title is "Today ·
  Nov 15", "Yesterday · Nov 14", else "Friday · Nov 13" (`AccountTime.dayTitle`,
  `calendar.today_date`, `calendar.yesterday_date`), its date and weekday in the app's language,
  with this Mac's region (`AppDates.locale`), in capitals, 11 medium monospaced, `dim`.
  A search's results keep tafs cloud's groups, as the iPad's `RecordResults`. Then **what the day
  spent**, after " · ", the whole heading in capitals in the app's language ("TODAY · 17 NOV · €640 SPENT"), as the iPad's day heading
  (`RecordView.swift:48`, `:107-125`): `Record.spentWords` writes each currency's sum from
  `Record.spent` in the app's language, joins them with " + ", and says it in `record.day_spent`,
  whose amount's place differs by language. A day that moved no money has none.
- **A call** is a panel (radius 14, padding 14): its status dot (9), then its taf's dot and
  "Taf · what it did · amount" in 14 semibold with its time at the right in 12 monospaced
  `dim`, then who decided and what became of it, at 13 `soft`.


## Report this payment (`Record.Entry.report`, `ReceiptSheet`)

Ported from the iPad's `ReportPaymentSheet.swift` and `TafsCloud+Record.swift` (`reportPayment`), for a payment the
person didn't expect (docs/record.md in tafs).

- **Offered where tafs cloud sends it:** an entry's `report` (`trace_id`, and `at`, when the payment was made) comes
  only on a payment this reader may report (an owner or admin, `cards.manage`, as KIFF's route asks) that has a receipt
  and isn't reported yet. `reported_at` takes it away, as does a report made here. An offer that doesn't read is none,
  and the line still reads.
- **At the receipt's foot**, in a panel, since the receipt is already a sheet on this Mac (the iPad opens a second
  one): "Report this payment", then the app's own words with the line's taf, amount and date
  (`record.report.intro`: "Report a payment you didn't expect: {taf} paid {amount} on {date}. We halt {taf} until
  you've looked."), and **Report and halt {taf}** in red.
- **One click, nothing signed:** `POST /v1/record/{trace_id}/report` with no body. It only takes authority away (KIFF
  marks its receipt and tafs cloud halts the taf, as the halt button does), so no key or password is asked; resuming
  stays behind an approval. Reporting again answers the same.
- **Then:** "Reported. {taf} is halted and the receipt is kept. If money left your account, contact your card issuer
  too." in place of the panel, and the tafs are read again (the taf shows halted). A failure says "Couldn't send the
  report. Nothing changed. Try again." and the button stays.

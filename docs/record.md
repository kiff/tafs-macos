# The Record

Every call the person's tafs made, newest first, found by what it is about, its action or
its amount. tafs cloud finds, words and decides; this app sends what is typed and draws the
answer as sent.

## What is read (`CloudClient`, `Record`)

| Call | Route | What |
|---|---|---|
| `record(_:cursor:)` | `GET /v1/record?q=&cursor=` | One page of a search: entries, tafs cloud's groups, and its own words for the search box, "nothing matched" and the end. |
| `recordCase(_:)` | `GET /v1/record/cases/{about}` | Every call about one thing, oldest first, with the step that failed in tafs cloud's words. |
| `exportReceipts(from:to:)` | `GET /v1/record/receipts?from=&to=` | The receipts of some days (YYYY-MM-DD, at most 92), for an accountant: tafs cloud's answer byte for byte, its CSV, and how many calls have no receipt yet. |

- tafs cloud is at `https://cloud.tafs.kiff.dev` and takes the person's KIFF session.
- What is typed is escaped and cut at 100 characters, tafs cloud's limit.
- An entry's title, detail, time and amount are tafs cloud's text, drawn as sent.
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
- **Filters** (`Record.Filter`), the iPad's: All, Money moved (done or approved, with an
  amount), Stopped (refused, not done, revoked) and Waiting (held, sending, unknown). They
  choose among the calls already read; a group left with none is left out.
- The list is by day (below); each row has a dot for how it went, in the iPad's kind
  colours (done and approved green; refused, not done and revoked red; any other kind amber), the call, its taf, its amount and its time,
  then the iPad's second line (below).
- **A day's reads fold into one line**, as the iPad's list (`RecordView.swift:44-63`): a call KIFF
  marks a read (`call.read_only`, as the iPad's `ActivityCall.readOnly`) goes under its day's
  calls as "· 3 reads of data, within its Card · Show" (`record.reads`, `record.show`), in 13 `ok`
  green; Show draws them under the day's calls and Hide (`record.hide`) folds them again. Only
  under All, as on the iPad: a filter shows reads as calls. A day of reads alone is its title and
  the fold.
- **A row's second line is the iPad's** (`RecordRow.detail`, `decidedLine`, `resultLine`,
  RecordView.swift:216-259, 314-329): for a call with a KIFF receipt or an owner's answer, who
  decided, then what became of it at the tool, "within its Card · done", "refused by its Card ·
  nothing sent", "approved by you · done", "refused by an admin · nothing sent" (`record.decided.*`,
  `record.result.*`, `record.nothing_sent`, `card.card_revoked`, the answerer as `record.answerer.*`
  or `people.role_phrase.*`). Any other call reads as tafs cloud words it. **Held** keeps tafs
  cloud's line: the iPad says "no longer waiting" once KIFF holds it no more, which the Record
  doesn't tell this Mac. What the call acted on (the iPad's `onText`, "payment …QbstR") isn't drawn:
  it needs the taf's reference, which the Record doesn't carry.
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
- **What happened**, the receipt's steps, is drawn **only** once this Mac checked the receipt as KIFF's
  and it matches the line: the line's amount, as a number in the same unit, and the owner's answer
  ("reject" is a refusal). Unsigned, failed, still checking, or another line's, it isn't.
- **The full receipt** (each step's hash, the signature's ends) and **Copy receipt**.
- **Mac differences:** the line's facts are tafs cloud's words (taf, time, detail), where the iPad
  builds its own from KIFF's activity; the line's payment (`on_hash` against the taf's reference) isn't
  checked, since tafs cloud's Record doesn't carry the reference; no Share; and a receipt opens from the
  Record's list and search, not from inside a case's sheet (a window shows one sheet at a time).

## Not yet

A case's steps drawn as their taf's Activity draws them, with each step's own next step (the
iPad's `SourceActivityRow`), the only retry: the Mac draws the Record's row, with no next step
yet. A case read with no steps shows an empty sheet, where the iPad keeps its spinner. A taf's
detail. A receipt's payment check against the taf's reference.

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


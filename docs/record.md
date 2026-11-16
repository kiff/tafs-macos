# The Record

Every call the person's tafs made, newest first, found by what it is about, its action or
its amount. tafs cloud finds, words and decides; this app sends what is typed and draws the
answer as sent.

## What is read (`CloudClient`, `Record`)

| Call | Route | What |
|---|---|---|
| `record(_:cursor:)` | `GET /v1/record?q=&cursor=` | One page of a search: entries, tafs cloud's groups, and its own words for the search box, "nothing matched" and the end. |
| `recordCase(_:)` | `GET /v1/record/cases/{about}` | Every call about one thing, oldest first, with the step that failed in tafs cloud's words. |

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
  colours (done and approved green; refused, not done and revoked red; any other kind amber), the call, its taf and what it is about, its amount and its time.
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
detail, exporting receipts (for someone who sees every taf's Record), and folding a
day's reads into one line, as the iPad's list does. A receipt's payment check against the
taf's reference.

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
It writes `build/screenshots/record-*.png` and `receipt-*.png`. There is no fixture for the Record in kiff/tafs's
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
  A search's results keep tafs cloud's groups, as the iPad's `RecordResults`. The iPad adds the
  day's spend ("€640 spent"); the Record sends each call's amount as text only, so the Mac
  doesn't add them up.
- **A call** is a panel (radius 14, padding 14): its status dot (9), then its taf's dot and
  "Taf · what it did · amount" in 14 semibold with its time at the right in 12 monospaced
  `dim`, then what it was about and how it went, at 13 `soft`.


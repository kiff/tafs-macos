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

## Not yet

A case's steps drawn as their taf's Activity draws them, with each step's own next step (the
iPad's `SourceActivityRow`), the only retry: the Mac draws the Record's row, with no next step
yet. A case read with no steps shows an empty sheet, where the iPad keeps its spinner. A taf's
detail, exporting receipts (for someone who sees every taf's Record), and folding a
day's reads into one line, as the iPad's list does.

## Tests

`scripts/test.sh record` checks the page as tafs cloud sends it, the escaping and the limit,
an ungrouped page, an unreadable one, a refusal's code, a case, the paging and the restart;
on a Mac, a search once typing pauses and at once on Return, and a case opened and closed.
It writes `build/screenshots/record-*.png`. There is no fixture for the Record in kiff/tafs's
`contracts/` yet: the shape is taken from kiff/tafs's `docs/api.md` and the iPad app's reader.

## The layout, as the iPad's

- **Taf chips** above the filters: "All tafs", then one pill a taf with its colour's dot. A
  taf's pill keeps that taf's calls (`Record.only(taf:in:)`), with the filter.
- **A day** is the iPad's (`RecordView.days` and `dayTitle`, RecordView.swift:134-151): the
  calls shown, whichever group tafs cloud sent them in, by the day they were made in the
  account's time zone (KIFF's `time_zone`), newest first (`Record.days`). Its title is "Today ·
  Nov 15", "Yesterday · Nov 14", else "Friday · Nov 13" (`AccountTime.dayTitle`,
  `calendar.today_date`, `calendar.yesterday_date`), its date and weekday in the app's language,
  never this Mac's, in capitals, 11 medium monospaced, `dim`.
  A search's results keep tafs cloud's groups, as the iPad's `RecordResults`. The iPad adds the
  day's spend ("€640 spent"); the Record sends each call's amount as text only, so the Mac
  doesn't add them up.
- **A call** is a panel (radius 14, padding 14): its status dot (9), then its taf's dot and
  "Taf · what it did · amount" in 14 semibold with its time at the right in 12 monospaced
  `dim`, then what it was about and how it went, at 13 `soft`.


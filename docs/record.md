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

- The search box shows tafs cloud's hint; Return searches.
- Each group has tafs cloud's title; each row has a dot for how it went (green done, amber
  held, red refused), the call, its taf and what it is about, its amount and its time.
- The next page loads when the end of the list comes into view, and joins its group.
- A cursor tafs cloud no longer takes (a call was made since) starts the search again.
- A slower answer to an older search is dropped.

## Not yet

Opening a case from a row, a taf's detail, and exporting receipts.

## Tests

`scripts/test.sh record` checks the page as tafs cloud sends it, the escaping and the limit,
an ungrouped page, an unreadable one, a refusal's code, a case, the paging and the restart.
It writes `build/screenshots/record-*.png`. There is no fixture for the Record in kiff/tafs's
`contracts/` yet: the shape is taken from kiff/tafs's `docs/api.md` and the iPad app's reader.

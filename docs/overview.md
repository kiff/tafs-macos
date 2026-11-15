# The Overview

Today, across the person's tafs, one line each. It opens behind the mascot and the app's
name, at the top of the sidebar.

## What is read (`Home`, `CloudClient.home()`)

`GET /v1/home` on tafs cloud. tafs cloud counts and words everything; the app draws it.

| Drawn | From |
|---|---|
| The first line ("1 taf working.") | `headline.words` |
| What waits for the person ("2 need you.") | `needs_you.words`, shown when `needs_you.count` is above 0 |
| A taf's name and colour | `name`, `color` |
| What it does | `job_summary` |
| **Now** | `work.line`; if tafs cloud sent none, `next_run_words`; if neither, a dash. The app never writes a line of its own. |
| A warning colour on Now | `work.attention` |
| What is wrong with it | the first of `health.lines`, when `health.level` isn't `healthy` |
| How many of its calls wait | `waiting` |

- A list whose tafs don't read is unreadable. It is never shown as "No tafs yet."
- A headline or a count that isn't the expected shape is left out; the list is still drawn.

## The layout

The iPad's: a large title and its line, the four columns' headings, and plain rows with no
panel behind them. A taf has its coloured rounded square. The Card and Last result columns
keep their place and their headings, and stay empty until they are read.

## Not yet

- **The Card and Last result columns** of the iPad's Overview. The iPad app works the Card's
  line out itself from many fields of the answer. There is no fixture for `GET /v1/home` in
  kiff/tafs's `contracts/` yet, and this app won't redo that arithmetic from a reading of
  another app's code.
- Opening a taf from its line, and the tafs in the sidebar.
- Reading the list again by itself. It is read when the screen opens.

## Tests

`scripts/test.sh overview`: the list as tafs cloud sends it, what Now falls back to, a taf
with only its required fields, an unreadable list, a malformed headline. It writes
`build/screenshots/overview-*.png`.

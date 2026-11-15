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

The iPad's: a large title and its line; **NEEDS YOU**, when something waits; the four
columns' headings in plain 11 bold; and plain rows with no panel behind them.

- **NEEDS YOU** (amber, mono 12): one row per call KIFF held, an amber dot, "Taf · what it
  asks" and "answer by {time}", on the raised ground. When tafs cloud counts more than the held
  calls (Coach's chats, steps), a last row has its `needs_you.words` and a chevron. Every row
  opens Needs you.
- **A taf's row:** its coloured square and name; **Now**, tafs cloud's line alone; **Card**,
  the first Card's one line ("€1,960 left today of €2,000", `TafCard.line`, from KIFF's numbers
  as #39 reads them), else "–"; **Last result**, "–". **A row opens its taf's page**, and
  "Each line opens the taf." says so under the table.

## Not yet

- **The Last result column.** The iPad reads each taf's runs and its last report (`GET
  /v1/tafs/{id}/runs`, then the report). There is no contract for either in kiff/tafs's
  `contracts/` yet, so the column says "–".
- Who uses a taf, under its name, for someone who manages it.
- Reading the list again by itself. It is read when the screen opens, and with each round.

## Tests

`scripts/test.sh overview`: the list as tafs cloud sends it, each Card's one line (in the
`taf` part), what Now falls back to, a taf
with only its required fields, an unreadable list, a malformed headline. It writes
`build/screenshots/overview-*.png`.

# Plan & usage

The balance now and the period's credits, in tafs cloud's words. **This screen only reads.**
Nothing is bought, raised or changed from the Mac.

## What is read (`Usage`, `CloudClient`)

| Call | Route | What |
|---|---|---|
| `balance()` | `GET /v1/usage/balance` | The balance's words, its meter (0 to 100), a detail line, a warning, and the plan's line. |
| `credits(previous:)` | `GET /v1/usage/credits`, or `?period=previous` | The period's total in words, a line for each taf that used credits, Coach's own use, what wasn't counted, and a note. |

- Every amount and every line is tafs cloud's. The app works out nothing.
- **The meter is how much is used**, as tafs cloud's own page says, kept within 0 to 100 as
  the phones keep it. With no number there is no bar.
- A balance without its state or its words is unreadable. A credits row that doesn't read is
  left out; the period is still drawn.

## The screen (`UsageView`, `UsageModel`)

Laid out as the iPad's: the screen's name small and centred at the top, then panels (radius
18, as `Look.panelRadius`). The balance's panel is edged in red while the tafs wait and in
amber with a warning, and the warning takes the same colour.

- **Balance**, a panel: the words (red while the tafs wait), the meter (the iPad's `Meter`: a
  5-high capsule on ink at 10%, green when fine, amber otherwise), then the detail, the warning and the plan's line.
- **Credits**, a panel: its heading, Last period and This period as the iPad's two-part
  switch, and the total.
- **Each taf's line** is its own panel, with its pace under it.
- **Coach's use past what's included** (`coach`) is a panel of its own after the tafs' rows,
  as on the iPad. It is counted, so it is never under what wasn't.
- **What wasn't counted**, a panel: tafs cloud's total line, then **why each wasn't**, a line
  each (`not_counted.lines[].words`: "Coach, included · 3 runs"). A reason with no words, or
  one that doesn't read, is left out, never the others.
- tafs cloud's note under them.
- Every line is drawn as sent (`Text(verbatim:)`).
- **Each half is read on its own.** One that can't be read says so and leaves the other.

## Not on the Mac

Buying credits or a plan, restoring purchases and raising the spend limit. The phones do
these through their stores; the Mac has no store. A request to an admin, a taf's runs behind
its line, and Manage are not built.

## Tests

`scripts/test.sh usage`: the balance and the credits as tafs cloud sends them, a meter out of
range, unreadable answers, a 503's code, each half failing alone, the period asked for, and
**that nothing but `GET` is ever sent**. It writes `build/screenshots/usage-*.png`.

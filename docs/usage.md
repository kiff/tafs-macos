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

- **Balance**: the words (red while the tafs wait), the meter (green when fine, amber
  otherwise), then the detail, the warning and the plan's line.
- **Credits**: This period or Last period, the total, each taf's line with its pace under
  it, then Coach, what wasn't counted, and the note.
- **Each half is read on its own.** One that can't be read says so and leaves the other.

## Not on the Mac

Buying credits or a plan, restoring purchases and raising the spend limit. The phones do
these through their stores; the Mac has no store. A request to an admin, a taf's runs behind
its line, and Manage are not built.

## Tests

`scripts/test.sh usage`: the balance and the credits as tafs cloud sends them, a meter out of
range, unreadable answers, a 503's code, each half failing alone, the period asked for, and
**that nothing but `GET` is ever sent**. It writes `build/screenshots/usage-*.png`.

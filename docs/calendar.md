# The Calendar

The tafs' scheduled work still to come, a week at a time. It is the sidebar's Calendar item,
so no other screen draws a second way to it.

## What is read (`Agenda`, `CloudClient.calendar(from:to:)`)

`GET /v1/calendar?from=&to=` on tafs cloud, for the seven days shown.

- tafs cloud works out every occurrence in the account's zone and gives each its day and
  time there. **The app converts no zone**, so it draws the same as the phones.
- Each event has its taf's name and colour, its time, and tafs cloud's words for what it is
  ("Every day at 09:00", "Try 2 of 3"). A dense schedule's day is one event with ×108.
- tafs cloud's own line for the range is drawn above the days ("3 to come"), in red when the
  account is halted and nothing runs.
- An event this app can't read is left out. An answer with no list of events is unreadable:
  it is never shown as an empty week.

## The screen (`CalendarView`, `CalendarModel`)

- **Seven days, Monday to Sunday**, each with its events by time, or "Nothing scheduled on
  this day."
- **Today** is marked with a pill on its day, and is the date in the **account's** zone, as
  tafs cloud names it. The Today button comes back to this week.
- The arrows move by a whole week. A slower answer for a week left behind is dropped.
- The title is the shared line for the week, also across two months or two years.

## Dates (`Days`)

Dates are `YYYY-MM-DD` with no zone: a day is a day. A date that isn't one (`2026-02-30`) is
refused, never rolled over.

## Not yet

The Day and Month views, choosing a date, and opening a taf from an event.

## Tests

`scripts/test.sh calendar`: the answer as tafs cloud sends it, an unreadable one, a halt, a
week across a month's and a year's end, dates that aren't dates, today in the account's zone,
the weeks asked for when moving. It writes `build/screenshots/calendar-*.png`.

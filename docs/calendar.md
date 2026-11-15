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

To the iPad's layout:

- **On the left, the month's card**: six weeks, Monday first, today ringed in amber, the days
  shown shaded. Its arrows turn its page without changing the days shown; a click on a day
  goes to it. Under it, the **agenda**: each day's events with tafs cloud's words, or tafs
  cloud's own line when there are none.
- **On the right**: Today, the arrows, the range's title, and the day shown as a date picker
  in the app's language (choosing a date goes there); under them, tafs cloud's line when it
  **halted** (in red) or **cut the read at its most** (`more`); then **Day** and **Week**;
  then the days' columns over an **hour grid**, 08:00 to 18:00, wider when an event falls
  outside.
- **Each hour is a row**, and each day's events in that hour are **stacked** in its cell, as
  on the iPad: two at the same minute both stay readable, and a busy hour grows its row. An
  event is the iPad's chip: its taf's dot and name on its colour, lightly; "09:00 · Name" in
  Day; "×n" for a repeat.
- With no event in the range, the app's line is centred under the grid.
- **Today** is the date in the **account's** zone, as tafs cloud names it. The first read
  names that zone: if its today is another day than the Mac's, the screen goes there.
- The arrows move by a week in Week and by a day in Day. A slower answer for days left behind
  is dropped.

## Dates (`Days`)

Dates are `YYYY-MM-DD` with no zone: a day is a day. A date that isn't one (`2026-02-30`) is
refused, never rolled over.

## Not yet

The Month view, and opening a taf from an event.

## Tests

`scripts/test.sh calendar`: the answer as tafs cloud sends it, an unreadable one, a halt, a
week across a month's and a year's end, dates that aren't dates, today in the account's zone,
the weeks asked for when moving. It writes `build/screenshots/calendar-*.png`.

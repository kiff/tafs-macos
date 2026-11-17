# The Calendar

The tafs' scheduled work still to come, by the day, the week or the month. It is the
sidebar's Calendar item, so no other screen draws a second way to it.

## What is read (`Agenda`, `CloudClient.calendar(from:to:)`)

`GET /v1/calendar?from=&to=` on tafs cloud, for the **six weeks of the month card** around the
day the screen is on, as the iPad reads (`Days.range(of:)`). So the card can mark every day
with work whatever the view, and moving within those six weeks reads nothing more.

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

- **On the left, the month's card**: six weeks under the weekday letters (11 bold, dim),
  Monday first. Each cell is at least 38 high, its number 13 pt, with up to three 5-pt dots in
  the colours of its tafs with work (`Page.marks(on:)`). The day the screen is on is filled
  amber, today ringed. Its arrows go to the same day a month before or after (the month's
  last when it is shorter), as on the iPad; a click on a day goes to it.
- **Under the card and the grid, full width**, as the iPad's wide layout
  (`CalendarView.swift:49-64`), the **agenda**: the days shown that hold work, each under its heading (14
  semibold, amber for today), each event on a panel (radius 10, padding 10): its time 13 mono
  in 46 points, a 9-pt dot, its name 14 semibold and tafs cloud's words 12 dim. tafs cloud's
  own line when there are none.
- **On the right**: the Today pill, the arrows, the range's title, and the day shown as the
  iPad's date pill: a medium date in the app's language ("Nov 15, 2026", `Days.medium`) on a
  raised capsule. macOS 12's compact picker is a numeric field, so the pill is a button that
  opens the month's calendar in a popover; choosing a day goes there and closes it; under them, tafs
  cloud's line when it **halted** (in red) or **cut the read at its most** (`more`); then
  **Day / Week / Month**, segmented, at most 320 wide; then the days.
- **The Today pill** has its padding and stroke on its word, and both are fixed, so no width
  cuts its round ends in any language. The stroke is drawn inside the label's bounds
  (`strokeBorder`): on the edge, half of it falls outside and is clipped to a sliver. It is quiet while today is shown.
- **Day and Week** draw the days' columns over an **hour grid**, 08:00 to 18:00, wider when
  an event on a day shown falls outside.
- **Month** draws the month card larger: cells at least 64 high, 15-pt numbers, the dots, and
  how many firings each day holds (`Page.count(on:)`).
- **Each hour is a row**, and each day's events in that hour are **stacked** in its cell, as
  on the iPad: two at the same minute both stay readable, and a busy hour grows its row. An
  event is the iPad's chip: its taf's dot and name on its colour, lightly; "09:00 · Name" in
  Day; "×n" for a repeat, kept whole on the name's line.
- **A narrow week keeps a few characters of each name** (`WeekChip`): the chip measures its
  column (the grid's width, less the hours, by the days), and keeps at least 34 points of the
  name, a few characters and "…". The dot gives way first, then the ×N; the name never does.
  The colour stays on the chip's ground, and VoiceOver still says the count.
- With no event on the days shown, the app's line is centred under the grid.
- **Today** is the date in the **account's** zone, as tafs cloud names it. The first read
  names that zone: if its today is another day than the Mac's, the screen goes there.
- The arrows move by a day, a week or a month, as the view is. A slower answer for days left
  behind is dropped.

## Dates (`Days`)

Dates are `YYYY-MM-DD` with no zone: a day is a day. A date that isn't one (`2026-02-30`) is
refused, never rolled over.

## Not yet

Opening a taf from an event.

## Tests

`scripts/test.sh calendar`: the answer as tafs cloud sends it, an unreadable one, a halt, a
week across a month's and a year's end, dates that aren't dates, today in the account's zone,
the six weeks asked for and when moving reads again, a month on, each day's dots and count,
Day, Week and Month, and what a week chip keeps as its column narrows (`WeekChip.fit`). It
writes `build/screenshots/calendar-*.png`, Month as `calendar-month-en.png`, and the week with
its agenda as `calendar-week-light.png`, `calendar-week-dark.png` and, narrow,
`calendar-week-narrow-light.png`.

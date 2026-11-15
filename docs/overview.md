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
| **Now** | By its `state`, as the iPad's `KIFFMapping.taf` (`Home.Taf.now`): waiting, "Waiting for you"; paused, "Paused"; halted, "Halted · resume it from Halt"; working and `unscheduled`, "Works from its chat"; working, `next_run_words`, else "Next run {time}" from `next_run`, else "Running"; idle, "Acting under KIFF"; any other, "Card not active". A setup stopped partway (`finish`, with its chat and words) says tafs cloud's words instead. |
| **What went wrong** | `Home.Taf.healthNow`: `work.line`, only when tafs cloud flags it (`work.attention`) or an idle taf's health needs attention. The sidebar's row shows it in place of Now. |
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
- **A taf's row:** its coloured square and name; **Now**, by its state (above); **Card**,
  the first Card's one line ("€1,960 left today of €2,000", `TafCard.line`, from KIFF's numbers
  as #39 reads them), else "–"; **Last result**, as the iPad's (below). **A row opens its
  taf's page**, and "Each line opens the taf." says so under the table.

## Last result (`Runs`)

While the Overview is shown, each taf's runs are read once (`GET /v1/tafs/{id}/runs`), then
the report of its newest run with a chat (`GET /v1/tafs/{id}/runs/{session}`). The column
says, by the iPad's rule: the report's first line without Markdown's marks; else why the run
stopped, from the runs list (a report never says); else "Last ran at {time}"; else "Nothing
yet". A taf whose runs can't be read keeps "–". The shapes are tafs cloud's contracts,
`taf-runs.json` and `taf-run-report*.json`, read by `scripts/test.sh contracts`.

## With no taf: the recipes (`Recipes`, `HomeRecipesView`, `RecipeSheet`)

Ported from the iPad's `HomeRecipes.swift` (`HomeRecipes`, `OwnWordsRow`, `RecipeRow`,
`AppMarks`, `RecipeSheet`), `TafsCloud.Recipes` and Home's no-taf branch in `HomeView.swift`.

- **Read** with each list read that has no taf, never with tafs; a read that fails keeps what
  was read. As strict as the iPad: a category or recipe that doesn't read, a recipe's
  `category`, `line` or `say` that isn't words, or a `shown` that isn't a flag fails the read.
  An app that doesn't read is left out, a label that isn't words is "". Only `proved` and
  `sample` are trimmed, so `say` goes in Coach's box as sent.
- **Listed** (`home.shown`, the sheet's `labels`, a category with a recipe): tafs cloud's line
  (also in the sidebar), **Say it in your own words**, a chip per category in its colour, and
  each recipe led by the problem it ends, its line and its apps (one mark each), on an edge in
  its category's colour. Its sheet: what it ends, what that costs today, its Card in zones,
  where its proof run passed and what it reported, and **Hand it to Coach**, which puts `say`
  in Coach's box. Nothing is sent until the person sends it.
- **Not listed:** tafs cloud's `home.words`, else the app's own line ("No tafs yet." and, by
  who may use Coach, `home.empty.coach` or `home.empty.shared`), then Own words.
- **Who may use Coach** (`mayUseCoach`): KIFF's `use` for the Setup agent, else
  `members.manage`. Without it, no Own words and no Hand it to Coach.

## Not yet

- Handing a recipe to a **new** Coach conversation (`newSetupChat`, `setupHanded`), and Own
  words opening one (`startNewTaf`): Coach on the Mac has one conversation, so the words go in
  its box and Own words opens it as it is.
- The apps' logos beside their names, and `RecipeGallery` with its sample's label.
- Who uses a taf, under its name, for someone who manages it.
- Reading the list again by itself. It is read when the screen opens, and with each round.

## Tests

`scripts/test.sh overview`: the list as tafs cloud sends it, each Card's one line (in the
`taf` part), what Now falls back to, a taf
with only its required fields, an unreadable list, a malformed headline. It writes
`build/screenshots/overview-*.png`, and `overview-contract-en.png` from tafs cloud's own
`home.json`, whose taf has a Card, so the Card column shows its line.

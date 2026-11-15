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

Every cell of a taf's row is centred on the row's height, which its avatar sets, so Now,
Card and Last result sit level with its name. The iPad's grid aligns its cells to the top
(`Grid(alignment: .topLeading)`, `ShareViews.swift:315`); on macOS 12 the owner asked for
them centred, so the Mac differs here.

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
- **Own words** starts a new taf, as the iPad's `startNewTaf` (`HomeView.swift:272`): a new
  conversation in Coach, so Coach mode's start shows, whatever Coach was showing.

## Every job: the gallery (`Gallery`, `RecipeGallerySheet`)

Ported from the iPad's `RecipeGallery.swift` (`RecipeGallerySheet`, `GalleryMode`,
`GalleryChoice`), `TafsCloud.Gallery` and the gallery's places in `HomeSplitView.swift`
(the sidebar's Explore row and strip, + New, `sheetRecipes`, `actOnGalleryChoice`).

- **Read** (`GET /v1/recipes/gallery`) with each list read, with tafs or without; a read that
  fails keeps what was read, and a tafs cloud without it (404) leaves none. Everything reads
  leniently, as on the iPad: a category or job that doesn't read is left out, never the
  gallery; missing words are none.
- **Start a new taf** opens the gallery where tafs cloud sends it, else Coach as before. It
  leads with **Say it in your own words** (Coach with nothing in its box), for someone who may
  use Coach, then tafs cloud's "All jobs" and every job by category, as the recipes on the
  Overview are drawn. A job's sheet hands it to Coach with the sheet's own words.
- **Explore jobs**, in the sidebar under the tafs, with or without tafs, once tafs cloud sends
  its words and lists a job: the same gallery under "Explore jobs", with no own-words row, each
  job's one action "Try it with Coach".
- **The strip**, in the sidebar with tafs, where tafs cloud shows it: its title, its jobs in
  its order (an id the gallery doesn't list is skipped), each on its category's colour and
  opening its sheet, then "See all jobs" (else "All jobs"), unless the strip shows them all.
- A job's sheet draws from the Overview's recipes when the job is on them, else the gallery's,
  with `/v1/recipes`' sheet words where the gallery sends none; a sample is under tafs cloud's
  label for it.
- What's chosen in the gallery is acted on once it has closed: a job goes to Coach's box, own
  words open Coach.

## Not yet

- Handing a recipe to a **new** Coach conversation (`newSetupChat`, `setupHanded`): its words
  go in the box of the conversation Coach shows.
- The apps' logos beside their names.
- A contract fixture for the gallery in kiff/tafs's `contracts/`: the shape is the iPad's reader.
- Who uses a taf, under its name, for someone who manages it.
- Reading the list again by itself. It is read when the screen opens, and with each round.

## Tests

`scripts/test.sh overview`: the list as tafs cloud sends it, each Card's one line (in the
`taf` part), what Now falls back to, a taf
with only its required fields, an unreadable list, a malformed headline. It writes
`build/screenshots/overview-*.png`, and `overview-contract-en.png` from tafs cloud's own
`home.json`, whose taf has a Card, so the Card column shows its line.

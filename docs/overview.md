# The Overview

Today, across the person's tafs, one line each. It opens behind the mascot and the app's
name, at the top of the sidebar.

## What is read (`Home`, `CloudClient.home()`)

`GET /v1/home` on tafs cloud. tafs cloud counts and words everything; the app draws it.

| Drawn | From |
|---|---|
| The first line ("1 taf working.") | `headline.words` |
| What waits for the person ("2 need you.") | Needs you's count and line, the iPad's `needsYouCount` and `needsYouWords` (docs/approvals.md): `needs_you`, else the app's own count |
| When it last ran (`Home.Taf.lastRun`) | `last_run` |
| A taf's name and colour | `name`, `color` |
| What it does | `job_summary` |
| **Now** | By its `state`, as the iPad's `KIFFMapping.taf` (`Home.Taf.now`): waiting, "Waiting for you"; paused, "Paused"; halted, "Halted · resume it from Halt"; working and `unscheduled`, "Works from its chat"; working, `next_run_words`, else "Next run {time}" from `next_run`, else "Running"; idle, "Acting under KIFF"; any other, "Card not active". A setup stopped partway (`finish`, with its chat and words) says tafs cloud's words instead. |
| **What went wrong** | `Home.Taf.healthNow`: `work.line`, only when tafs cloud flags it (`work.attention`) or an idle taf's health needs attention. The sidebar's row shows it in place of Now. |
| A warning colour on Now | `work.attention` |
| What is wrong with it | the first of `health.lines`, when `health.level` isn't `healthy` |
| How many of its calls wait | `waiting` |
| Its labels (`Home.Taf.labels`) | `labels: [id]`, on a taf that has any |
| The account's labels (`HomeLabel`) | `labels: [{id, name, color, count, waiting, headline}]`, in the order to show them, and `labels_words.all` for the first chip |

- A list whose tafs don't read is unreadable. It is never shown as "No tafs yet."
- A headline or a count that isn't the expected shape is left out; the list is still drawn.

## The layout

The iPad's: a large title and its line; **NEEDS YOU**, when something waits; the four
columns' headings in plain 11 bold; and plain rows with no panel behind them.

- **NEEDS YOU** (amber, mono 12): one row per call KIFF held, an amber dot, "Taf · what it
  asks" and "answer by {time}", on the raised ground. When tafs cloud counts more than the held
  calls (Coach's chats, steps), a last row has its `needs_you.words` and a chevron. Every row
  opens Needs you.
- **The order** is the iPad's `listedTafs` (`AppModel.swift:546-557, 615-641`, `ListOrder`): a
  taf waiting on the person first (a call held, as tafs cloud counts it), then the one at work
  most recently, then tafs cloud's order. It is settled when the list's tafs change, not on
  every read, so it doesn't move while the person looks at it; a taf newly waiting goes to the
  top at once. The iPad knows "most recently" from KIFF's record and each taf's chat, which this
  Mac doesn't read for every taf: it goes by the list's `last_run`. The sidebar's tafs are in
  the same order. tafs cloud sends no `relevant_now` on `/v1/home` at the pin (`home.json`).
- **A taf's row:** its coloured square and name; under its name, for whoever manages the taf,
  who uses it, as the iPad's `usedBy` (`ShareViews.swift:378-394`, `Shares.usedBy`): each
  group and person it's shared with, then how many people ("Support, ana@acme.com · 4 people"),
  or "Not shared"; read from KIFF's grants when the Overview shows, once KIFF says which tafs
  the person manages; **Now**, by its state (above); **Card**,
  the first Card's one line ("€1,960 left today of €2,000", `TafCard.line`, from KIFF's numbers
  as #39 reads them), else "–"; **Last result**, as the iPad's (below). **A row opens its
  taf's page**, and "Each line opens the taf." says so under the table.

Every cell of a taf's row is centred on the row's height, which its avatar sets, so Now,
Card and Last result sit level with its name. The iPad's grid aligns its cells to the top
(`Grid(alignment: .topLeading)`, `ShareViews.swift:315`); on macOS 12 the owner asked for
them centred, so the Mac differs here.

## Labels (`HomeLabels`, `LabelChips`)

As the iPad's Overview (kiff/tafs#1173, `ShareViews.swift` and `BriefView.swift:142-169`,
`378-427`) and kiff/tafs `docs/labels.md`. A label is a name and a colour Coach gives a taf; the
apps only filter by it.

- **The chips**, under NEEDS YOU: All, then two labels, then "+N", which shows the rest once
  clicked. Each label has its count, and an amber dot while one of its tafs waits for the person.
  The chosen one is inverted; clicked again, it goes back to All. The first chip's word is
  tafs cloud's (`labels_words.all`), else the app's "All" (`home.labels_all`, as the iPad's `labelsAllWords`).
- **A chip filters the table** to the tafs carrying it, in Home's order: filtering never
  reorders. A label that's gone shows them all. The list opens on All.
- **A taf's row** shows two of its labels as small grey chips under its name, then "+1".
- **With no labelled taf**, Home sends no labels: there's no chip row, and the Overview is as
  before. A label or a taf's labels of another shape read as none, never the list.

## Last result (`Runs`)

While the Overview is shown, each taf's runs are read once (`GET /v1/tafs/{id}/runs`), then
the report of its newest run with a chat (`GET /v1/tafs/{id}/runs/{session}`). The column
says, by the iPad's rule (`ShareViews.swift:410-418`): the report's first line without
Markdown's marks; else why the run stopped, from the runs list (a report never says); else
"Last ran at {time}", by the list's `last_run`; else "Nothing yet". Before its runs are read,
the list's `last_run` says it ("Last ran at {time}", else "Nothing yet"), never "–". A taf
whose runs can't be read says so ("Its runs couldn't be loaded. {why}"), as the iPad's
`loadReport`. Only an agent tafs doesn't run has "–". The shapes are tafs cloud's contracts,
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
  each recipe led by the problem it ends, its line and its apps, on an edge in its category's
  colour. Each app is its logo, 18 points, then its name, as the iPad's `AppMarks` and `AppMark`
  (`HomeRecipes.swift:134-165`): the logo only from tafs cloud's own `/v1/logos/` path
  (`Recipes.App.logo`, `Apps.logoPath`), read as Connect apps reads its logos (`AppLogos`,
  docs/connections.md › Logos). With none, or one refused or that doesn't decode, the name alone. Its sheet: what it ends, what that costs today, its Card in zones,
  where its proof run passed and what it reported, and **Hand it to Coach**, which opens a new
  conversation in Coach with `say` in its box, as the iPad's `handRecipeToCoach`
  (`CoachModel.handRecipe`), whatever Coach was showing. The gallery's jobs do the same. Nothing
  is sent until the person sends it. (The brief's next move, by contrast, goes in the box of the
  chat shown, as the iPad's `startNextMove`.)
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
  gallery; missing words are none. Each job's apps carry their logos, drawn as the Overview's
  recipes draw them (above), in Start a new taf and in Explore jobs.
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
- **The list is read again by itself**, as the iPad's `refresh`: when the screen opens, at once
  when the app comes back to the front (the iPad's scene becoming active), and after this Mac's
  own acts that change it (an answer in Needs you, a halt, chats set aside). The iPad has no
  timer: it also reads after a run it saw at work ends, or a call is held in its chat. This Mac
  also reads the lists every 5 minutes while the window is open (`WindowReads`, held calls every
  minute), which catches those within that time.

## Not yet

- Handing a recipe to a **new** Coach conversation (`newSetupChat`, `setupHanded`): its words
  go in the box of the conversation Coach shows.
- A contract fixture for the gallery in kiff/tafs's `contracts/`: the shape is the iPad's reader.

## Tests

`scripts/test.sh overview`: the list as tafs cloud sends it, each Card's one line (in the
`taf` part), what Now falls back to, a taf
with only its required fields, an unreadable list, a malformed headline. It writes
`build/screenshots/overview-*.png` (with `overview-labels-en`, `overview-labels-money-en` and
`overview-labels-fr` for the chips), `overview-contract-en.png` from tafs cloud's own
`home.json`, whose taf has a Card, so the Card column shows its line, and
`overview-parity-en.png` and its `-dark` twin: the rows in the iPad's order, with who uses each
taf and its Last result before its runs are read. The order, `usedBy`, `last_run` and Halt all's
rule are tested with no Mac.

The apps' logos (`RecipeLogosTests`, and on a Mac `AppMarksScreenTests`): only tafs cloud's own
path is kept, in the recipes and the gallery; a job's app draws its logo, then its name, and a
refused or dropped logo the name alone. It writes `explore-jobs-logos-en.png` and
`gallery-logos-en.png`, each with its `-dark` twin.

# Your brief and a mission's log

"Your brief" is what tafs got done and what needs the person, twice a day, in Needs you's place
once tafs cloud serves it. It's ported from the iPad's (kiff/tafs#1173: `BriefView.swift`,
`TafsCloud+Brief.swift`, the brief in `AppModel.swift`). Every word, count, order and urgency is
tafs cloud's (kiff/tafs `docs/missions.md`, "Your brief"); the app draws it and decides nothing.

## When it shows (`BriefModel.load`)

`GET /v1/brief?label=` is read with each 30-second round, beside the held calls and the tafs.

- **The switch is the route itself:** until tafs cloud serves it, it answers 404, there's no brief,
  and Needs you is as today.
- **Any other failure, or a brief with no decision, nothing done and no next move,** keeps Needs
  you too. The brief never hides what waits.
- **Once there's a brief,** the sidebar's Needs you row takes tafs cloud's name for it ("Your
  brief", `words.title`), and the screen is the brief.
- **A session that ends** keeps nothing: the brief goes, and a read or a Later still on its way is
  dropped.

## The screen (`BriefScreen`, `DecisionCard`, `CaseRow`)

As the iPad's width: the title and its time, the label chips (as the Overview's, filtering the
brief), then two columns.

- **Decisions,** on the left: each card has its taf, the question, Coach's recommendation with its
  why (only when tafs cloud sends a why), what happens meanwhile, why it can't wait when it can't,
  and its answers. The recommended answer is filled; the others are outlined, a decline in red.
  "N more decisions" follows, when tafs cloud counts more.
- **Done**, on the right: each mission's cases (green once closed, amber while waiting), its value,
  and Evidence, which opens the mission's log.
- **The next move**, under Done: its Start puts the words in Coach's box, to edit and send, for
  someone who may use Coach. Its dismiss hides it here.
- **The rest**, under that: tafs cloud's line for what needs nothing now, and Needs you's own count
  of what the brief doesn't show. It opens Needs you.

## Answers: nothing is signed from the brief

- **An answer opens Needs you,** where the held call or step is answered, with nothing chosen
  ahead: the answer is never part of where it goes (`Brief.destination`). A held call goes to its
  own card, a step to its step, anything else to Needs you's list. Needs you shows a back row to
  the brief.
- **Later** posts `POST /v1/brief/decisions/{id}/later`, the id one escaped path segment
  (`CloudClient.escaped`), with no signature. The card is set aside only once tafs cloud has
  moved it; a refusal keeps it, with tafs cloud's words. An urgent decision never offers Later,
  whatever was sent.
- **Needs you beyond the brief** is matched item by item, never by number: a held call or a step
  the brief shows is matched by its `ref` (`hold:<id>`, `step:<handoff>`), and what the brief
  can't carry is counted (`Brief.needsYouBeyond`).

## A mission's log (`MissionLogView`)

`GET /v1/missions/{id}/log`, in a sheet of the Mac's own (Close, or Esc), read only, newest first,
by day in the account's zone, as the Record titles its days. Each entry says who (a taf by its
name, "A taf" once it's removed, Coach for the lead, "You" or the person's name), its kind as a
coloured word, the time, its words, its evidence (references only, never data) and its value. A
removed taf's entries stay, greyed.

## Mac differences

- **The brief is the sidebar's Needs you entry,** where the iPad has it in Needs you's tab and
  sidebar item. Two columns always, as the iPad's regular width.
- **A held call has no page of its own on the Mac:** Needs you's list holds its card, and Approve
  isn't on macOS 12 yet. So opening any decision shows Needs you's list.
- **No alert routing by `brief_kind`:** the Mac's alerts are its own, posted for held calls while
  the app is open (`Notifier`), and none comes from tafs cloud's push yet. A clicked alert opens
  Needs you, which is the brief once there is one.
- **The mission log's Ask Coach** isn't here yet.
- **No sample brief:** the Mac has no sample mode.

## Tests

`scripts/test.sh brief`:
- **Core:** the brief as tafs cloud sends it; Done's mission as words or `{id, name}`; a
  recommendation only with its why; no Later when urgent; an empty brief; where each decision
  goes; the item-by-item match; the routes (the label's query, Later's escaped id with no
  signature, the log's mission); and the log's authors, removed entries and times.
- **Mac:** 404 and no brief; the tab's name; a failure or empty brief keeping Needs you; Later
  once, set aside after; a refused Later kept with its words; no Later for an urgent decision; a
  label filtering it; the session's end; the screen sending nothing; and screenshots `brief-en`,
  `brief-fr` and `mission-log-en`.

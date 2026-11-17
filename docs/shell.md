# The window and its sidebar

The window is the iPad app's full-width layout: a sidebar on the raised ground, and the
screen it opens beside it.

## The sidebar

Top to bottom, as on the iPad:

| Part | What |
|---|---|
| The mascot and "tafs" | Opens the Overview. |
| Needs you, Record, Calendar, Plan & usage, Connect apps | One row each: its symbol and its name, in semibold. Needs you ends with the number waiting, as a plain grey number, never a badge. The open screen's row has the iPad's rounded grey ground (`Palette.chosen`). |
| NEEDS YOU | Only when calls are held: each one with an amber dot, its taf's name and what it asks, as the iPad names the call ("Deploys: Run migration 0042 · migrate", see `docs/approvals.md`), then KIFF's reason and the time to answer by. A call whose taf isn't listed shows what it asks alone. A row opens Needs you. |
| YOUR TAFS | Each taf as the iPad's row: its 34-point avatar (`TafAvatar`: its colour, corners at 0.3 of its size, its initial in rounded bold at half its size), its name in 15 semibold, and in 13, as the iPad's `tafRow`: what went wrong last (`healthNow`), red when failing and amber otherwise; a setup stopped partway, amber; else Now by its state (docs/overview.md). With none, tafs cloud's own line for that ("Pick a job for your first taf."), and nothing when it sends none. |
| Start a new taf | The brand's gradient button. It opens Coach, where a taf is made. |
| Coach | The dark button under it. |
| Account | With who is signed in under it. Its symbol is the iPad's: an outlined person in the soft colour, filled and amber (`amberText`) while Account is open. |

- The order, the symbols and the names are the iPad app's (`Screen`, in `Sources/Core/shell`).
  Calendar is a sidebar item, so no screen draws a second way to it.
- The headings NEEDS YOU and YOUR TAFS are the shared `Eyebrow`: mono 12, tracking 0.7.
- The sidebar's small lines (a taf's line, YOUR TAFS, the account under Account) use the soft
  text colour where the iPad uses dim: dim is 4.23:1 on the raised ground in light, under
  the 4.5:1 that small text needs.
- NEEDS YOU's heading is amber as text (`amberText`), not the amber itself: the amber is
  under 4.5:1 on the raised ground. The rows' words are KIFF's and the taf's, drawn as sent.
- The tafs in the sidebar don't open anything yet: a taf's own page arrives in its pull request.
- **From a taf's page**, as the iPad's Coach mode opens over it: Improve in Coach and Change
  the workflow with Coach open Coach on a new conversation about the taf, and an `ask_coach`
  card's Ask Coach opens it with the card's words in its box, nothing sent. Each is only for
  someone who manages the taf and may use Coach, and Coach's Back returns to the screen open
  before the taf. The ring's + opens Connect apps (docs/taf.md).

## Reading at launch, and how long it takes

- **The held calls and the tafs are read side by side**, at launch and with each 30-second
  round, as the iPad's `refresh` reads Home, the held calls and the account together
  (`AppModel.swift:1815-1821`). What this person may do with each taf is read after the list,
  as there. Who is signed in is read at once on its own. Back in front, a round is read at
  once, as the iPad's `refresh()` when its scene becomes active (`TafsApp.swift:60-68`).
- **The list last read shows in the first frame** (`RememberedHome`, the iPad's remembered
  list, `AppModel.swift:2022-2054`): the tafs alone from Home's answer, kept with their account
  in the app's preferences, shown only for that account and read again at once. It holds the
  tafs' names, states, colours, Cards and lines: never the rest of Home, a chat, a key or a
  session. It is replaced by each list read, and forgotten whenever a session is kept or ended:
  sign-in, pairing and sign-out, as the iPad's `useSession` and `forgetSession`
  (`AppModel.swift:868, 1323`). Sign-out marks the Overview ended before its first wait, so a
  read still on its way keeps nothing. A read that fails leaves a list on screen as it is, as
  the iPad's (`AppModel.swift:1909-1916`); only an empty screen says why.
- **`LaunchClock`** writes to the system log how long the app took from launch to its first
  window and to its first list read, once each ("tafs: first window after 412 ms"). Read
  them in Console, or with `log stream --predicate 'process == "tafs"'`.

## Words and the mascot

The build copies each shipped language's lines and the mascot from kiff/tafs at the pin into
the app ([shared.md](shared.md)). `Words.load()` picks the person's language, and every view
reads `@Environment(\.words)`.

**Dates and times are in the app's language, with this Mac's region** (`AppDates.locale`), as
the iPad's `Locale.current` with a per-app language: a Mac set to Spanish that shows the app in
English reads English dates, and an English app on a British Mac reads "15 Nov 2026" and 14:05. A fixed clock ("HH:mm") is `en_US_POSIX`, so no language or Mac setting makes it
12-hour. The Record's day titles (`AccountTime.dayTitle`) and the dial's times (`zonedShown`)
take the words' language too.

## Screenshots

`scripts/test.sh shell` writes `build/screenshots/sidebar-<language>[-dark].png` in English,
French and Portuguese at 1280 × 800, light and dark, drawn with no window on screen. The dark
ones have tafs and a held call; the light ones have neither.

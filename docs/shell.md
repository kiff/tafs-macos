# The window and its sidebar

The window is the iPad app's full-width layout: a sidebar on the raised ground, and the
screen it opens beside it.

## The sidebar

Top to bottom, as on the iPad:

| Part | What |
|---|---|
| The mascot and "tafs" | Opens the Overview. |
| Needs you, Record, Calendar, Plan & usage, Connect apps | One row each: its symbol and its name. Needs you ends with the number waiting, as a plain number. The open screen's name is in a heavier weight. |
| YOUR TAFS | Each taf with its coloured square, its name, and tafs cloud's line for where its work stands. With none, tafs cloud's own line for that ("Pick a job for your first taf."), and nothing when it sends none. |
| Start a new taf | The brand's gradient button. It opens Coach, where a taf is made. |
| Coach | The dark button under it. |
| Account | With who is signed in under it. |

- The order, the symbols and the names are the iPad app's (`Screen`, in `Sources/Core/shell`).
  Calendar is a sidebar item, so no screen draws a second way to it.
- The sidebar's small lines use the soft text colour: the dim one is under 4.5:1 on the
  raised ground.
- The tafs in the sidebar don't open anything yet: a taf's own page arrives in its pull request.

## Words and the mascot

The build copies each shipped language's lines and the mascot from kiff/tafs at the pin into
the app ([shared.md](shared.md)). `Words.load()` picks the person's language, and every view
reads `@Environment(\.words)`.

## Screenshots

`scripts/test.sh shell` writes `build/screenshots/sidebar-<language>[-dark].png` in English,
French and Portuguese at 1280 × 800, light and dark, drawn with no window on screen.

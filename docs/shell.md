# The window and its sidebar

The window is the iPad app's full-width layout: a sidebar on the raised ground, and the
screen it opens beside it.

## The sidebar

| Item | Opens | Its name's key |
|---|---|---|
| The mascot and "tafs" | Overview | `home.overview.title` |
| Needs you, with the number waiting | Needs you | `needs_you.title` |
| Record | Record | `record.title` |
| Calendar | Calendar | `calendar.heading` |
| Plan & usage | Plan and usage | `usage.title` |
| Connect apps | Connect apps | `connect.apps.title` |
| Coach, at the foot | Coach | `coach.title` |
| Account, at the foot | Account | `settings.title` |

- The order, the symbols and the names are the iPad app's (`Screen`, in `Sources/Core/shell`).
  Calendar is a sidebar item, so no screen draws a second way to it.
- The selected item sits on a panel. The second lines of the sidebar use the soft text
  colour: the dim one is under 4.5:1 on the raised ground.
- Each screen arrives in its own pull request. Until then its place shows its name.

## Words and the mascot

The build copies each shipped language's lines and the mascot from kiff/tafs at the pin into
the app ([shared.md](shared.md)). `Words.load()` picks the person's language, and every view
reads `@Environment(\.words)`.

## Screenshots

`scripts/test.sh shell` writes `build/screenshots/sidebar-<language>[-dark].png` in English,
French and Portuguese at 1280 × 800, light and dark, drawn with no window on screen.

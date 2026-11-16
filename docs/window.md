# The signed-in window

Once this Mac has a session, the window is the sidebar with each built screen in its place
(`SignedInView`). A screen that isn't built yet shows its name.

| Sidebar item | Screen | Doc |
|---|---|---|
| Needs you | The held calls, with Refuse | [approvals.md](approvals.md) |
| Account | Devices, and Sign out for this Mac | [account.md](account.md) |

## Staying up to date

While the window is open, KIFF's list of held calls is read again every 30 seconds. The
number beside Needs you is that list's count.

## Notifications

A macOS notification is posted for each call that appears while the app is open
(`Announced`, `Notifier`):

- **each call once**, and none of those already waiting when the window opened, since the
  person is looking at them;
- a call that left the list and is held again is announced again;
- the title is the app's line ("A taf needs you"); the body is KIFF's own words for the call,
  or "Open Needs you to answer." when KIFF sent none;
- **clicking one opens Needs you.**

macOS asks the person to allow notifications the first time one is posted. With the app
closed there is no notification yet: that needs a push, which needs a signed build.

## Signing out

Sign out ends the session at KIFF, then forgets it on this Mac whether or not KIFF answered,
and the window goes back to sign-in.

If KIFF couldn't be reached, this Mac is signed out here but its session is still valid at
KIFF until it expires. To end it for certain, sign this Mac out from another device's Devices.

## The pieces every screen shares (`Sources/App/base/Components.swift`)

Each is the iPad's own, at its sizes:

| Piece | As the iPad's |
|---|---|
| `ScreenTitle` | Rounded bold at 30 (the Overview) or 34 (the Record; Needs you draws its own at 34), and plain bold at 34 for the iPad's navigation titles (Account, Connect apps; Devices draws its own). Its line is 14 in `dim`. |
| `Eyebrow` | 12 monospaced, capitals, tracking 0.7, in `dim` unless a colour is given. |
| `Chip` | A pill, always 13 regular, padding 11/5: chosen, ink-filled with its words on the fill; else white, outlined, its words in `soft`. Clipped to its shape. |


## Illustrations (`Sources/App/base/Illustrations.swift`)

The approved first-time and empty-state drawings: ten boards for the iPhone, iPad and Mac (boards
11 and 12 are the watches'). Each is ported shape for shape from the iPad's `Illustration`
(kiff/tafs `ios/Tafs/Design/Illustrations.swift`), drawn in code from shapes (no image file), in the
theme's colours, so light and dark both read, with the brand's sweep (`Theme.brand`) as the mark.
Each is drawn on its board's grid and scaled to the width it's given, never wider than its own.

**Rule 14: no text in a drawing.** Shapes only, never a letter, a number or a word, not even a
symbol's: every word stays the screen's own shared key. Every drawing is hidden from VoiceOver.
`ArtBoardTests` reads the drawings' file for this.

Which screen draws which, and when, is `ArtBoard` (Core), tested on any machine:

| Board | Drawing | Screen, and when |
| --- | --- | --- |
| 1. First run | `firstRun` | The sign-in window's KIFF half (`SignInView`), before Continue and after a failure: the iPad's welcome draws it there. It replaces the half's own placeholder. |
| 2. No tafs yet | `noTafs` | The Overview with no taf and no job listed, above the empty line (`OverviewView`), once the list is read empty. |
| 3. Your brief, nothing to do | `briefClear` | Your brief with no decision left to answer (`BriefScreen`), where the decisions go. |
| 4. All halted | `allHalted` | Halt all (`HaltView` with no taf), once every taf is halted. The sheet grows by its room. |
| 5. An app connected | `appConnected` | Connecting's receipt (`ConnectReceiptSheet`, over Coach), at the top, at its own width: the iPad's key receipt (`ConnectApprovalSheet`). It shows once Coach's chat marks a connection made that this Mac saw waiting (`ConnectReceipt`, docs/connections.md › The receipt). |
| 6. Needs you, nothing waiting | `nothingWaiting` | Needs you with nothing waiting (`NeedsYouView`), above its words. |
| 7. Coach, no taf or one | `coachFirst` | Coach's empty chat once Coach is started (`CoachView`), while the account has no taf or one. |
| 8. New taf, small | `newTaf` | Beside "Say it in your own words" in the new taf's gallery (`RecipeGallerySheet`). |
| 9. Coach starting | `coachStarting` | Coach's start, before Coach is started on the account (`CoachView`): the iPad's at its width, always on a Mac. |
| 10. Overview | `overview` | The Overview, under its title (`OverviewView`): the iPad's at its width, always on a Mac, except where board 2 shows instead. |

The screenshots of each, in light and dark, are `build/screenshots/board-*.png`
(`IllustrationScreenTests`).

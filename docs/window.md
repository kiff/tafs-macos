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


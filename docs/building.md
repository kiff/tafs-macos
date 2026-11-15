# Building and testing

tafs for macOS runs on macOS 12 (Monterey) and later, on Intel and Apple silicon. It is
written in Swift with SwiftUI and AppKit.

## What you need

- A Mac on macOS 12 or later with Apple's Command Line Tools (`xcode-select --install`).
  No Xcode, and no package manager: the scripts call the Swift compiler directly.
- **The code stays within Swift 5.7 and the macOS 12 SDK**, the newest a Mac on macOS 12
  can install. CI's Mac job builds with a newer Xcode, which accepts things this one refuses,
  so two rules are checked on their own (`scripts/swift57.sh`, the `swift57` job, on every
  change):
  - **every file parses with Swift 5.7**, so newer syntax fails;
  - **no SwiftUI builder holds more than 10 views** (`scripts/viewbuilders.py`). The macOS 12
    and 13 SDKs' `ViewBuilder` takes at most 10 in one block; a newer SDK takes any number,
    so a newer build never says. Put the views past 10 in a `Group { … }` or a view of their
    own.

  A full Swift 5.7 build needs Xcode 14 or the Command Line Tools of macOS 12. The Mac job
  lists the Xcodes its runner has; the build on a Mac with macOS 12 stays the final check.

## The SDK

`scripts/sdk.sh` names the macOS SDK the app is built against, and `build.sh` and `test.sh`
pass it to the compiler (`-sdk`), printing it first. It is `$SDK` when that's set, else the
newest SDK on the Mac whose SwiftUI this Swift can build with: each SDK, newest first, is
tried with a view that keeps `@State`. An SDK can be newer than the compiler can use: with
the Command Line Tools alone, MacOSX 27.2's `@State` needs a macro plugin they don't carry,
while MacOSX 26.5 builds. On macOS 12 with Swift 5.7 it is that Mac's own SDK.

```sh
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk scripts/build.sh   # one SDK, named
```

## Build

```sh
scripts/build.sh                  # build/tafs.app, Intel and Apple silicon in one binary
ARCHS=x86_64 CONFIG=debug scripts/build.sh    # one architecture, unoptimized, for a quick run
open build/tafs.app
```

The build is not signed. Signing and notarization are a release step, not part of this script.

## Where the code is

| Folder | What |
|---|---|
| `Sources/Core/<part>/` | Code that needs only Foundation: models, words, what the servers answer. It compiles on Linux. |
| `Sources/App/<part>/` | The views and what needs a Mac (AppKit, the Keychain, signing). |
| `Sources/Core/base/`, `Sources/App/base/` | What every part uses: the palette, the theme, snapshots. |
| `Sources/App/entry/` | The file that starts the app. Tests leave it out. |
| `Tests/<part>/` | The part's tests that need no Mac. |
| `Tests/<part>/mac/` | The part's tests that need the views or a Mac. |
| `Tests/Runner/` | The small test runner. XCTest isn't in the Command Line Tools. |

A **part** is a folder of `Tests/`. `ls Tests` lists them; `Runner` is the test runner, not a
part. Today: `shell`, `strings`, `contracts`, `pairing`, `account`, `approvals`, `record`,
`overview`, `calendar`, `usage`, `connections`, `coach` and `taf`.

## Test

```sh
scripts/test.sh                   # every part
scripts/test.sh shell             # one part
scripts/test.sh --core shell      # only the tests that need no Mac
```

A test file lists its tests in `let <part>Tests: [Test]`, or `let <part>MacTests: [Test]` in
the `mac/` folder. The runner prints one line per test and fails if any did.

## Screens in tests

`Snapshot.bitmap(of:size:dark:)` draws a view with no window on screen, in the light or the
dark appearance. Tests read colours from it, and it writes the PNG screenshots.

## CI

`.github/workflows/ci.yml` runs on every pull request, on `main`, and each night.

- **Only the parts a change touches run** (`scripts/parts.sh` reads the changed paths). A
  change to shared code, the test runner, a script, the workflow or the shared pin runs every
  part, **on the Mac too**: the pin brings new words and contracts every screen reads. `strings` and `contracts`
  always run.
- **The tests that need no Mac run on Linux** with Swift 5.7.
- **The Swift 5.7 checks** (`swift57`) run on every change, on Linux.
- **A Mac job** builds the app for both architectures and runs the parts' Mac tests. It runs
  when `Sources/App/`, `App/`, a `mac/` test folder, shared code, the runner, a script, the
  workflow or the shared pin changed.
- **The screenshots** the Mac job's tests write (`build/screenshots/*.png`) are kept with the
  run for 14 days, as the artifact `screenshots`, even when a test fails. A pull request that
  changes a screen links them for its before and after.
- **One part alone:** run the workflow by hand with `part` set to its name.
- **Every night**, every part runs on both.
- **The drift check** fails when the shared pin is too far behind ([shared.md](shared.md)).

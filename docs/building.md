# Building and testing

tafs for macOS runs on macOS 12 (Monterey) and later, on Intel and Apple silicon. It is
written in Swift with SwiftUI and AppKit.

## What you need

- A Mac on macOS 12 or later with Apple's Command Line Tools (`xcode-select --install`).
  No Xcode, and no package manager: the scripts call the Swift compiler directly.
- **The code stays within Swift 5.7**, the newest Swift a Mac on macOS 12 can install. CI
  compiles it with Swift 5.7 on every pull request, so newer syntax fails there.

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

A **part** is a folder of `Tests/`: `shell`, `strings`, `contracts` and `pairing` today, then
`approvals`, `coach`, `record`, `connections`, `calendar` and `account` as they arrive.

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
  change to shared code, a script or the workflow runs every part. `strings` and `contracts`
  always run.
- **The tests that need no Mac run on Linux** with Swift 5.7.
- **A Mac job** builds the app for both architectures and runs the parts' Mac tests. It runs
  only when `Sources/App/`, `App/`, a `mac/` test folder, a script or the workflow changed.
- **One part alone:** run the workflow by hand with `part` set to its name.
- **Every night**, every part runs on both.
- **The drift check** fails when the shared pin is too far behind ([shared.md](shared.md)).

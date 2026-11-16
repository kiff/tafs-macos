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
- **`cmake` and `pkg-config`**, for the native libraries (below). The Command Line Tools
  don't carry them. CI's Mac runners have `cmake`, and `pkg-config` is installed when missing.

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

## The native libraries

The app talks to a USB security key through libfido2 (docs/approvals.md, "Passkeys on macOS
12"), and recovers a KIFF receipt's signer with libsecp256k1 (docs/record.md). `scripts/fido.sh`
builds both, and the two libfido2 needs, from pinned source:

| Library | Version | Source, and what's checked |
|---|---|---|
| libfido2 | 1.17.0 | Its release tarball, by SHA-256. The pinned hash is the tarball's whose release signature verified. |
| OpenSSL (libcrypto) | 3.5.9 | Its release tarball, by the SHA-256 openssl.org publishes. |
| libcbor | 0.13.0 | Its tag, at a pinned commit, and the SHA-256 of its files: it publishes no tarball. libfido2 1.17.0 builds with this version. |
| libsecp256k1 | 0.7.1 | Its tag, at a pinned commit (`1a53f496…`), and the SHA-256 of its files, as libcbor's. It's the release the iPad's swift-secp256k1 0.24.0 vendors. Built with its recovery module only: ECDH, extrakeys, Schnorr, MuSig and ElligatorSwift off, and no tests, benchmarks or examples. |

- **Nothing prebuilt is used**, and a source whose hash isn't the pinned one isn't unpacked.
- **Static libraries for each architecture**, for macOS 12, in `build/fido/<arch>/lib`, with
  their headers and a module map (`import CFido`, `import CSecp256k1`) in `build/fido/<arch>/include`. zlib, which
  libfido2 links, is the SDK's. libcrypto is built alone: no shared library, modules, engines,
  apps, tests or docs.
- **`build.sh` runs it for each architecture it builds**, and `test.sh` for this Mac's when the
  app's views are tested. Once an architecture is built by the script as it is, it isn't built
  again (`build/fido/<arch>/.stamp` holds the script's hash). The first build takes a few minutes.
- **The licences** of the four go to `build/fido/licenses`, and `build.sh` puts them in the app
  (`Contents/Resources/licenses/`).
- **CI's Mac job** restores the libraries an earlier run of this same script built, keyed on the
  script's hash, so a moved pin builds again. The nightly run restores nothing and builds them.

**Moving a pin:** change the version and its hash in `scripts/fido.sh` together, from the
publisher: libfido2's tarball, after checking its `.sig`; OpenSSL's `.sha256` from openssl.org;
for libcbor and libsecp256k1, the tag's commit and the files' hash (`find . -type f ! -path './.git/*' -print0 |
LC_ALL=C sort -z | xargs -0 shasum -a 256 | shasum -a 256` in a fresh clone of the tag).

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
- **A Mac job** builds the app for both architectures, with the native libraries (above),
  checks the libraries' licences are in it, and runs the parts' Mac tests. It runs
  when `Sources/App/`, `App/`, a `mac/` test folder, shared code, the runner, a script, the
  workflow or the shared pin changed.
- **The screenshots** the Mac job's tests write (`build/screenshots/*.png`) are kept with the
  run for 14 days, as the artifact `screenshots`, even when a test fails. A pull request that
  changes a screen links them for its before and after.
- **One part alone:** run the workflow by hand with `part` set to its name.
- **Every night**, every part runs on both.
- **The drift check** fails when the shared pin is too far behind ([shared.md](shared.md)).

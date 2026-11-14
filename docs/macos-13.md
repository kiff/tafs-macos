# tafs on macOS 13 and later

On macOS 13 and later, tafs is the iPhone and iPad app built for the Mac with **Mac Catalyst**. Its code is in [kiff/tafs](https://github.com/kiff/tafs), under `ios/`. This repository holds the notes.

The full page is [docs/mac-app.md in kiff/tafs](https://github.com/kiff/tafs/blob/main/docs/mac-app.md), once its pull request is merged. This page keeps the decision and the build steps.

## The decision: Mac Catalyst

An iPad app reaches a Mac in two ways.

| | Mac Catalyst | "Designed for iPad" |
|---|---|---|
| Macs it runs on | Intel and Apple silicon | Apple silicon only |
| How it ships | the Mac App Store, or a signed and notarized disk image | the Mac App Store only |
| The menu bar and the window | the app's own | what the system gives an iPad app |
| Tested in CI | yes, as a Mac build | no |
| Code changes | a few | none |

Mac Catalyst was chosen for the Intel Macs, the disk image, the menu bar and the CI build.

"Designed for iPad" stays possible beside it. It needs no code: it's a setting of the app's App Store listing, which offers the iPad app to Apple silicon Macs.

## Building it

On a Mac with Xcode and XcodeGen, from a clone of kiff/tafs:

```bash
cd ios && xcodegen generate
xcodebuild build -project Tafs.xcodeproj -scheme TafsMac \
  -destination "platform=macOS,variant=Mac Catalyst" CODE_SIGNING_ALLOWED=NO
```

To run the unit tests on the Mac:

```bash
xcodebuild test -project Tafs.xcodeproj -scheme TafsMac \
  -destination "platform=macOS,variant=Mac Catalyst" CODE_SIGNING_ALLOWED=NO
```

The build is unsigned. Signing, notarizing and the disk image are set up at release.

In CI, kiff/tafs's `Mac` workflow does both steps on a macOS runner.

## What a Mac Catalyst build lacks

Found by building it. Each is compiled out on the Mac only:

- **Live Activities** (`ActivityKit`). The Mac build has no Live Activity for a held call, and the widget extension isn't built for it.
- **The Siri tip** (`SiriTipView`) on the Halt screen.
- **The Home button** in UI tests (`XCUIDevice.press`). The Mac build runs the unit tests only.

## A Mac's tests run on the Mac

The iPhone's and iPad's tests run on a Simulator, where approvals are always ready. A Mac's tests run on the Mac itself, and a CI runner has no Touch ID. A test that needs an approval sets its model ready and uses a stub signer.

## Owed before a release

A person approves a Card with Touch ID on a real Mac. The Mac build has only run in CI.

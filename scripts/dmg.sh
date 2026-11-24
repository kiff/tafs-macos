#!/bin/sh
# Packs build/tafs.app into a disk image a person opens and drags to Applications
# (docs/release.md). Run scripts/build.sh first.
#   scripts/dmg.sh                       signed ad hoc: for a check, not for anyone's Mac
#   IDENTITY="Developer ID Application: …" scripts/dmg.sh
#                                        signed with Developer ID and the hardened runtime,
#                                        ready to notarize (the DMG workflow does that)
#   PUSH=1 PROFILE=path/to.provisionprofile IDENTITY=… scripts/dmg.sh
#                                        with alerts with tafs closed: the app built with PUSH=1,
#                                        its Developer ID profile with push embedded, and
#                                        aps-environment signed in (App/tafs-push.entitlements)
set -eu
cd "$(dirname "$0")/.."

APP=build/tafs.app
IDENTITY="${IDENTITY:--}"
[ -d "$APP" ] || { echo "No $APP: run scripts/build.sh first" >&2; exit 2; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
DMG="build/tafs-$VERSION-$BUILD.dmg"

# The app first, then the image around it: a signature covers what's inside it.
# With the app's entitlements (App/tafs.entitlements): under the hardened runtime, the
# microphone and the camera each need their own, or dictation and Take photo fail without a word.
ENTITLEMENTS=App/tafs.entitlements
if [ "${PUSH:-0}" = "1" ]; then
    # Push is a restricted entitlement: signed in only with the profile that allows it, or macOS won't launch the app.
    [ "$IDENTITY" != "-" ] || { echo "PUSH=1 needs IDENTITY: push is signed with Developer ID only" >&2; exit 2; }
    [ -f "${PROFILE:-}" ] || { echo "PUSH=1 needs PROFILE, the Developer ID provisioning profile with push" >&2; exit 2; }
    cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
    ENTITLEMENTS=App/tafs-push.entitlements
fi
if [ "$IDENTITY" = "-" ]; then
    codesign --force --entitlements "$ENTITLEMENTS" --sign - "$APP"
else
    # The hardened runtime and a secure timestamp, which notarization requires.
    codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"
echo "The app's entitlements:"
codesign -d --entitlements :- "$APP" 2>/dev/null
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "com.apple.security.device.audio-input" \
    || { echo "The app is signed without the microphone entitlement" >&2; exit 1; }
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "com.apple.security.device.camera" \
    || { echo "The app is signed without the camera entitlement" >&2; exit 1; }
# Push only with its profile, and never without PUSH=1.
if [ "${PUSH:-0}" = "1" ]; then
    codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "com.apple.developer.aps-environment" \
        || { echo "The app is signed without aps-environment" >&2; exit 1; }
else
    ! codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "aps-environment" \
        || { echo "aps-environment is signed in without PUSH=1 and its profile" >&2; exit 1; }
    [ ! -f "$APP/Contents/embedded.provisionprofile" ] || { echo "A profile is embedded without PUSH=1" >&2; exit 1; }
fi

# What the window shows: the app, and Applications to drag it to.
STAGE=build/dmg
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname tafs -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGE"
[ "$IDENTITY" = "-" ] || codesign --force --timestamp --sign "$IDENTITY" "$DMG"

# Opened as a person opens it: the app is there, whole, and still signed.
MOUNT=$(mktemp -d)
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$DMG"
trap 'hdiutil detach -quiet "$MOUNT" 2>/dev/null || true; rmdir "$MOUNT" 2>/dev/null || true' EXIT
[ -x "$MOUNT/tafs.app/Contents/MacOS/tafs" ] || { echo "The image has no tafs.app" >&2; exit 1; }
[ -L "$MOUNT/Applications" ] || { echo "The image has no Applications link" >&2; exit 1; }
codesign --verify --strict "$MOUNT/tafs.app"
echo "Built $DMG ($(du -h "$DMG" | cut -f1)), app $(lipo -archs "$MOUNT/tafs.app/Contents/MacOS/tafs"), signed $( [ "$IDENTITY" = "-" ] && echo "ad hoc" || echo "with Developer ID")"

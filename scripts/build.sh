#!/bin/sh
# Builds build/tafs.app for macOS 12 and later, Intel and Apple silicon in one binary, with
# the Swift compiler alone (docs/building.md).
#   ARCHS="x86_64"   builds one architecture, for a quick local run
#   CONFIG=debug     builds without optimization
set -eu
cd "$(dirname "$0")/.."

ARCHS="${ARCHS:-x86_64 arm64}"
OPT="-O"
[ "${CONFIG:-release}" = "debug" ] && OPT="-Onone"
OUT=build
APP="$OUT/tafs.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# The SDK, named: the newest this Swift can build SwiftUI with, or $SDK (scripts/sdk.sh).
SDK=$(scripts/sdk.sh)
echo "SDK: $SDK"

SLICES=""
for arch in $ARCHS; do
    echo "Compiling for $arch"
    find Sources -name '*.swift' | sort | xargs swiftc -swift-version 5 -parse-as-library $OPT -sdk "$SDK" \
        -target "$arch-apple-macos12.0" -module-name Tafs -o "$OUT/tafs-$arch"
    SLICES="$SLICES $OUT/tafs-$arch"
done

# shellcheck disable=SC2086
lipo -create $SLICES -output "$APP/Contents/MacOS/tafs"
cp App/Info.plist "$APP/Contents/Info.plist"

# The shared words of each shipped language and the mascot, as kiff/tafs has them at the pin.
scripts/shared.sh fetch
STRINGS="$APP/Contents/Resources/strings"
mkdir -p "$STRINGS"
cp .shared/app/strings/languages.json "$STRINGS/"
for lang in $(tr -d '[]",:' < .shared/app/strings/languages.json | awk '/shipped/ { for (i = 2; i <= NF; i++) print $i }'); do
    cp -R ".shared/app/strings/$lang" "$STRINGS/$lang"
    ls "$STRINGS/$lang"/*.json > /dev/null
done
[ -d "$STRINGS/en" ] || { echo "No words were copied into the app" >&2; exit 1; }
cp .shared/ios/Shared/Mascot.xcassets/Mascot.imageset/mascot.png "$APP/Contents/Resources/mascot.png"
echo "Built $APP: $(lipo -archs "$APP/Contents/MacOS/tafs")"

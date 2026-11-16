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

# The native libraries, built from pinned source for each architecture (scripts/fido.sh): the
# security key's libfido2, and libsecp256k1 for KIFF's receipts.
# shellcheck disable=SC2086
scripts/fido.sh $ARCHS

# The shared words, the mascot and the iPad's Swift that Core compiles as it is, at the pin.
scripts/shared.sh fetch

SLICES=""
for arch in $ARCHS; do
    echo "Compiling for $arch"
    { find Sources -name '*.swift' | sort; scripts/shared.sh sources; } | xargs swiftc -swift-version 5 -parse-as-library $OPT -sdk "$SDK" \
        -target "$arch-apple-macos12.0" -I "build/fido/$arch/include" -L "build/fido/$arch/lib" \
        -module-name Tafs -o "$OUT/tafs-$arch"
    SLICES="$SLICES $OUT/tafs-$arch"
done

# shellcheck disable=SC2086
lipo -create $SLICES -output "$APP/Contents/MacOS/tafs"
cp App/Info.plist "$APP/Contents/Info.plist"

# The shared words of each shipped language and the mascot, as kiff/tafs has them at the pin.
STRINGS="$APP/Contents/Resources/strings"
mkdir -p "$STRINGS"
cp .shared/app/strings/languages.json "$STRINGS/"
for lang in $(tr -d '[]",:' < .shared/app/strings/languages.json | awk '/shipped/ { for (i = 2; i <= NF; i++) print $i }'); do
    cp -R ".shared/app/strings/$lang" "$STRINGS/$lang"
    ls "$STRINGS/$lang"/*.json > /dev/null
done
[ -d "$STRINGS/en" ] || { echo "No words were copied into the app" >&2; exit 1; }
cp .shared/ios/Shared/Mascot.xcassets/Mascot.imageset/mascot.png "$APP/Contents/Resources/mascot.png"
# The licenses of the libraries linked in: libfido2, libcbor, OpenSSL and libsecp256k1.
mkdir -p "$APP/Contents/Resources/licenses"
cp build/fido/licenses/*.txt "$APP/Contents/Resources/licenses/"
echo "Built $APP: $(lipo -archs "$APP/Contents/MacOS/tafs")"

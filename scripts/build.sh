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

# K5=1: the end-to-end pass's build, with the new onboarding on (`Onboarding.on`, docs/pairing.md), as the iPad's
# `TAFS_K5`. Never for the download: dmg.sh refuses an app built with it.
K5FLAG=""
if [ "${K5:-}" = 1 ]; then K5FLAG="-D TAFS_K5"; echo "K5 build: the new onboarding is on"; fi

SLICES=""
for arch in $ARCHS; do
    echo "Compiling for $arch"
    { find Sources -name '*.swift' | sort; scripts/shared.sh sources; } | xargs swiftc -swift-version 5 -parse-as-library $OPT $K5FLAG -sdk "$SDK" \
        -target "$arch-apple-macos12.0" -I "build/fido/$arch/include" -L "build/fido/$arch/lib" \
        -module-name Tafs -o "$OUT/tafs-$arch"
    SLICES="$SLICES $OUT/tafs-$arch"
done

# shellcheck disable=SC2086
lipo -create $SLICES -output "$APP/Contents/MacOS/tafs"
cp App/Info.plist "$APP/Contents/Info.plist"
# A K5 build says so in its bundle, so dmg.sh never packs it.
rm -f "$APP/Contents/Resources/k5"
[ -z "$K5FLAG" ] || { mkdir -p "$APP/Contents/Resources" && echo "TAFS_K5" > "$APP/Contents/Resources/k5"; }

# The shared words of each shipped language and the mascot, as kiff/tafs has them at the pin.
STRINGS="$APP/Contents/Resources/strings"
mkdir -p "$STRINGS"
cp .shared/app/strings/languages.json .shared/app/strings/ages.json "$STRINGS/"
for lang in $(tr -d '[]",:' < .shared/app/strings/languages.json | awk '/shipped/ { for (i = 2; i <= NF; i++) print $i }'); do
    cp -R ".shared/app/strings/$lang" "$STRINGS/$lang"
    ls "$STRINGS/$lang"/*.json > /dev/null
done
[ -d "$STRINGS/en" ] || { echo "No words were copied into the app" >&2; exit 1; }
cp .shared/ios/Shared/Mascot.xcassets/Mascot.imageset/mascot.png "$APP/Contents/Resources/mascot.png"
# The app's icon: the iPad's artwork on macOS's icon grid (App/AppIcon.png, 1024 square), at
# every size Finder and the Dock ask for. Info.plist names it (CFBundleIconFile).
SET="$OUT/tafs.iconset"
rm -rf "$SET"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" App/AppIcon.png --out "$SET/icon_${size}x${size}.png" > /dev/null
    sips -z $((size * 2)) $((size * 2)) App/AppIcon.png --out "$SET/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$SET" -o "$APP/Contents/Resources/tafs.icns"
rm -rf "$SET"
[ -s "$APP/Contents/Resources/tafs.icns" ] || { echo "The app's icon wasn't made" >&2; exit 1; }
# The licenses of the libraries linked in: libfido2, libcbor, OpenSSL and libsecp256k1.
mkdir -p "$APP/Contents/Resources/licenses"
cp build/fido/licenses/*.txt "$APP/Contents/Resources/licenses/"
echo "Built $APP: $(lipo -archs "$APP/Contents/MacOS/tafs")"

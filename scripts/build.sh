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

SLICES=""
for arch in $ARCHS; do
    echo "Compiling for $arch"
    find Sources -name '*.swift' | sort | xargs swiftc -swift-version 5 -parse-as-library $OPT \
        -target "$arch-apple-macos12.0" -module-name Tafs -o "$OUT/tafs-$arch"
    SLICES="$SLICES $OUT/tafs-$arch"
done

# shellcheck disable=SC2086
lipo -create $SLICES -output "$APP/Contents/MacOS/tafs"
cp App/Info.plist "$APP/Contents/Info.plist"
echo "Built $APP: $(lipo -archs "$APP/Contents/MacOS/tafs")"

#!/bin/sh
# Prints the macOS SDK the app is built against (docs/building.md): $SDK when it's set, else
# the newest SDK on this Mac whose SwiftUI this Swift compiler can build with. An SDK can be
# newer than the compiler can use: with the Command Line Tools alone, MacOSX 27.2's `@State`
# needs a macro plugin they don't carry, while 26.5 builds. Each SDK is tried with a view that
# keeps `@State`, newest first; the first that compiles is the one.
set -eu
if [ -n "${SDK:-}" ]; then echo "$SDK"; exit 0; fi
default=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
dir=$(dirname "${default:-/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk}")
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
printf 'import SwiftUI\nstruct Probe: View {\n    @State private var n = 0\n    var body: some View { Text(String(n)) }\n}\n' > "$probe/probe.swift"
# The default first, then every versioned SDK, newest first.
for sdk in "$default" $(ls -d "$dir"/MacOSX[0-9]*.sdk 2>/dev/null | sort -V -r); do
    [ -d "$sdk" ] || continue
    if swiftc -typecheck -sdk "$sdk" -target "$(uname -m)-apple-macos12.0" "$probe/probe.swift" >/dev/null 2>&1; then
        echo "$sdk"
        exit 0
    fi
done
echo "No macOS SDK here builds SwiftUI with this Swift: set SDK=/path/to/MacOSX.sdk" >&2
exit 1

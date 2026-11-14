#!/bin/sh
# Runs the tests, all of them or the parts named (docs/building.md).
#   scripts/test.sh                 every part
#   scripts/test.sh approvals       one part
#   scripts/test.sh --core shell    only the tests that need no Mac (they run on Linux too)
set -eu
cd "$(dirname "$0")/.."

CORE=0
if [ "${1:-}" = "--core" ]; then CORE=1; shift; fi
PARTS="$*"
[ -n "$PARTS" ] || PARTS=$(ls Tests | grep -v '^Runner$')

# The shared words and contracts, at the pin.
scripts/shared.sh fetch

# Swift tells files of one build apart by name: two with the same name don't compile together.
TWICE=$(find Sources Tests -name '*.swift' -exec basename {} \; | sort | uniq -d)
[ -z "$TWICE" ] || { echo "Two files share a name; name each after its part: $TWICE" >&2; exit 2; }

OUT=build/tests
mkdir -p "$OUT"
MAIN="$OUT/main.swift"
FILES="$OUT/files"
: > "$FILES"
printf 'import Foundation\n\nvar suites: [(name: String, tests: [Test])] = []\n' > "$MAIN"

find Sources/Core Tests/Runner -name '*.swift' | sort >> "$FILES"
# The app's views are tested on a Mac, without the file that starts the app.
[ "$CORE" = 1 ] || find Sources/App -name '*.swift' -not -path 'Sources/App/entry/*' | sort >> "$FILES"

for part in $PARTS; do
    case "$part" in *[!a-z0-9_]*) echo "No such part: $part" >&2; exit 2 ;; esac
    [ -d "Tests/$part" ] || { echo "No such part: $part" >&2; exit 2; }
    if ls "Tests/$part"/*.swift >/dev/null 2>&1; then
        ls "Tests/$part"/*.swift >> "$FILES"
        echo "suites.append((\"$part\", ${part}Tests))" >> "$MAIN"
    fi
    if [ "$CORE" = 0 ] && ls "Tests/$part/mac"/*.swift >/dev/null 2>&1; then
        ls "Tests/$part/mac"/*.swift >> "$FILES"
        echo "suites.append((\"$part, on a Mac\", ${part}MacTests))" >> "$MAIN"
    fi
done
echo "exit(run(suites))" >> "$MAIN"
echo "$MAIN" >> "$FILES"

TARGET=""
[ "$(uname)" = "Darwin" ] && TARGET="-target $(uname -m)-apple-macos12.0"
# shellcheck disable=SC2086
xargs swiftc -swift-version 5 -Onone $TARGET -module-name TafsTests -o "$OUT/run" < "$FILES"
"$OUT/run"

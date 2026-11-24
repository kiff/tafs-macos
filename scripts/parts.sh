#!/bin/sh
# Says which parts a change touches, from the changed files' paths on standard input, one a
# line. Prints two lines: "parts=<names>" and "mac=true|false" (whether a Mac must build).
#   git diff --name-only main...HEAD | scripts/parts.sh
#   scripts/parts.sh all            every part, as the nightly run
#   scripts/parts.sh approvals      one part, as workflow_dispatch's input
# A part is a folder of Tests/, with its code in Sources/Core/<part> and Sources/App/<part>.
# Code outside a part, the scripts, the workflow and the shared pin run every part, on the
# Mac too. Strings, contracts and the Sources-wide guards always run.
set -eu
cd "$(dirname "$0")/.."

ALL=$(ls Tests | grep -v '^Runner$' | tr '\n' ' ' | sed 's/ *$//')
# A part is a plain name: test.sh writes it into Swift source.
is_part() {
    case "$1" in ""|*[!a-z0-9_]*) return 1 ;; esac
    [ -d "Tests/$1" ]
}

if [ "${1:-}" = "all" ]; then
    echo "parts=$ALL"; echo "mac=true"; exit 0
elif [ -n "${1:-}" ]; then
    is_part "$1" || { echo "No such part: $1" >&2; exit 2; }
    echo "parts=$1"; echo "mac=true"; exit 0
fi

PARTS=""; MAC=false; EVERY=false
while IFS= read -r path; do
    case "$path" in
        Tests/*/mac/*|Sources/App/*|App/*) MAC=true ;;
        scripts/*|.github/workflows/*) MAC=true; EVERY=true ;;
    esac
    case "$path" in
        Tests/*/*|Sources/Core/*/*|Sources/App/*/*)
            part=$(echo "$path" | sed -E 's#^(Tests|Sources/Core|Sources/App)/([^/]+)/.*#\2#')
            if is_part "$part"; then PARTS="$PARTS $part"; else EVERY=true; fi ;;
        Sources/*|Tests/*|shared.pin) EVERY=true ;;
    esac
done

# Every part runs on the Mac too: shared code, the runner and the pin reach the app's views
# and every part's Mac tests, so a run on Linux alone would let a broken Mac test through.
[ "$EVERY" = true ] && { PARTS="$ALL"; MAC=true; }
# The guards read every source file, so a change in any part can break one: they run on every change.
for always in strings contracts guards; do
    is_part "$always" && PARTS="$PARTS $always"
done
echo "parts=$(echo "$PARTS" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/^ *//; s/ *$//')"
echo "mac=$MAC"

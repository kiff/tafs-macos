#!/bin/sh
# The words and contracts every tafs app shares, read from kiff/tafs at the commit named in
# shared.pin (docs/shared.md). Nothing of them is copied into this repository.
#   scripts/shared.sh fetch          puts app/strings and contracts at the pin in .shared/
#   scripts/shared.sh drift          fails when the pin is too far behind kiff/tafs main
#   scripts/shared.sh verdict C D    the drift rule alone: C commits behind, D days behind
set -eu
cd "$(dirname "$0")/.."

REPO=kiff/tafs
PIN=$(tr -d '[:space:]' < shared.pin)
# The pin is a full commit id and nothing else, before it reaches git or the API.
case "$PIN" in
    *[!0-9a-f]*) echo "shared.pin is not a commit id" >&2; exit 2 ;;
esac
[ "${#PIN}" = 40 ] || { echo "shared.pin is not a full commit id (40 characters)" >&2; exit 2; }
MAX_COMMITS=20
MAX_DAYS=7

verdict() {
    if [ "$1" -gt "$MAX_COMMITS" ] || [ "$2" -gt "$MAX_DAYS" ]; then
        echo "The pin is $1 commits and $2 days behind $REPO main (at most $MAX_COMMITS commits, $MAX_DAYS days)."
        echo "Set shared.pin to main's commit in a pull request of its own."
        return 1
    fi
    echo "The pin is $1 commits and $2 days behind $REPO main."
}

case "${1:-}" in
    fetch)
        [ "$(cat .shared/.pin 2>/dev/null || true)" = "$PIN" ] && exit 0
        rm -rf .shared
        git init -q .shared
        git -C .shared remote add origin "https://github.com/$REPO.git"
        git -C .shared sparse-checkout set app/strings contracts
        git -C .shared fetch -q --depth 1 --filter=blob:none origin "$PIN"
        git -C .shared checkout -q FETCH_HEAD
        echo "$PIN" > .shared/.pin
        echo "Fetched $REPO at $PIN"
        ;;
    drift)
        # How many commits main has past the pin, and how many days ago the first of them was made.
        set -- $(gh api "repos/$REPO/compare/$PIN...main" --jq \
            '"\(.ahead_by) \(if .ahead_by == 0 then 0 else ((now - (.commits[0].commit.committer.date | fromdateiso8601)) / 86400 | floor) end)"')
        verdict "$1" "$2"
        ;;
    verdict)
        verdict "$2" "$3"
        ;;
    *)
        echo "usage: scripts/shared.sh fetch | drift | verdict <commits> <days>" >&2
        exit 2
        ;;
esac

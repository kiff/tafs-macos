#!/bin/sh
# What a Mac on macOS 12 needs that a newer build can't show (docs/building.md): every source
# file parses with Swift 5.7, no SwiftUI builder holds more than 10 views, and no app code has
# the shapes Swift 5.7 refused there.
set -eu
cd "$(dirname "$0")/.."
swiftc --version 2>&1 | head -1
scripts/shared.sh fetch > /dev/null
{ find Sources Tests -name '*.swift' | sort; scripts/shared.sh sources; } | xargs swiftc -parse
find Sources/App -name '*.swift' | sort | xargs python3 scripts/viewbuilders.py
find Sources/App -name '*.swift' | sort | xargs python3 scripts/swift57patterns.py
echo "Swift 5.7: every file parses, no builder holds more than 10 views, and no code has a shape it refuses."

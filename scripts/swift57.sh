#!/bin/sh
# What a Mac on macOS 12 needs that a newer build can't show (docs/building.md): every source
# file parses with Swift 5.7, and no SwiftUI builder holds more than 10 views.
set -eu
cd "$(dirname "$0")/.."
swiftc --version 2>&1 | head -1
find Sources Tests -name '*.swift' | sort | xargs swiftc -parse
find Sources/App -name '*.swift' | sort | xargs python3 scripts/viewbuilders.py
echo "Swift 5.7: every file parses, and no builder holds more than 10 views."

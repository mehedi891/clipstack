#!/bin/bash
# Run the test suite.
#
# Tests use swift-testing rather than XCTest: the Command Line Tools ship
# Testing.framework but no XCTest. SwiftPM does not search the CLT Developer
# framework directory on its own, so the path is passed explicitly.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV="$(xcode-select -p)/Library/Developer"
FW="$DEV/Frameworks"
LIB="$DEV/usr/lib"          # holds lib_TestingInterop.dylib, which Testing.framework loads

cd "$ROOT"
exec swift test \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xlinker -F -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" \
    "$@"

#!/bin/sh
# Runs the unit tests. Without full Xcode, Swift Testing lives in the Command Line Tools
# and has to be pointed at explicitly.
set -eu
cd "$(dirname "$0")/.."
if xcode-select -p 2>/dev/null | grep -q CommandLineTools; then
  CLT=/Library/Developer/CommandLineTools
  FW="$CLT/Library/Developer/Frameworks"
  LIB="$CLT/Library/Developer/usr/lib"
  exec swift test \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xswiftc -plugin-path -Xswiftc "$CLT/usr/lib/swift/host/plugins/testing" \
    -Xlinker -F -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" "$@"
else
  exec swift test "$@"
fi

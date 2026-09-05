#!/bin/zsh
# Runs the Swift Testing suite. With only the Command Line Tools installed, SwiftPM does not find
# Testing.framework by itself, so the search paths are passed explicitly. Works unchanged with Xcode too.
set -euo pipefail
cd "$(dirname "$0")"
DEV="$(xcode-select -p)"
FRAMEWORKS="$DEV/Library/Developer/Frameworks"
[[ -d "$FRAMEWORKS" ]] || FRAMEWORKS="$DEV/Platforms/MacOSX.platform/Developer/Library/Frameworks"
INTEROP="$DEV/Library/Developer/usr/lib"
swift test \
  -Xswiftc -F"$FRAMEWORKS" \
  -Xlinker -F"$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$INTEROP" \
  "$@"

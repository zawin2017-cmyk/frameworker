#!/bin/zsh
# Builds Frameworker.app with SwiftPM (no Xcode needed, the Command Line Tools are enough).
#   ./build.sh            build only, result in .build/Frameworker.app
#   ./build.sh --install  build, replace ~/Applications/Frameworker.app and launch it
# The bundle lives inside the hidden .build directory on purpose: Spotlight and Alfred index visible
# folders, and a second launchable copy would run as a second instance next to the installed one.
set -euo pipefail
cd "$(dirname "$0")"

APP=Frameworker
BUNDLE_ID=nl.zawin.frameworker
OUT=".build/$APP.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/$APP"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/$APP"
cp Info.plist "$OUT/Contents/Info.plist"

if [[ ! -f .build/AppIcon.icns || scripts/make-icon.swift -nt .build/AppIcon.icns ]]; then
  swiftc -O scripts/make-icon.swift -o .build/make-icon
  .build/make-icon .build/AppIcon.icns
fi
cp .build/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"

# Ad-hoc signature with a designated requirement based on the bundle identifier instead of the binary's
# hash, so the Accessibility permission granted in System Settings survives rebuilds.
codesign --force --sign - --identifier "$BUNDLE_ID" \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" "$OUT"

echo "Built $OUT"

if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/Applications/$APP.app"
  mkdir -p "$HOME/Applications"
  pkill -x "$APP" 2>/dev/null || true
  for _ in {1..20}; do pgrep -x "$APP" >/dev/null || break; sleep 0.15; done
  rm -rf "$DEST"
  cp -R "$OUT" "$DEST"
  open "$DEST"
  echo "Installed and launched $DEST"
fi

#!/bin/zsh
# Renders the real DotBar UI offscreen and composes Mac App Store screenshots.
# Nothing is shown on screen; the running DotBar app is never touched.
#
#   marketing/make-screenshots.sh [work-dir]
#
# Output: dist/screenshots/*.png (2880x1800 and 1440x900).
set -euo pipefail

ROOT=${0:A:h:h}
WORK=${1:-$(mktemp -d /tmp/dotbar-shots.XXXXXX)}
OUT="$ROOT/dist/screenshots"
mkdir -p "$WORK" "$OUT"

# Sandbox HOME so AppState/Store can never see or write the user's items.json.
FAKE_HOME="$WORK/screenshots-home"
mkdir -p "$FAKE_HOME/Library/Application Support"

SRCS=($(find "$ROOT/DotBar" -name '*.swift' ! -name 'DotBarApp.swift'))

echo "--- building renderer"
swiftc -O -swift-version 5 -framework AppKit -framework SwiftUI \
  -o "$WORK/render" "${SRCS[@]}" "$ROOT/marketing/render/main.swift"

echo "--- building composer"
swiftc -O -swift-version 5 -framework AppKit -o "$WORK/compose" "$ROOT/marketing/compose/main.swift"

echo "--- rendering UI"
HOME="$FAKE_HOME" CFFIXED_USER_HOME="$FAKE_HOME" "$WORK/render" "$WORK"

echo "--- composing"
"$WORK/compose" "$WORK" "$OUT" "$ROOT/Assets/AppIcon-master.png"

for f in "$OUT"/*-2880x1800.png; do
  small="${f%-2880x1800.png}-1440x900.png"
  cp "$f" "$small"
  sips -Z 1440 "$small" >/dev/null
done

echo "--- results"
for f in "$OUT"/*.png; do sips -g pixelWidth -g pixelHeight "$f" | tr '\n' ' '; echo; done

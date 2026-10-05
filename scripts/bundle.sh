#!/usr/bin/env bash
# Build NameCards in release mode and assemble a signed NameCards.app.
# Set SIGN_IDENTITY to a stable certificate name to avoid repeated permission prompts; defaults to ad-hoc ("-").
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/NameCards"
APP="NameCards.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NameCards"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"

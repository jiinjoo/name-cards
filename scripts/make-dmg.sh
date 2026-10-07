#!/usr/bin/env bash
# Packages NameCards.app into a drag-to-install disk image: NameCards-<version>.dmg.
# Run scripts/bundle.sh first (UNIVERSAL=1 for releases).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" NameCards.app/Contents/Info.plist)"
DMG="NameCards-$VERSION.dmg"
STAGING="$(mktemp -d)"
# ditto preserves the code signature and extended attributes.
ditto NameCards.app "$STAGING/NameCards.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "NameCards $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "Built $DMG"

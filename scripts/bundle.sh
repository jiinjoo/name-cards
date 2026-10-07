#!/usr/bin/env bash
# Build NameCards in release mode and assemble a signed NameCards.app.
#
# Environment:
#   UNIVERSAL=1      build for both Apple Silicon and Intel (slower; used for releases)
#   VERSION=1.2.3    version shown in Finder/About (default: from Resources/Info.plist)
#   BUILD=42         build number (default: from Resources/Info.plist)
#   SIGN_IDENTITY    signing identity; defaults to ad-hoc ("-"). Use a stable certificate to avoid repeated
#                    permission prompts after rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="NameCards.app"
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    # Build each architecture and merge with lipo. (`--arch a --arch b` needs full Xcode; this works with
    # the Command Line Tools too.)
    BINARIES=()
    for ARCH in arm64 x86_64; do
        swift build -c release --triple "$ARCH-apple-macosx14.0"
        BINARIES+=("$(swift build -c release --triple "$ARCH-apple-macosx14.0" --show-bin-path)/NameCards")
    done
    BIN="$(mktemp -d)/NameCards"
    lipo -create "${BINARIES[@]}" -output "$BIN"
else
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)/NameCards"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NameCards"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${BUILD:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
fi

codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/NameCards"))"

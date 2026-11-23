#!/bin/bash
# Builds a universal, Developer ID signed build/Stagehand.app.
# The stable signature keeps the Screen Recording and Camera permissions across rebuilds.
# RELEASE=1 adds a secure timestamp, which notarization requires (needs network).
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${SIGN_IDENTITY:-Developer ID Application: MusicData Labs Sweden AB (Q47N78X9DT)}"
APP="build/Stagehand.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Stagehand"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Stagehand"
cp Resources/Info.plist "$APP/Contents/Info.plist"

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
"$BIN" --write-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

TIMESTAMP="--timestamp=none"
[ "${RELEASE:-0}" = 1 ] && TIMESTAMP="--timestamp"

# Sparkle: embed the framework and sign its helpers inside-out. Stagehand is not sandboxed,
# so the XPC services are not needed (see Sparkle's sandboxing docs) and are removed.
FW="$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
ditto "$(dirname "$BIN")/Sparkle.framework" "$FW"
rm -rf "$FW/Versions/B/XPCServices" "$FW/XPCServices"
for item in "$FW/Versions/B/Autoupdate" "$FW/Versions/B/Updater.app" "$FW"; do
    codesign --force --options runtime $TIMESTAMP --sign "$IDENTITY" "$item"
done

codesign --force --options runtime $TIMESTAMP \
    --entitlements Resources/Stagehand.entitlements \
    --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"

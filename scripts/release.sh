#!/bin/bash
# Builds, notarizes and staples Stagehand, zips it, and writes the Sparkle update feed.
# One-time setup of the notary credentials (stored in the login Keychain):
#   xcrun notarytool store-credentials musicdatalabs-notary \
#       --apple-id <apple id> --team-id Q47N78X9DT --password <app-specific password>
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-musicdatalabs-notary}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
ZIP="build/Stagehand-$VERSION.zip"

RELEASE=1 ./scripts/build.sh

rm -f "$ZIP"
ditto -c -k --keepParent build/Stagehand.app "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple build/Stagehand.app

# Re-zip so the download carries the stapled ticket.
rm -f "$ZIP"
ditto -c -k --keepParent build/Stagehand.app "$ZIP"
spctl --assess --type execute -vv build/Stagehand.app

# Sparkle appcast, signed with the EdDSA key in the login Keychain (account "stagehand").
# The app reads releases/latest/download/appcast.xml, so it must be uploaded with every release.
APPCAST_DIR="build/appcast"
rm -rf "$APPCAST_DIR" && mkdir -p "$APPCAST_DIR"
cp "$ZIP" "$APPCAST_DIR/"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast --account stagehand \
    --download-url-prefix "https://github.com/maxflach/stagehand/releases/download/v$VERSION/" \
    --link "https://github.com/maxflach/stagehand" \
    "$APPCAST_DIR"

echo "Release ready: $ZIP and $APPCAST_DIR/appcast.xml"
echo "Publish: gh release create v$VERSION \"$ZIP\" \"$APPCAST_DIR/appcast.xml\" --target main --title \"Stagehand $VERSION\""

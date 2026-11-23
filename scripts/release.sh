#!/bin/bash
# Builds, notarizes and staples Stagehand, then zips it for distribution.
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
echo "Release ready: $ZIP"

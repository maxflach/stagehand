# Stagehand

macOS app (Swift, SwiftPM, no Xcode project). Virtual display + ScreenCaptureKit stage for meeting screen sharing. See SPEC.md for the feature scope.

- Clean-room project: do not copy code from Gorian90/BetterScreenSharing (no license). The virtual display header comes from DeskPad (MIT), see THIRD_PARTY_NOTICES.md.
- Regular Dock app with a control panel window. No menu bar extra (the user's laptop has a notch).
- Build: `./scripts/build.sh`. Release: `./scripts/release.sh` (notarytool profile `musicdatalabs-notary`).
- Signing: "Developer ID Application: MusicData Labs Sweden AB (Q47N78X9DT)". Bundle id `com.musicdatalabs.stagehand`.
- Branches: `develop` is the working branch, `main` is releases.

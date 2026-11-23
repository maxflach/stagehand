# Stagehand

macOS app (Swift, SwiftPM, no Xcode project). Virtual display + ScreenCaptureKit stage for meeting screen sharing. See SPEC.md for the feature scope.

- Clean-room project: do not copy code from Gorian90/BetterScreenSharing (no license). The virtual display header comes from DeskPad (MIT), see THIRD_PARTY_NOTICES.md.
- Regular Dock app with a control panel window, plus a menu bar icon. `stagehand://menu` opens that menu at the pointer (the user's SketchyBar item calls it, since the native menu bar is hidden there).
- Updates: Sparkle 2 (SwiftPM). Feed: `releases/latest/download/appcast.xml`. EdDSA private key is in the login Keychain, account `stagehand`; public key in Info.plist. Every GitHub release must include `appcast.xml` from `release.sh`.
- Keep CPU low: stage capture is 30 fps, the panel preview only runs while the panel is visible, and avoid endless SwiftUI animations or shadows on live views (they redraw every frame).
- Build: `./scripts/build.sh`. Release: bump Info.plist versions, merge to main, `./scripts/release.sh` (notarytool profile `musicdatalabs-notary`), then `gh release create` with the zip and appcast.xml.
- Signing: "Developer ID Application: MusicData Labs Sweden AB (Q47N78X9DT)". Bundle id `com.musicdatalabs.stagehand`.
- Branches: `develop` is the working branch, `main` is releases.

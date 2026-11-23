# Stagehand

Share one screen in Teams, Zoom, Meet or Slack, then change what it shows with a keystroke, without stopping the share.

Stagehand creates a virtual display named **Stagehand**. Share that display once in the meeting app. Pick any window or screen in the Stagehand control panel (or with the shortcuts) and it fills the shared display. On top you can add your webcam, a spotlight or a highlight around the cursor, or a full-screen break countdown.

## Shortcuts

| Keys | Action |
|---|---|
| ⌃⌥⌘1 … 9 | Show source 1 to 9 from the list |
| ⌃⌥⌘← / → | Previous / next source |
| ⌃⌥⌘C | Webcam on / off |
| ⌃⌥⌘S | Spotlight on / off |
| ⌃⌥⌘H | Highlight cursor on / off |
| ⌃⌥⌘B | Start / stop break countdown |
| ⌃⌥⌘R | Refresh the window list |

## Build

```bash
./scripts/build.sh          # build/Stagehand.app, Developer ID signed (hardened runtime)
./scripts/release.sh        # + notarize, staple and zip (needs the musicdatalabs-notary profile)
```

Requires Xcode, macOS 14 or later. The first launch asks for Screen Recording; reopen the app after allowing it.

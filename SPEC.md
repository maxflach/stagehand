# Functional spec

Written from the public README and feature list of a similar app, not from its code.

## Goal
Share one thing in a meeting app (Teams, Zoom, Meet, Slack) and change what that shows
with a keystroke, without stopping and restarting the share.

## Core
- The app creates a virtual display. The user shares that display once in the meeting app.
- The user picks what the display shows: any window, or any physical screen.
- Global hotkeys switch between sources without touching the meeting app.
- Everything runs locally: no network, no drivers, no plug-ins.

## Overlays on the shared display
- Webcam picture-in-picture on top of the shared content.
- Spotlight: dim everything except an area around the cursor.
- Highlight: mark an area or the cursor position.
- Countdown timer for breaks, shown full screen on the shared display.

## App shell
- Menu bar control panel to pick sources, toggle overlays and edit hotkeys.
- First-run guide for Screen Recording and Camera permissions.
- macOS 14 or later, Apple Silicon and Intel.

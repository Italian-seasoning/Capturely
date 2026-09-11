# Capturely Project Outline

## Product Goal

Capturely is a native macOS gaming clipping app: a lightweight, local-first replay recorder inspired by Medal, but with its own native macOS identity, low resource usage, and editor-friendly clip files.

The first target use case is Roblox. For testing, the app currently uses:

- Main detected app label: `REC · ROBLOX`
- Subtitle/window context: `Rivals · 60s buffer · Window locked`

The app should feel like a compact premium replay cockpit, closer to NVIDIA replay than a full video editor.

## Core Product Direction

- Native macOS app, not Electron.
- Full app window that can minimize into the menu bar.
- Compact fixed-size recording window.
- Manual clipping first.
- Local-first clip storage.
- Future options for iCloud storage and adding clips to Photos.
- Clip organization by `Game / Date / Time`.
- Recording should target the detected game window, not a full-screen generic capture.
- Games are manually added first, with a light Applications folder scan as an optional helper.
- Default buffer should be around 60 seconds.
- User-configurable recording settings for people who edit heavily.
- Future voice trigger support, similar to "Medal clip that", but using Capturely's own phrase.
- Future reaction/audio-trigger clipping is a maybe-later feature.

## What Has Been Built

The current project is a SwiftPM-based native macOS SwiftUI app located at:

the repository root

Current app foundations:

- SwiftUI macOS app scaffold.
- Compact fixed-size app window.
- Native macOS sidebar/titlebar structure.
- Recording page with dark glass styling.
- Always-visible sidebar recording status.
- Roblox-focused recording display metadata.
- Recent clips model behavior.
- Game registry persistence.
- Process matching foundations.
- Clip path/date organization logic.
- App bundle build/verify script.

Current recording UI:

- Compact hero recording card.
- `REC · ROBLOX` detected app status.
- `Rivals · 60s buffer · Window locked` subtitle.
- Small audio waveform strip under the subtitle.
- Desktop-native Save Clip button with `⌥⌘C`.
- Minimal Recent Clips cards.
- Recent clips include blurred thumbnail-style preview blocks.
- Recent clips show ROBLOX / Rivals metadata.
- Bottom quick settings are limited to four tiles:
  - Quality
  - Video
  - Audio
  - Hotkey

Recently removed from the overbuilt UI pass:

- Large replay timeline.
- Progress ring.
- Moving playhead.
- Redundant Storage bottom tile.
- Redundant Detected Game bottom tile.
- Excessive empty space.
- Resizable window behavior.
- Sidebar status hidden-until-hover behavior.

## Current Verification

Latest verified state:

- `swift test` passed with 14 tests.
- `./script/build_and_run.sh --verify` passed.
- App bundle verified at:

`dist/Capturely.app`

Useful local commands:

```sh
cd Capturely
swift test
./script/build_and_run.sh --verify
./script/build_and_run.sh
```

## Important Design Notes

Keep the UI compact and Apple-native.

The user specifically wants:

- Black/red recording feedback.
- Neutral macOS glass styling for the rest of the interface.
- Minimal layout.
- No redundant stats.
- No huge empty sections.
- No window preview.
- Recent clips at the top of the workflow.
- Settings and stats kept smaller.
- Games managed in Settings.
- Sidebar status always visible.
- Fixed compact window shape.
- Apple styling for the real app, not a generic web dashboard look.

Do not copy Medal branding or naming.

## What We Are Looking To Build Next

The next milestone is real recording functionality, not editing.

Target flow:

1. User manually adds a game.
2. Capturely watches for that game to start.
3. When a known game starts, Capturely detects the app/window.
4. Capturely notifies the user that replay recording is active.
5. Capturely records a rolling replay buffer.
6. User clicks Save Clip or presses `⌥⌘C`.
7. Capturely saves the last buffer segment locally.
8. The clip appears at the front of Recent Clips.
9. Later, the Library page manages saved clips.

## Recommended Next Implementation Phase

### 1. Permissions

Add and verify macOS permissions:

- Screen Recording.
- Microphone, if mic capture is enabled.
- Clear in-app permission status.
- Graceful degraded states when permissions are missing.

### 2. Game/Window Capture

Use ScreenCaptureKit for capture.

Initial target:

- Detect Roblox.
- Capture the Roblox game window.
- Support window title/experience metadata when available.
- Handle the window disappearing, relaunching, or changing title.

### 3. Rolling Replay Buffer

Build the core replay buffer.

Goals:

- Default around 60 seconds.
- Support user-configurable lengths such as 30 seconds and 5 minutes.
- Keep memory usage very low.
- Avoid keeping large raw frame buffers in RAM.
- Prefer efficient encoded segments or another compact buffer strategy.

### 4. Save Clip

Implement real clip save behavior.

Expected behavior:

- Save last replay buffer when Save Clip is clicked.
- Save last replay buffer when `⌥⌘C` is pressed.
- Name and organize clips by game/date/time.
- Insert saved clip metadata into Recent Clips immediately.

Desired folder shape:

```text
ROBLOX/
  2026-06-06/
    12-34-56.mov
```

### 5. Audio

Start simple:

- Capture game/system audio if available.
- Add microphone support later.
- Keep mocked waveform UI until real audio levels are wired in.
- Eventually map live audio levels into the waveform strip.

### 6. Performance Pass

Capturely should be extremely light, especially because the main use case is Roblox.

Measure:

- Idle CPU/RAM.
- Active recording CPU/RAM.
- Save clip spike.
- Disk write behavior.
- Buffer memory growth over time.

Tune:

- Balanced default quality.
- Encoder settings.
- Segment duration.
- Buffer retention.

### 7. Settings Page

Move configuration into Settings.

Settings should eventually include:

- Added games.
- Manual add game.
- Optional Applications folder scan.
- Buffer length.
- Quality preset.
- Video resolution/FPS.
- Audio source.
- Mic toggle.
- Storage location.
- iCloud/Photos options.
- Hotkey.

### 8. Menu Bar Behavior

Capturely should remain useful when minimized.

Menu bar goals:

- Show recording status.
- Save clip from menu bar.
- Open main window.
- Show detected app/game.
- Keep capture alive while the main window is closed or hidden.

## Current Priority

The most important next task is:

**Make Capturely capture a Roblox window into a low-resource rolling buffer and save a real clip on command.**

The UI is in a good enough compact state for now. The next pass should focus on functional recording, permissions, and performance.

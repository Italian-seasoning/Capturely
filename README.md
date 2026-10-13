# Capturely

<p align="center">
  <img src="Assets/CapturelyLogo.png" width="180" alt="Capturely logo">
</p>

[View the software showcase](https://nolan-mac-apps.nolankrahn.chatgpt.site/apps/capturely)

Capturely is a native macOS replay clipping app for games. The MVP targets macOS 26 and records configured game windows into a local replay buffer.

## Quick install

```sh
brew install --cask italian-seasoning/tap/capturely
```

Current preview: **0.1.3**. [Download the ZIP](https://github.com/Italian-seasoning/Capturely/releases/download/v0.1.3/Capturely-0.1.3-macOS.zip).

Requires macOS 26 or newer on Apple silicon.

These previews are not Apple-notarized. Homebrew verifies the archive checksum and leaves Gatekeeper enabled. If macOS blocks the first launch, review the app in **System Settings → Privacy & Security**. Sparkle verifies subsequent in-app updates with its signed feed.

## See the app

![Capturely recording workspace in standby with replay duration and quality controls](docs/screenshots/capturely-recording.png)

![Capturely theme, replay workflow and capture-source settings](docs/screenshots/capturely-settings.png)

[Watch the interface walkthrough](docs/screenshots/capturely-walkthrough.mp4). This short sequence shows the captured interface views; it is not a gameplay or download benchmark.

Screenshots show local preview builds. Empty queues and standby states are shown where applicable.


## Replay analysis and FrameBar

The current source adds recording bookmarks, sampled performance timelines, clip comparisons, and local integration with [FrameBar](https://github.com/Italian-seasoning/FrameBar). Capturely excludes FrameBar from display captures and can export its metrics as optional subtitle and JSON sidecars. Bookmarks mark moments without saving a replay; use **Control–Option–Command–B** while recording, then seek them in a saved clip's editor.

See [Replay analysis](docs/REPLAY_ANALYSIS.md), [FrameBar integration](docs/FRAMEBAR_INTEGRATION.md), and [Performance review](docs/PERFORMANCE_REVIEW_2026-10-10.md) for setup, measurements, and remaining gameplay checks. Sampled FPS summaries do not measure frame-level 1% lows. The **0.1.3** release includes the committed replay telemetry and interface improvements, a repaired Sparkle feed, and macOS 26 requirements. Later work on `main` may extend that release.

## Install

```bash
brew tap Italian-seasoning/tap
brew install --cask capturely
```

Capturely checks the signed [Sparkle](https://sparkle-project.org) release feed automatically. You can also choose **Check for Updates…** from the menu bar.

## Run

```bash
./script/build_and_run.sh
```

For live capture QA, prefer launching with this script instead of alternating
between Xcode DerivedData builds and `dist/Capturely.app`. Screen Recording
permission is stored against the signed app identity, so one stable launch path
keeps permission prompts predictable.

If you build from Xcode, use Xcode for editing, tests, and build errors, then
launch the signed app with `./script/build_and_run.sh` for ScreenCaptureKit
runtime QA. Xcode's default SwiftPM Run action launches a different build
product than `dist/Capturely.app`, so macOS can show a separate Screen Recording
permission entry even when the signed Capturely app is already approved.

`build_and_run.sh` signs the finished app bundle. If no certificate-backed code
signing identity is available, it falls back to ad-hoc signing and prints a
warning because macOS may ask for Screen Recording permission again after code
changes. Set `CAPTURELY_CODE_SIGN_IDENTITY` to an Apple Development, Developer
ID, or local code signing identity to keep permission approval stable across
rebuilds.

To create a local-only signing identity for Capturely development:

```bash
./script/create_local_signing_identity.sh
CAPTURELY_CODE_SIGN_IDENTITY="Capturely Local Development" ./script/build_and_run.sh
```

## Verify

```bash
xcodebuild -workspace .swiftpm/xcode/package.xcworkspace -scheme Capturely build
xcodebuild -workspace .swiftpm/xcode/package.xcworkspace -scheme Capturely test
./script/build_and_run.sh --verify
```

## Release

Current public previews are not notarized. The optional certificate-backed release workflow requires the secrets listed in [the workflow](.github/workflows/release.yml) and `RELEASE_AUTOMATION_ENABLED=true`; it is not required to install the current preview.

## Local Clip Folder

Capturely saves clips under:

```text
~/Movies/Capturely/Clips/<Game>/<Date>/<Time>/
```

Each saved clip folder contains `clip.mov` and `metadata.json`. When editable audio is enabled and more than one source is captured, it also contains `editable-source.mov` with ordered app and microphone tracks.

The library supports search, game/star/date filters, clip titles, tags, native sharing, and Original/1080p/720p exports. In Settings, add up to four running apps under Isolated App Tracks; Capturely records those apps separately instead of the broad system mix, while keeping the microphone on its own track. The clip editor provides mute, solo, and gain controls for each preserved track.

## Appearance and reaction clips

Choose Daylight (white, red, and ice blue), Harbor, Neon, or Graphite in Settings. The compact in-game overlay opens from the top-left and collapses in height before fading, with a light sweep and support for Reduce Motion.

Automatic reaction clipping uses the microphone level, a configurable threshold, and a cooldown. It requires microphone permission, an enabled microphone, and a running replay buffer. The microphone meter in Settings shows the input level.

## Discord Rich Presence

Enable the local presence bridge in Capturely Settings. The opt-in bridge serves capture activity on `127.0.0.1:48731`, without clip paths or window titles. The companion Vencord plugin is in [integrations/vencord/EnhancedPresence](integrations/vencord/EnhancedPresence). Copy that directory into a Vencord source checkout's `src/userplugins`, build Vencord, and enable EnhancedPresence. Enter your own Discord application ID in the plugin settings; presence remains unpublished until one is configured.

This integration provides Capturely activity. The broader universal EnhancedPresence engine is not included.

## License and attribution

[MIT](LICENSE) — Copyright © 2026 [Italian-seasoning](https://github.com/Italian-seasoning). Forks and redistribution are allowed; retain the copyright and license notice. Please identify independently maintained forks and link back to this project. Third-party components retain their own licenses.

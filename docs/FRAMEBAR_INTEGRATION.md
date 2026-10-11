# FrameBar recording integration

FrameBar's on-screen overlay is excluded from display recordings by application identity. Window recording already captures only the selected game's window. Capturely refreshes its content filter on companion launch/exit, with a health-check retry. Launch FrameBar before capture for exclusion from the first recorded frame; a companion launched during capture requires an asynchronous filter update.

With **Log game process while capturing** enabled, Capturely requests FrameBar readings for the matching game process. FrameBar keeps its existing CPU budget and reader setting: this does not start another screen capture or override disabled FPS reading. Both apps must be running; Roblox performance stats must be visible and FrameBar must have screen-recording access. Unavailable readings remain blank.

Saved clips contain `telemetry.json`, analysis-friendly `telemetry.csv` and optional `clip.srt` subtitles when fresh companion samples exist. **Cut & Mix → Performance subtitles** toggles the captions without modifying video pixels. Export copies the sidecars beside the video. SRT can be enabled in players supporting external subtitles; it is not an embedded QuickTime subtitle track. Edited copies trim and rebase telemetry to their new start.

The two-second sampler maps readings into the selected replay segments using their capture-start timestamps, accounting for trimmed starts and gaps. Timing is approximate, not per-frame instrumentation. Stats include sampled game FPS, system and game CPU/RAM, system GPU, ping, visible CPU/GPU milliseconds, thermal state, recording FPS and encoder drops. Recording FPS is the session-average capture callback rate, not game FPS. Logs preserve the stats-read timestamp; stale OCR readings expire after ten seconds. A sample is displayed for no more than three seconds without a fresh snapshot. RAM CSV columns explicitly use GiB; the compact UI uses G/GB.

No temperature, clock, VRAM or live 1% low is fabricated. FrameBar's per-frame import can calculate genuine lows after a MicroProfiler export, but OCR samples cannot.

The 2026-10-10 update adds recording bookmarks, performance timelines, clip comparisons, and FrameBar setup/CPU diagnostics. See [Replay analysis](REPLAY_ANALYSIS.md) for controls, limits, and current validation.

## Review fixes and validation

- Health task cancellation now exits before another check and terminates when its backend is gone.
- Game-window selection ignores tiny/nonstandard window layers.
- Empty/dot/dot-dot game names fall back to a safe library folder. Timestamp collision fallback uses a UUID rather than another potentially colliding timestamp.
- Process-log metadata/index writes now run asynchronously instead of blocking the main actor.
- New telemetry I/O is bounded: a small atomic local snapshot, a ten-minute sample ring and utility-priority export. FrameBar publishes only while Capturely requests telemetry. Workspace observer subscriptions cancel with the coordinator.
- Tests cover replay gaps, trimmed starts, missing samples, subtitle rebasing and path containment. Existing hardware-encoder tests exercise generated video/audio replay files, not a live ScreenCaptureKit/Roblox session.

Live gameplay FPS recognition, physical ProMotion changes, first-frame overlay exclusion, subtitle playback on a real recorded clip and CPU during simultaneous recording/OCR still require runtime verification. The under-1% target applies to FrameBar, not Capturely's video encoder. A successful build alone does not establish these outcomes.

2026-10-09 validation: FrameBar 18 tests passed; Capturely 131 tests passed. Both Release bundles build and are signature-verified. FrameBar averaged 0.05% of one core over a 20-second idle run with no active game/capture. The live Low Power Mode panel shows Adaptive. An installation fix replaces FrameBar's app bundle instead of merging it: leftover Debug dylibs had invalidated the installed Release resource seal. Permissions may still require re-enabling the stable signed build in macOS settings.

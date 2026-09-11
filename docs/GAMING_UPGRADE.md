# Capturely gaming upgrade

Built for macOS 26 with ScreenCaptureKit, hardware HEVC/H.264 encoding, and a rolling disk buffer.

## Quality

| Profile | Resolution cap | Frame rate cap | Codec | Video bitrate |
| --- | --- | --- | --- | --- |
| Light | 720p | 30 fps | HEVC | 5 Mbps |
| Rivals | 1080p | 60 fps | HEVC | 16 Mbps |
| Studio | 1440p | 60 fps | HEVC | 28 Mbps |
| Custom | 720–1440p | up to 60 fps | HEVC or H.264 | 5–36 Mbps |

Rivals is the recommended starting point. Light reduces capture load further. Studio increases pixel and storage load. Resolution is capped without upscaling; aspect ratio is preserved with even encoder dimensions. Window capture uses Retina pixel dimensions.

The selected profile now applies to Roblox, including registrations that previously forced a low-quality preset. Each save requests the configured replay length, including repeated saves. Actual saved duration is limited by available footage.

## Recording changes

- Release builds replace Debug builds for normal use.
- ScreenCaptureKit's bounded queue supplies samples synchronously to the writer; no second unbounded queue retains frames.
- Hardware encoding is required, with no silent CPU encoder fallback. Encoder failures appear in diagnostics.
- Game audio and microphone use separate timestamped inputs, with independent gains at export.
- Video is copied for ordinary exports. FFmpeg, when already installed, can mix audio without re-encoding video. The native audio-mix fallback can re-encode video and cost more.
- In-progress exports hold hard links to segments, protecting footage from buffer expiry. Copy is the fallback when links are unavailable.
- Segment completion is sorted chronologically; stop/error paths finalize writers.
- Configured save hotkeys appear in the UI without conflicting fixed shortcuts.
- Static graphite/cyan panels replace the layered red treatment; primary controls, quality, and replay duration are prominent.

## Validation

Xcode Debug tests include a real hardware encoder check: 150 video frames, simultaneous game/mic audio, segment rollover, replay export, and decoding an exported frame. Other checks cover retention during export, source gains, selected quality, and repeated saves.

The Release bundle was built, signed, verified, launched, and inspected through its native UI. Rivals was selected in the app.

The follow-up investigation repaired a signing-identity mismatch, and the user restored the existing macOS approval. A real desktop recording, replay export, and full-file decode now pass, with zero encoder backpressure drops during the test. Live Roblox gameplay and microphone synchronization remain unverified. See PERMISSION_AND_NETWORK_DIAGNOSIS.md for evidence and the Wi-Fi latency investigation.

For a live check: record a moving Rivals session, save overlapping clips across several 20-second segment boundaries, and inspect playback plus Diagnostics → Encoder drops. Compare gameplay FPS with recording off/on under the same game settings; use Light if recording pressure is excessive.

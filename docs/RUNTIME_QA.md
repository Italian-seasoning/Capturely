# Capturely Runtime QA

Use this checklist for live Roblox capture validation. Do not include clip contents or screen contents in diagnostics; diagnostics should contain only status, timestamps, and paths.

## Setup

1. Build and verify the app:

   ```sh
   cd Capturely
   swift test
   swift build
   ./script/build_and_run.sh --verify
   ```

2. Check the signing output from `build_and_run.sh --verify`.
   - `Signed ... with <identity>` means rebuilds should keep the same Screen Recording permission approval.
   - `Capturely was ad-hoc signed` means macOS may ask for Screen Recording permission again after code changes.
   - To stabilize local rebuilds, install a certificate-backed code signing identity and set `CAPTURELY_CODE_SIGN_IDENTITY` when needed.
   - For local-only development, run `./script/create_local_signing_identity.sh`, then launch with `CAPTURELY_CODE_SIGN_IDENTITY="Capturely Local Development" ./script/build_and_run.sh`.

3. Launch Capturely:

   ```sh
   ./script/build_and_run.sh
   ```

   Use Xcode for editing, build diagnostics, and tests. For live ScreenCaptureKit
   runtime QA, launch this signed app bundle instead of Xcode's default SwiftPM
   Run product so macOS keeps one stable Screen Recording permission entry.

4. Open the Recording page and click the debug button beside Recent Clips.
5. Confirm the debug panel shows `Waiting for Roblox`, no detected app, and an output folder under `~/Movies/Capturely/Clips` unless a custom folder is configured.

## Permissions

1. If macOS asks for Screen Recording permission, grant it for Capturely.
2. Quit and reopen Capturely after changing Screen Recording permission.
3. Confirm the UI changes from `Screen Recording permission required` to `Waiting for Roblox`.
4. Microphone is not part of the current runtime path. Do not treat missing microphone permission as a failure unless a preset explicitly enables mic capture.
5. Keep using the same launch path during QA. Switching between Xcode builds and `dist/Capturely.app` can create separate macOS permission entries.

## Roblox Detection

1. Launch Roblox.
2. Confirm Capturely changes to `Starting capture`.
3. Confirm the menu bar item shows a Capturely recording status.
4. Confirm the debug panel shows:
   - Detected app: Roblox or ROBLOX
   - Capture state: Recording, Buffer warming up, or Ready to save
   - Recent Events contains `appDetected`, `captureStarting`, and `captureStarted`

## Replay Buffer

1. Keep Roblox open for at least 60 seconds.
2. Confirm buffer duration increases in the debug panel.
3. Confirm Recent Events eventually contains `firstVideoSampleReceived`.
4. If system/game audio is available, confirm Recent Events contains `firstAudioSampleReceived` and Audio tracks shows `Game only`.
5. Confirm the UI reaches `Ready to save`.

## Save Button

1. Click Save Clip.
2. Confirm the UI changes to `Saving replay`.
3. Confirm Recent Events contains:
   - `saveRequested`
   - `activeSegmentFlushed`
   - `compositionStarted`
   - `outputValidated`
   - `metadataWritten`
   - `thumbnailGenerated`, if thumbnail creation succeeds
   - `clipIndexed`
4. Confirm a new clip appears in Recent Clips and Library.
5. Confirm the saved `.mov` opens and plays.

## Hotkey Save

1. Return to Roblox.
2. Press `Option+Command+C`.
3. Confirm the same save events appear.
4. Confirm a second saved clip appears in Library.

## Duplicate Saves

1. Trigger two saves in the same second if possible.
2. Confirm both save folders exist and neither overwrites the other.
3. Expected folder suffix pattern: `HH-MM-SS`, then `HH-MM-SS-2`.

## Thumbnails

1. Open Library.
2. Confirm saved clips show generated thumbnails when possible.
3. If thumbnail generation fails, confirm the placeholder appears and the clip still remains indexed only if the `.mov` output is valid.

## Library Actions

1. Click Play on a saved clip and confirm it opens.
2. Click Reveal in Finder and confirm Finder selects the saved clip.
3. Delete a test clip and confirm:
   - A confirmation appears.
   - The clip is moved to Trash.
   - The Library list updates.
   - Other saved clips remain intact.

## Menu Bar

1. Close or hide the main Capturely window.
2. Use the menu bar item to Save Clip.
3. Use Open Library and Open Settings.
4. Use Export Diagnostics and confirm Finder reveals a diagnostics `.txt` file.

## Roblox Relaunch

1. Quit Roblox.
2. Confirm Capturely returns to `Waiting for Roblox`.
3. Relaunch Roblox.
4. Confirm Capturely starts a new capture session and stale temporary replay segments do not accumulate.

## Diagnostics Export

1. Click the debug-panel export button or menu bar Export Diagnostics.
2. Open the exported text file.
3. Confirm it includes:
   - Detected app/game
   - Recording state
   - Permission status
   - Segment count and buffer duration
   - Last video/audio sample timestamps
   - Audio status
   - Output folder
   - Recent state transitions
   - Last save result/error
   - Recent restart attempts
4. Confirm it does not include screen contents, clip contents, or file contents.

## Stall Handling

1. During recording, watch the debug panel for stale video sample timestamps.
2. If video samples stall, confirm the UI/event timeline reports `Capture stalled, restarting`.
3. Confirm Capturely attempts a safe restart and records a `captureStalledRestarting` event.
4. If diagnostics show sustained video input backpressure, confirm Capturely restarts once in Performance Mode and records a `captureStalledRestarting` event with a backpressure message.

## Performance Gate

Use the same Roblox experience, graphics settings, and display for each run.

1. Capture a 60-second baseline with Capturely open but not recording:
   - Roblox FPS range
   - Capturely CPU in Activity Monitor
   - Overall CPU pressure
2. Start recording with each preset: Storage Saver, Balanced, Editing, and Custom.
3. For each preset, record a 60-second sample and confirm:
   - Roblox FPS drop is not noticeable during steady recording.
   - Activity Monitor does not show sustained Capturely CPU spikes.
   - Diagnostics performance lines show low dropped-frame counts and stable append timing.
   - Replay segment retention stays close to the selected clip length plus one short segment of padding, not a fixed five-minute temp buffer.
4. For each preset, click Save Clip during gameplay and confirm:
   - Roblox FPS drop is 2 FPS or less while saving.
   - Diagnostics show `Direct segment copy` for single-segment saves or `ffmpeg stream copy` for multi-segment saves when audio gain is unchanged.
   - Segment flush timing stays low with the shorter active segments; compare save feel against older 10-second segment builds if available.
   - Thumbnail generation can finish after the clip is indexed and does not block the save.
5. Export diagnostics after each preset and keep the files with QA notes.

## Pass Criteria

The runtime pass succeeds when Roblox detection, buffer warming, Save Clip, hotkey save, playable output, metadata, thumbnails, Library actions, menu bar actions, diagnostics export, Roblox relaunch behavior, and the Performance Gate all pass without silent failure.

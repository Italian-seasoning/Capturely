# Replay analysis update — 2026-10-10

FrameBar now has an FPS setup check and a 30-second CPU audit. Capturely adds recording bookmarks, a clip performance timeline, and clip comparisons. These tools use the existing sampling pipeline; they add no background sampling timer.

## FPS setup

In FrameBar Settings → FPS & Capture, choose **Check FPS setup**. The report separates screen access, the stats-reader setting, the foreground game window, and a fresh FPS reading. Return to Roblox with Shift–F5 or Command–Shift–F5 stats visible to complete one check. Fn may be needed. Cancel clears a queued check. The check works even when FPS is absent from the menu bar and overlay; disabling the reader also cancels it.

The installed app currently reports screen access as unconfirmed. This update exposes that status and enables a manual capture check; it does not reset permissions or establish that gameplay OCR works. A successful read can confirm access even when macOS preflight reports otherwise.

## CPU audit

Choose **Run 30-second CPU audit**, then return to the workload being measured. Results group existing CPU samples by background/settings, live panel, Roblox overlay, hidden overlay, or Roblox with Capturely. Recording with the game in the background has a separate group. Each group shows the sample mean, peak sample, and count below 1% of one CPU core. Results stay in memory until relaunch.

Verified on the installed Release app: background/settings averaged **0.05%**, peaked at **0.16%**, and all **16/16 samples** were below 1%. This is not a gameplay or recording measurement, and sampled peaks are not instantaneous maximums.

## Bookmarks

During recording, press **Control–Option–Command–B**, or choose **Bookmark moment** in Capturely's menu. The Recording page has the same action. Bookmarking marks the current moment without saving a replay. It requires active recording; repeated presses within half a second are ignored.

The Recording page and menu show the last accepted bookmark time. Standby disables the action and clears that feedback.

Save a replay containing that moment. **Cut & Mix → Bookmarks** lets you seek to each marker. Markers outside the saved replay or in recording gaps are omitted. Edited copies trim and rebase markers. The clip metadata stores them, and exports copy a `<video>.bookmarks.json` sidecar. Older clip metadata remains compatible.

Bookmarks and telemetry are copied before the active segment's asynchronous flush, so stopping capture during that flush cannot clear the save's metric/marker data. Optional bookmark-sidecar failures report a diagnostic while preserving the bookmark metadata and video.

## Timeline and comparison

Enable **Log game process while capturing** in Capturely and run FrameBar before recording. In a saved clip's **Cut & Mix**, expand **Performance timeline & comparison**. Choose sampled FPS, ping, system CPU, or system GPU. Click the graph to seek. Missing readings leave gaps; summaries weight each reading by its covered time.

Choose another clip with telemetry in **Compare with** to compare means and coverage. Different scenes, game settings, and clip lengths can affect those values. This is a comparison of sampled readings, not a controlled benchmark or frame-level 1% low. Genuine lows still require FrameBar's per-frame MicroProfiler/CSV import.

The copy button places the current metric summary and optional comparison on the local clipboard, including coverage and the sampled-data qualification.

Telemetry loads only when opening a clip/editor or selecting a comparison. Loads are bounded to 4 MB and 5,000 entries and run at utility priority. Graph points and summaries are cached until the metric or comparison changes. A basic clip without telemetry installs no extra player time observer. Comparison cancellation prevents an older selection from replacing a newer one.

## Validation

- FrameBar: 26 tests passed, with a saved Xcode result bundle. Installed Release signature passed strict verification. Native UI exercised setup, cancellation, and the completed CPU audit. A native pixel test checks visible text/icon alignment in stacked and single-row layouts, with two and four readings.
- Capturely: the exact publication snapshot passed 136 tests with the optional native-render test enabled, including bookmark trimming/gaps, legacy metadata, sidecar conflict protection, weighted summaries, malformed telemetry, and waiting-window retry policy. The render used synthetic readings without screen capture or library changes. Unrelated local Discord work was excluded from this snapshot.
- Both Release builds were installed and signature-verified. Capturely was in standby before replacement; the new bookmark button is disabled there as intended.
- Live Roblox OCR, simultaneous recording CPU, overlay exclusion, and a complete bookmark/save/edit/export gameplay session remain for the user's test.

Optional native render command: `CAPTURELY_RENDER_REPLAY_ANALYSIS=/tmp/Capturely-ReplayAnalysis-verification.png swift test --filter replayAnalysisRendersInANativeWindow`. Normal regression runs skip that optional UI test.

Standby efficiency measurements and the delayed-window fix are described in [Performance review](PERFORMANCE_REVIEW_2026-10-10.md).

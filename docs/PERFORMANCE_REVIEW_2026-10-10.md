# Capturely efficiency and reliability review

## Changes

The existing health loop updates every ten seconds in standby and every two seconds during recording. State transitions change the interval without adding another timer. Unchanged health, status, recording state, configuration lock, and microphone level no longer trigger redundant published updates. The Performance panel reports the current interval.

Automatic capture retries a waiting game window through that existing standby loop. A game process can launch before ScreenCaptureKit can resolve its window; the process match previously stayed unchanged and never retried. Retries require the same matched game, automatic sessions enabled, no manual session, and a PID that the user has not stopped. They introduce no permission prompt. Repeated waiting results do not publish duplicate state or write repeated starting diagnostics. Recording keeps its existing two-second stall/backpressure checks.

Recording bookmarks now display the last accepted time. The clip timeline can copy a qualified metric summary and comparison. Timeline data and summaries stay cached during playback; comparison loads reject results from superseded selections. Clips without telemetry install no additional playback observer.

Replay saves copy metric samples and bookmarks before asynchronously flushing the active segment. A stop during the flush can no longer clear those snapshots. Bookmark sidecars are optional; their failure retains the clip metadata and video.

## Measurements

Installed Release builds were measured in standby with the main window visible. Each measurement used process CPU-time deltas over thirty seconds after a five-second settling period. Percentages refer to one CPU core.

| Scenario | Before | After |
| --- | ---: | ---: |
| Standby, window visible | 2.133% | 0.667% |

This is one measurement per build, approximately 69% lower in this scenario. Other concurrent workloads can affect the result. It does not establish recording CPU, encoder performance, gameplay overhead, or a guaranteed ceiling. The final delayed-window retry remains dormant in standby without a matching waiting game and was added after this measurement.

FrameBar's separate thirty-second audit measured 0.05% average and 0.16% peak sample in background/settings, with 16/16 samples below 1%. Gameplay and simultaneous recording remain unmeasured.

## Validation and remaining runtime checks

The exact Capturely publication snapshot passed 136 tests with the optional native timeline rendering test enabled. Coverage includes waiting-window retry safety, replay/export validation, bookmark gaps and trimming, sampled metric coverage, malformed telemetry, and sidecar conflict protection. Unrelated local Discord changes were excluded. Native UI confirmed standby and disabled bookmark/save actions before replacing the app. No game or user screen recording was started for this review.

The delayed-window retry is verified as policy and compiled code; an actual launch with a delayed game window still needs runtime exercise. The user's Roblox test should also check FPS acquisition, click-through positioning, clean Capturely footage, metric subtitles, and a bookmark/save/edit/export session. Sampled FPS summaries are not true frame-level 1% lows; those require per-frame input.

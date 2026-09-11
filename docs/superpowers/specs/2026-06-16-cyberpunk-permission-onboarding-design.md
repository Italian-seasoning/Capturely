# Cyberpunk Permission Onboarding Design

Date: 2026-06-16
Project: Capturely
Status: Approved design direction, pending implementation plan

## Goal

Build a guided first-run onboarding cockpit for Capturely that checks and requests core permissions while letting the user confirm replay basics before entering the app.

The screen should feel like a premium cyberpunk replay system coming online, not a generic settings form. It must preserve Capturely's current black/red visual identity and compact native macOS feel.

## Scope

This onboarding pass covers:

- Screen Recording status and request action.
- Microphone status when microphone capture is enabled.
- Notification explanation, with real authorization still allowed to happen when recording starts.
- Replay buffer length summary/control.
- Save clip hotkey summary/control.
- Clip save location summary/action.
- Clear primary action that advances the user without trapping them.

This pass does not cover:

- Full game management or app scanning.
- Capture source selection.
- Full quality/audio mixer configuration.
- New theme switching.
- Editing, library redesign, or menu bar work.

The five color/font explorations from the visual brainstorming session are reserved as future main-UI theme inspiration. This onboarding implementation stays on the existing Capturely red palette, with only restrained cyan accents where the app already uses them.

## Recommended Approach

Use a single-screen setup cockpit.

The screen should show all first-run setup information at once, organized into two major zones:

- Left: permission system checks.
- Right: replay defaults.

This keeps the flow fast and avoids a heavy wizard while still feeling intentional. It also fits the current fixed-size app window better than a multi-step setup.

## Visual Direction

Use the current Capturely components and palette as the base:

- Background: near-black `CyberTheme.void`.
- Panels: dark red-black `CyberTheme.panel` and `CyberTheme.panelRaised`.
- Primary signal: `CyberTheme.red`.
- Secondary alerts: `CyberTheme.warning`.
- Success: `CyberTheme.success`.
- Optional accent: minimal `CyberTheme.cyan`.

The mood should borrow from the user's red diagnostic HUD references:

- Thin red technical borders.
- Scanline sweep.
- Small terminal labels.
- Big numbered system-check labels.
- Dense but readable microcopy.
- Tactical permission states like `REQUIRED`, `OPTIONAL`, `READY`, and `ARMED`.

Avoid the more experimental lime, magenta, violet, and amber palettes in this implementation. Also avoid the broken/noisy type-grid direction from the draft.

## Layout

The onboarding screen should replace the current simple vertical checklist with a compact two-column cockpit:

1. Header rail
   - Brand: `CAPTURELY SETUP`.
   - Status: `REPLAY SYSTEM CHECK`.
   - Animated scan/status line.
   - Short supporting copy: "Arm replay capture before launching a match."

2. Permission system panel
   - Screen Recording row: required, shows current status, has the main request action when missing.
   - Microphone row: optional unless `settings.recordsMicrophone` is true.
   - Notifications row: explains that alerts are used for recording and saved clips; can remain informational for now.

3. Replay defaults panel
   - Buffer length: existing `settings.replayDurationSeconds`.
   - Save hotkey: existing `settings.saveClipHotkey`.
   - Save location: existing `settings.clipLibraryURL` or default path.

4. Bottom command rail
   - Primary button changes by state:
     - Missing Screen Recording: `Request Access`.
     - Required microphone missing: `Request Microphone`.
     - Ready enough to proceed: `Enter Capturely`.
   - Secondary actions:
     - `Open Settings`.
     - `Skip for now` or equivalent non-blocking continue action.

## Behavior

Screen Recording is the main required permission for useful capture. The onboarding should call it out as the highest priority and route the request through the existing permission backend.

Microphone remains optional unless microphone recording is enabled. If mic capture is off, the row should read as optional and should not block entry.

Notifications should not block entry. The row should explain that notifications are used for recording and saved-clip alerts, but the app can still request notification authorization later when recording starts.

Replay basics should reflect the actual settings store. Changes made in onboarding should persist through existing settings paths, not a separate onboarding-only state model.

The user should be guided but not trapped. Even with missing permissions, they should have a way to enter the app or open Settings, because macOS permissions sometimes require a relaunch or a trip to System Settings.

## Components

Implement with small SwiftUI components that fit existing conventions:

- `OnboardingView`
  - Owns the screen composition.
  - Receives settings, permission summary, and action closures from `ContentView`.

- `OnboardingStatusHeader`
  - Renders the setup title, scanline rail, and readiness copy.

- `OnboardingPermissionRow`
  - Renders icon, title, status chip, detail, and optional action.
  - Handles Screen Recording, Microphone, and Notifications display.

- `OnboardingReplaySettingRow`
  - Renders buffer, hotkey, and save location summaries.

- `OnboardingCommandRail`
  - Renders primary and secondary actions.
  - Computes the primary label from readiness state passed in by the parent.

Existing shared visual components such as `CyberPanel`, `CutCornerRectangle`, `CyberButtonStyle`, `CyberScanlines`, and `CyberTheme` should be reused instead of introducing a second style system.

## Data Flow

`CaptureBackend` remains the source of truth for permission and settings state.

`ContentView` should pass `OnboardingView`:

- `settings`
- `permissionSummary`
- action to request Screen Recording
- action to request Microphone if needed
- action to open Settings
- action to complete onboarding or continue
- actions for replay defaults only if the onboarding exposes editable controls

`OnboardingView` should not directly create or own permission services. It should only display state and call closures.

## Animation

Use smooth cyberpunk animation, but keep it controlled:

- Staged row reveal when onboarding appears.
- Subtle scanline sweep in the header.
- Soft red pulse on required missing permission.
- Status chip transitions when permissions become ready.
- Button press states using existing Cyber button styling.

Respect `accessibilityReduceMotion`. When reduced motion is enabled, skip staged movement and pulses, but keep clear static status changes.

Do not add large looping background motion, aggressive glitching, or layout-shifting hover effects.

## Error Handling

Missing Screen Recording:

- Show `REQUIRED`.
- Primary action requests access.
- If still missing after request, show guidance to grant Screen Recording in System Settings and relaunch Capturely.

Missing microphone while mic capture is enabled:

- Show `REQUIRED`.
- Primary action requests microphone.
- If denied, keep the row visible and allow the user to continue with mic capture disabled or open Settings.

Notifications:

- Show as informational or `LATER`.
- Do not block entry.

Settings persistence failures:

- Use existing backend messaging where available.
- Do not mark setup as fully ready if a setting change visibly fails.

## Accessibility

The onboarding must remain keyboard-usable and screen-reader understandable:

- All buttons have clear labels.
- Permission rows do not rely only on color; include text status.
- Focus rings remain visible.
- Reduced motion is respected.
- Text stays inside fixed window constraints.
- Status microcopy remains readable at the current compact window size.

## Testing

Add or update focused tests for:

- Screen Recording missing produces the correct onboarding primary action.
- Screen Recording ready allows `Enter Capturely`.
- Microphone only blocks when mic capture is enabled.
- Notifications do not block setup.
- Replay defaults display the current settings values.

Run validation after implementation:

```sh
xcodebuild -workspace .swiftpm/xcode/package.xcworkspace -scheme Capturely -destination 'platform=macOS' test -quiet
swift test
swift build
CAPTURELY_CODE_SIGN_IDENTITY="Capturely Local Development" ./script/build_and_run.sh --verify
```

Runtime permission QA should use the signed app bundle at:

```text
dist/Capturely.app
```

## Open Implementation Notes

The current worktree already contains broad modified Capturely files from previous backend/UI work. Implementation should touch only the files needed for onboarding and permission wiring unless tests reveal a direct dependency.

The visual companion mockups are saved under `.superpowers/brainstorm/` for reference only and should not be committed as product code.

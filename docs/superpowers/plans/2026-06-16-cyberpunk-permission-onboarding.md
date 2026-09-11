# Cyberpunk Permission Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Capturely's simple first-run checklist with a compact cyberpunk setup cockpit that checks permissions and confirms replay basics.

**Architecture:** Keep `CaptureBackend` as the source of truth for permissions and settings, and keep `OnboardingView` as a pure SwiftUI view that renders state and calls injected closures. Add a small testable readiness model inside the onboarding view file so the UI's primary action and blocking rules are deterministic.

**Tech Stack:** SwiftPM macOS app, SwiftUI, Swift Testing, ScreenCaptureKit permission state from existing `PermissionSummary`, Xcode workspace validation through `.swiftpm/xcode/package.xcworkspace`.

---

## File Structure

- Modify `Capturely/Sources/Capturely/Views/OnboardingView.swift`
  - Add `OnboardingReadiness`.
  - Replace the simple checklist with a single-screen red HUD cockpit.
  - Add focused subviews: `OnboardingStatusHeader`, `OnboardingPermissionRow`, `OnboardingReplaySettingRow`, `OnboardingCommandRail`, and small status chip helpers.
  - Keep the view driven by injected values and closures only.
- Modify `Capturely/Sources/Capturely/Views/ContentView.swift`
  - Pass existing backend actions into the richer `OnboardingView`.
- Create `Capturely/Tests/CapturelyTests/OnboardingViewTests.swift`
  - Test readiness rules and display values without snapshot testing.
- Optional modify `Capturely/Tests/CapturelyTests/SmokeTests.swift`
  - Only if compile coverage for the new initializer needs an existing smoke test update.

Do not create a second design system. Reuse `CyberTheme`, `CyberPanel`, `CyberButtonStyle`, `CutCornerRectangle`, and `CyberScanlines`.

The repository currently has broad uncommitted Capturely work. Stage only the files listed in each task. Do not run `git add .`.

---

### Task 1: Add Onboarding Readiness Model

**Files:**
- Modify: `Capturely/Sources/Capturely/Views/OnboardingView.swift`
- Create: `Capturely/Tests/CapturelyTests/OnboardingViewTests.swift`

- [ ] **Step 1: Write failing readiness tests**

Create `Capturely/Tests/CapturelyTests/OnboardingViewTests.swift` with this content:

```swift
import Foundation
import Testing
@testable import Capturely

@Test func onboardingReadinessRequestsScreenRecordingFirst() {
    let readiness = OnboardingReadiness.evaluate(
        settings: .defaults,
        permissionSummary: PermissionSummary(
            microphoneGranted: false,
            screenCaptureStatus: "Screen Recording permission needed",
            screenCaptureGranted: false
        )
    )

    #expect(readiness.primaryAction == .requestScreenRecording)
    #expect(readiness.primaryTitle == "Request Access")
    #expect(!readiness.canEnterCapturely)
    #expect(readiness.screenRecordingStatus == .required)
}

@Test func onboardingReadinessRequestsMicrophoneOnlyWhenEnabled() {
    var settings = AppSettings.defaults
    settings.recordsMicrophone = true

    let readiness = OnboardingReadiness.evaluate(
        settings: settings,
        permissionSummary: PermissionSummary(
            microphoneGranted: false,
            screenCaptureStatus: "Ready",
            screenCaptureGranted: true
        )
    )

    #expect(readiness.primaryAction == .requestMicrophone)
    #expect(readiness.primaryTitle == "Request Microphone")
    #expect(!readiness.canEnterCapturely)
    #expect(readiness.microphoneStatus == .required)
}

@Test func onboardingReadinessAllowsEntryWhenRequiredPermissionsAreReady() {
    let readiness = OnboardingReadiness.evaluate(
        settings: .defaults,
        permissionSummary: PermissionSummary(
            microphoneGranted: false,
            screenCaptureStatus: "Ready",
            screenCaptureGranted: true
        )
    )

    #expect(readiness.primaryAction == .enterCapturely)
    #expect(readiness.primaryTitle == "Enter Capturely")
    #expect(readiness.canEnterCapturely)
    #expect(readiness.microphoneStatus == .optional)
    #expect(readiness.notificationsStatus == .later)
}

@Test func onboardingReplaySummaryUsesCurrentSettings() {
    let settings = AppSettings(
        selectedPresetID: CapturePreset.balanced.id,
        clipLibraryURL: URL(fileURLWithPath: "/tmp/Capturely-Clips", isDirectory: true),
        saveClipHotkeyDisplayValue: "Shift+Command+C",
        saveClipHotkey: .shiftCommandC,
        captureSourceMode: .selectedDisplay,
        selectedDisplayID: nil,
        replayDurationSeconds: 120,
        recordsSystemAudio: true,
        recordsMicrophone: false,
        microphoneDeviceID: nil,
        systemAudioMix: 1,
        microphoneMix: 1,
        customPreset: .defaults
    )

    #expect(OnboardingReadiness.bufferLabel(settings: settings) == "2m buffer")
    #expect(OnboardingReadiness.hotkeyLabel(settings: settings) == "Shift+Command+C")
    #expect(OnboardingReadiness.saveLocationLabel(settings: settings).contains("Capturely-Clips"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```sh
swift test --filter Onboarding
```

Expected: compile fails because `OnboardingReadiness` is not defined.

- [ ] **Step 3: Add readiness model**

In `Capturely/Sources/Capturely/Views/OnboardingView.swift`, below the imports and before `struct OnboardingView`, add:

```swift
struct OnboardingReadiness: Equatable {
    enum PrimaryAction: Equatable {
        case requestScreenRecording
        case requestMicrophone
        case enterCapturely
    }

    enum ItemStatus: String, Equatable {
        case required = "REQUIRED"
        case ready = "READY"
        case optional = "OPTIONAL"
        case later = "LATER"
        case armed = "ARMED"
    }

    var primaryAction: PrimaryAction
    var screenRecordingStatus: ItemStatus
    var microphoneStatus: ItemStatus
    var notificationsStatus: ItemStatus

    var primaryTitle: String {
        switch primaryAction {
        case .requestScreenRecording:
            return "Request Access"
        case .requestMicrophone:
            return "Request Microphone"
        case .enterCapturely:
            return "Enter Capturely"
        }
    }

    var canEnterCapturely: Bool {
        primaryAction == .enterCapturely
    }

    static func evaluate(settings: AppSettings, permissionSummary: PermissionSummary) -> OnboardingReadiness {
        let screenStatus: ItemStatus = permissionSummary.screenCaptureGranted ? .ready : .required
        let microphoneStatus: ItemStatus
        if settings.recordsMicrophone {
            microphoneStatus = permissionSummary.microphoneGranted ? .ready : .required
        } else {
            microphoneStatus = .optional
        }

        let primaryAction: PrimaryAction
        if !permissionSummary.screenCaptureGranted {
            primaryAction = .requestScreenRecording
        } else if settings.recordsMicrophone && !permissionSummary.microphoneGranted {
            primaryAction = .requestMicrophone
        } else {
            primaryAction = .enterCapturely
        }

        return OnboardingReadiness(
            primaryAction: primaryAction,
            screenRecordingStatus: screenStatus,
            microphoneStatus: microphoneStatus,
            notificationsStatus: .later
        )
    }

    static func bufferLabel(settings: AppSettings) -> String {
        switch settings.replayDurationSeconds {
        case 30:
            return "30s buffer"
        case 60:
            return "60s buffer"
        case 120:
            return "2m buffer"
        case 300:
            return "5m buffer"
        default:
            return "\(settings.replayDurationSeconds)s buffer"
        }
    }

    static func hotkeyLabel(settings: AppSettings) -> String {
        settings.saveClipHotkey.displayValue
    }

    static func saveLocationLabel(settings: AppSettings) -> String {
        settings.clipLibraryURL?.path(percentEncoded: false) ?? "~/Movies/Capturely/Clips"
    }
}
```

- [ ] **Step 4: Run focused tests**

Run:

```sh
swift test --filter Onboarding
```

Expected: all onboarding tests pass.

- [ ] **Step 5: Commit task 1**

Stage only:

```sh
git add Capturely/Sources/Capturely/Views/OnboardingView.swift Capturely/Tests/CapturelyTests/OnboardingViewTests.swift
git commit -m "test: add onboarding readiness rules"
```

If staging shows unrelated files, unstage them with `git restore --staged <path>` and restage only the listed paths.

---

### Task 2: Wire Onboarding Actions From Backend

**Files:**
- Modify: `Capturely/Sources/Capturely/Views/OnboardingView.swift`
- Modify: `Capturely/Sources/Capturely/Views/ContentView.swift`
- Modify: `Capturely/Tests/CapturelyTests/OnboardingViewTests.swift`

- [ ] **Step 1: Add failing action-routing test**

Append this test to `Capturely/Tests/CapturelyTests/OnboardingViewTests.swift`:

```swift
@MainActor
@Test func onboardingPrimaryActionRoutesToInjectedClosures() {
    var requestedScreenRecording = false
    var requestedMicrophone = false
    var completed = false

    let screenBlocked = OnboardingView(
        settings: .defaults,
        permissionSummary: PermissionSummary(
            microphoneGranted: false,
            screenCaptureStatus: "Screen Recording permission needed",
            screenCaptureGranted: false
        ),
        completeOnboarding: { completed = true },
        openSettings: {},
        requestScreenCapturePermission: { requestedScreenRecording = true },
        requestMicrophonePermission: { requestedMicrophone = true }
    )
    screenBlocked.performPrimaryAction()

    #expect(requestedScreenRecording)
    #expect(!requestedMicrophone)
    #expect(!completed)

    requestedScreenRecording = false
    let ready = OnboardingView(
        settings: .defaults,
        permissionSummary: PermissionSummary(
            microphoneGranted: false,
            screenCaptureStatus: "Ready",
            screenCaptureGranted: true
        ),
        completeOnboarding: { completed = true },
        openSettings: {},
        requestScreenCapturePermission: { requestedScreenRecording = true },
        requestMicrophonePermission: { requestedMicrophone = true }
    )
    ready.performPrimaryAction()

    #expect(!requestedScreenRecording)
    #expect(!requestedMicrophone)
    #expect(completed)
}
```

- [ ] **Step 2: Run focused tests to verify failure**

Run:

```sh
swift test --filter Onboarding
```

Expected: compile fails because `requestScreenCapturePermission`, `requestMicrophonePermission`, and `performPrimaryAction()` are missing on `OnboardingView`.

- [ ] **Step 3: Add action closures and primary routing**

In `Capturely/Sources/Capturely/Views/OnboardingView.swift`, extend `OnboardingView` stored properties from:

```swift
var completeOnboarding: () -> Void = {}
var openSettings: () -> Void = {}
```

to:

```swift
var completeOnboarding: () -> Void = {}
var openSettings: () -> Void = {}
var requestScreenCapturePermission: () -> Void = {}
var requestMicrophonePermission: () -> Void = {}
var setReplayDuration: (Int) -> Void = { _ in }
var setSaveClipHotkey: (SaveClipHotkey) -> Void = { _ in }
var chooseClipLibrary: () -> Void = {}
var resetClipLibrary: () -> Void = {}
```

Inside `OnboardingView`, add:

```swift
var readiness: OnboardingReadiness {
    OnboardingReadiness.evaluate(settings: settings, permissionSummary: permissionSummary)
}

func performPrimaryAction() {
    switch readiness.primaryAction {
    case .requestScreenRecording:
        requestScreenCapturePermission()
    case .requestMicrophone:
        requestMicrophonePermission()
    case .enterCapturely:
        completeOnboarding()
    }
}
```

- [ ] **Step 4: Wire `ContentView` to backend**

In `Capturely/Sources/Capturely/Views/ContentView.swift`, update the `OnboardingView` initializer call to pass:

```swift
OnboardingView(
    settings: backend.settings,
    permissionSummary: backend.permissionSummary,
    completeOnboarding: {
        backend.completeOnboarding()
        selectedPage = .recording
    },
    openSettings: {
        backend.completeOnboarding()
        selectedPage = .settings
    },
    requestScreenCapturePermission: backend.requestScreenCapturePermission,
    requestMicrophonePermission: {
        backend.setRecordsMicrophone(true)
    },
    setReplayDuration: backend.setReplayDuration,
    setSaveClipHotkey: backend.setSaveClipHotkey,
    chooseClipLibrary: backend.chooseClipLibrary,
    resetClipLibrary: backend.resetClipLibrary
)
```

- [ ] **Step 5: Run focused tests**

Run:

```sh
swift test --filter Onboarding
```

Expected: all onboarding tests pass.

- [ ] **Step 6: Commit task 2**

Stage only:

```sh
git add Capturely/Sources/Capturely/Views/OnboardingView.swift Capturely/Sources/Capturely/Views/ContentView.swift Capturely/Tests/CapturelyTests/OnboardingViewTests.swift
git commit -m "feat: wire onboarding permission actions"
```

---

### Task 3: Build the Cyberpunk Setup Cockpit UI

**Files:**
- Modify: `Capturely/Sources/Capturely/Views/OnboardingView.swift`
- Modify: `Capturely/Tests/CapturelyTests/OnboardingViewTests.swift`

- [ ] **Step 1: Add display coverage test**

Append this test to `Capturely/Tests/CapturelyTests/OnboardingViewTests.swift`:

```swift
@MainActor
@Test func onboardingViewAcceptsReplayControlClosures() {
    var replayDuration: Int?
    var hotkey: SaveClipHotkey?
    var choseLibrary = false
    var resetLibrary = false

    let view = OnboardingView(
        settings: .defaults,
        permissionSummary: PermissionSummary(
            microphoneGranted: false,
            screenCaptureStatus: "Ready",
            screenCaptureGranted: true
        ),
        completeOnboarding: {},
        openSettings: {},
        requestScreenCapturePermission: {},
        requestMicrophonePermission: {},
        setReplayDuration: { replayDuration = $0 },
        setSaveClipHotkey: { hotkey = $0 },
        chooseClipLibrary: { choseLibrary = true },
        resetClipLibrary: { resetLibrary = true }
    )

    view.setReplayDuration(120)
    view.setSaveClipHotkey(.shiftCommandC)
    view.chooseClipLibrary()
    view.resetClipLibrary()

    #expect(replayDuration == 120)
    #expect(hotkey == .shiftCommandC)
    #expect(choseLibrary)
    #expect(resetLibrary)
}
```

- [ ] **Step 2: Run focused tests**

Run:

```sh
swift test --filter Onboarding
```

Expected: pass after Task 2 because closures exist. If it fails, fix initializer defaults before changing UI.

- [ ] **Step 3: Replace `OnboardingView.body` with cockpit layout**

In `Capturely/Sources/Capturely/Views/OnboardingView.swift`, replace the existing `body` with this structure:

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 12) {
        OnboardingStatusHeader(readiness: readiness)

        HStack(alignment: .top, spacing: 12) {
            CyberPanel(padding: 12, cut: 10, isHot: !permissionSummary.screenCaptureGranted) {
                VStack(alignment: .leading, spacing: 10) {
                    CyberSectionTitle(title: "Permission System")
                    OnboardingPermissionRow(
                        number: "01",
                        title: "Screen Recording",
                        detail: permissionSummary.screenCaptureStatus,
                        status: readiness.screenRecordingStatus,
                        systemImage: "rectangle.on.rectangle",
                        isHot: !permissionSummary.screenCaptureGranted,
                        actionTitle: permissionSummary.screenCaptureGranted ? nil : "Request",
                        action: requestScreenCapturePermission
                    )
                    OnboardingPermissionRow(
                        number: "02",
                        title: "Microphone",
                        detail: settings.recordsMicrophone ? (permissionSummary.microphoneGranted ? "Mic capture ready" : "Needed for mic track") : "Optional for now",
                        status: readiness.microphoneStatus,
                        systemImage: "mic",
                        isHot: readiness.microphoneStatus == .required,
                        actionTitle: readiness.microphoneStatus == .required ? "Request" : nil,
                        action: requestMicrophonePermission
                    )
                    OnboardingPermissionRow(
                        number: "03",
                        title: "Notifications",
                        detail: "Used for recording and saved-clip alerts",
                        status: readiness.notificationsStatus,
                        systemImage: "bell.badge",
                        isHot: false,
                        actionTitle: nil,
                        action: {}
                    )
                }
            }

            CyberPanel(padding: 12, cut: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    CyberSectionTitle(title: "Replay Defaults")
                    OnboardingReplaySettingRow(
                        number: "04",
                        title: "Buffer",
                        value: OnboardingReadiness.bufferLabel(settings: settings),
                        systemImage: "timer",
                        controls: AnyView(replayDurationControls)
                    )
                    OnboardingReplaySettingRow(
                        number: "05",
                        title: "Hotkey",
                        value: OnboardingReadiness.hotkeyLabel(settings: settings),
                        systemImage: "keyboard",
                        controls: AnyView(hotkeyControls)
                    )
                    OnboardingReplaySettingRow(
                        number: "06",
                        title: "Save Location",
                        value: OnboardingReadiness.saveLocationLabel(settings: settings),
                        systemImage: "folder",
                        controls: AnyView(saveLocationControls)
                    )
                }
            }
        }

        OnboardingCommandRail(
            readiness: readiness,
            primaryAction: performPrimaryAction,
            openSettings: openSettings,
            skipAction: completeOnboarding
        )
    }
    .padding(18)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(onboardingBackground)
}
```

- [ ] **Step 4: Add helper views and control builders**

In the same file, replace `OnboardingStepRow` with the new helper views. Use this code as the implementation target:

```swift
private extension OnboardingView {
    var onboardingBackground: some View {
        CyberTheme.void
            .overlay(
                LinearGradient(
                    colors: [CyberTheme.deepRed.opacity(0.30), CyberTheme.void, CyberTheme.void],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(CyberScanlines().opacity(0.10))
    }

    var replayDurationControls: some View {
        HStack(spacing: 5) {
            ForEach([30, 60, 120, 300], id: \.self) { seconds in
                Button(durationChoiceLabel(seconds)) {
                    setReplayDuration(seconds)
                }
                .buttonStyle(CyberButtonStyle(tone: settings.replayDurationSeconds == seconds ? .primary : .ghost))
            }
        }
    }

    var hotkeyControls: some View {
        HStack(spacing: 5) {
            ForEach(SaveClipHotkey.choices.prefix(3)) { choice in
                Button(choice.compactDisplayValue) {
                    setSaveClipHotkey(choice)
                }
                .buttonStyle(CyberButtonStyle(tone: settings.saveClipHotkey == choice ? .primary : .ghost))
            }
        }
    }

    var saveLocationControls: some View {
        HStack(spacing: 5) {
            Button("Choose", action: chooseClipLibrary)
                .buttonStyle(CyberButtonStyle(tone: .secondary))
            Button("Default", action: resetClipLibrary)
                .buttonStyle(CyberButtonStyle(tone: .ghost))
        }
    }

    func durationChoiceLabel(_ seconds: Int) -> String {
        switch seconds {
        case 30: return "30s"
        case 60: return "60s"
        case 120: return "2m"
        case 300: return "5m"
        default: return "\(seconds)s"
        }
    }
}
```

Then add compact helper structs in `OnboardingView.swift`:

```swift
struct OnboardingStatusHeader: View {
    var readiness: OnboardingReadiness
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CyberPanel(padding: 14, cut: 12, isHot: true) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("CAPTURELY SETUP")
                        .font(.caption.weight(.heavy).monospaced())
                        .tracking(1.8)
                        .foregroundStyle(CyberTheme.red)
                    Text("REPLAY SYSTEM CHECK")
                        .font(.system(size: 24, weight: .black, design: .monospaced))
                        .foregroundStyle(CyberTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                    Text(readiness.canEnterCapturely ? "Replay cockpit armed." : "Arm replay capture before launching a match.")
                        .font(.caption.monospaced())
                        .foregroundStyle(CyberTheme.muted)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(readiness.canEnterCapturely ? "READY" : "ACTION")
                        .font(.caption.weight(.heavy).monospaced())
                        .tracking(1.4)
                        .foregroundStyle(readiness.canEnterCapturely ? CyberTheme.success : CyberTheme.warning)
                    Rectangle()
                        .fill(CyberTheme.red)
                        .frame(width: 92, height: 3)
                        .opacity(reduceMotion ? 0.65 : 1)
                }
            }
        }
    }
}

struct OnboardingPermissionRow: View {
    var number: String
    var title: String
    var detail: String
    var status: OnboardingReadiness.ItemStatus
    var systemImage: String
    var isHot: Bool
    var actionTitle: String?
    var action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.title3.weight(.black).monospaced())
                .foregroundStyle(isHot ? CyberTheme.red : CyberTheme.dim)
                .frame(width: 34, alignment: .leading)
            Image(systemName: systemImage)
                .font(.caption.weight(.heavy))
                .foregroundStyle(isHot ? CyberTheme.red : CyberTheme.muted)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title.uppercased())
                        .font(.caption.weight(.heavy).monospaced())
                        .tracking(0.7)
                    OnboardingStatusChip(status: status)
                }
                Text(detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(CyberTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(CyberButtonStyle(tone: isHot ? .primary : .secondary))
            }
        }
        .padding(9)
        .background(
            CutCornerRectangle(cut: 7)
                .fill(CyberTheme.void.opacity(0.52))
                .overlay(
                    CutCornerRectangle(cut: 7)
                        .stroke((isHot ? CyberTheme.red : CyberTheme.deepRed).opacity(isHot ? 0.74 : 0.42), lineWidth: 1)
                )
        )
    }
}

struct OnboardingReplaySettingRow: View {
    var number: String
    var title: String
    var value: String
    var systemImage: String
    var controls: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Text(number)
                    .font(.title3.weight(.black).monospaced())
                    .foregroundStyle(CyberTheme.dim)
                    .frame(width: 34, alignment: .leading)
                Image(systemName: systemImage)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(CyberTheme.muted)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(.caption.weight(.heavy).monospaced())
                        .tracking(0.7)
                    Text(value)
                        .font(.caption2.monospaced())
                        .foregroundStyle(CyberTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            controls
        }
        .padding(9)
        .background(
            CutCornerRectangle(cut: 7)
                .fill(CyberTheme.void.opacity(0.48))
                .overlay(
                    CutCornerRectangle(cut: 7)
                        .stroke(CyberTheme.deepRed.opacity(0.42), lineWidth: 1)
                )
        )
    }
}

struct OnboardingStatusChip: View {
    var status: OnboardingReadiness.ItemStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption2.weight(.black).monospaced())
            .tracking(0.8)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                CutCornerRectangle(cut: 4)
                    .fill(background)
                    .overlay(CutCornerRectangle(cut: 4).stroke(foreground.opacity(0.70), lineWidth: 1))
            )
    }

    private var foreground: Color {
        switch status {
        case .required:
            return CyberTheme.warning
        case .ready, .armed:
            return CyberTheme.success
        case .optional, .later:
            return CyberTheme.muted
        }
    }

    private var background: Color {
        switch status {
        case .required:
            return CyberTheme.deepRed.opacity(0.52)
        case .ready, .armed:
            return CyberTheme.success.opacity(0.14)
        case .optional, .later:
            return CyberTheme.void.opacity(0.62)
        }
    }
}

struct OnboardingCommandRail: View {
    var readiness: OnboardingReadiness
    var primaryAction: () -> Void
    var openSettings: () -> Void
    var skipAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(readiness.canEnterCapturely ? "ALL REQUIRED SYSTEMS READY" : "SETUP CAN CONTINUE WITH LIMITED CAPTURE")
                .font(.caption2.weight(.heavy).monospaced())
                .tracking(1.0)
                .foregroundStyle(CyberTheme.muted)
            Spacer(minLength: 0)
            Button("Open Settings", action: openSettings)
                .buttonStyle(CyberButtonStyle(tone: .ghost))
            Button("Skip for Now", action: skipAction)
                .buttonStyle(CyberButtonStyle(tone: .secondary))
            Button(readiness.primaryTitle, action: primaryAction)
                .buttonStyle(CyberButtonStyle(tone: .primary))
                .keyboardShortcut(.defaultAction)
        }
    }
}
```

- [ ] **Step 5: Run focused tests and build**

Run:

```sh
swift test --filter Onboarding
swift build
```

Expected: onboarding tests pass and app builds.

- [ ] **Step 6: Commit task 3**

Stage only:

```sh
git add Capturely/Sources/Capturely/Views/OnboardingView.swift Capturely/Tests/CapturelyTests/OnboardingViewTests.swift
git commit -m "feat: build cyberpunk onboarding cockpit"
```

---

### Task 4: Full Validation Through Xcode and Signed Bundle

**Files:**
- Modify only if tests reveal a direct compile or behavior issue:
  - `Capturely/Sources/Capturely/Views/OnboardingView.swift`
  - `Capturely/Sources/Capturely/Views/ContentView.swift`
  - `Capturely/Tests/CapturelyTests/OnboardingViewTests.swift`

- [ ] **Step 1: Run full Swift tests**

Run:

```sh
swift test
```

Expected: all tests pass.

- [ ] **Step 2: Run Xcode workspace tests**

Run:

```sh
xcodebuild -workspace Capturely/.swiftpm/xcode/package.xcworkspace -scheme Capturely -destination 'platform=macOS' test -quiet
```

Expected: tests pass. A warning about multiple matching macOS destinations is acceptable.

- [ ] **Step 3: Verify signed app bundle**

Run:

```sh
cd Capturely
CAPTURELY_CODE_SIGN_IDENTITY="Capturely Local Development" ./script/build_and_run.sh --verify
```

Expected: build succeeds, `Info.plist` lints, codesign verifies, and output includes `Verified dist/Capturely.app`.

- [ ] **Step 4: Commit validation fixes if needed**

If any fix was required, stage only changed onboarding-related files:

```sh
git add Capturely/Sources/Capturely/Views/OnboardingView.swift Capturely/Sources/Capturely/Views/ContentView.swift Capturely/Tests/CapturelyTests/OnboardingViewTests.swift
git commit -m "fix: validate onboarding cockpit"
```

If no fixes were required, do not create an empty commit.

---

## Final Review Checklist

- The onboarding screen is a single-screen cockpit, not a multi-step wizard.
- Screen Recording is clearly required and has the main request path.
- Microphone is optional unless mic capture is enabled.
- Notifications are informational and do not block entry.
- Replay buffer, hotkey, and save location reflect real settings.
- User can enter Capturely without being trapped by macOS permission state.
- The style uses the existing black/red Capturely palette.
- Motion is restrained and can be reduced via `accessibilityReduceMotion`.
- No new theme switching or game-management scope slipped in.
- Xcode validation and signed bundle verification pass.

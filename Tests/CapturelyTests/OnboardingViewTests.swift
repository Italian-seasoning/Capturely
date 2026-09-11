import Foundation
import Testing
@testable import Capturely

@Test func onboardingScanLineDoesNotRequireContinuousRendering() {
    #expect(!OnboardingClipScanLine.usesContinuousAnimation)
}

@MainActor
@Test func onboardingPrimaryActionRoutesToInjectedClosures() {
    var blockedActions: [String] = []
    let blockedView = OnboardingView(
        settings: .defaults,
        permissionSummary: PermissionSummary(
            microphoneGranted: false,
            screenCaptureStatus: "Screen Recording permission needed",
            screenCaptureGranted: false
        ),
        completeOnboarding: { blockedActions.append("complete") },
        requestScreenCapturePermission: { blockedActions.append("screen") },
        requestMicrophonePermission: { blockedActions.append("microphone") }
    )

    blockedView.performPrimaryAction()

    #expect(blockedActions == ["screen"])

    var microphoneSettings = AppSettings.defaults
    microphoneSettings.recordsMicrophone = true
    var microphoneActions: [String] = []
    let microphoneView = OnboardingView(
        settings: microphoneSettings,
        permissionSummary: PermissionSummary(
            microphoneGranted: false,
            screenCaptureStatus: "Ready",
            screenCaptureGranted: true
        ),
        completeOnboarding: { microphoneActions.append("complete") },
        requestScreenCapturePermission: { microphoneActions.append("screen") },
        requestMicrophonePermission: { microphoneActions.append("microphone") }
    )

    microphoneView.performPrimaryAction()

    #expect(microphoneActions == ["microphone"])

    var readyActions: [String] = []
    let readyView = OnboardingView(
        settings: .defaults,
        permissionSummary: PermissionSummary(
            microphoneGranted: false,
            screenCaptureStatus: "Ready",
            screenCaptureGranted: true
        ),
        completeOnboarding: { readyActions.append("complete") },
        requestScreenCapturePermission: { readyActions.append("screen") },
        requestMicrophonePermission: { readyActions.append("microphone") }
    )

    readyView.performPrimaryAction()

    #expect(readyActions == ["complete"])
}

@MainActor
@Test func onboardingViewAcceptsReplayControlClosures() {
    var replayDuration: Int?
    var hotkey: SaveClipHotkey?
    var selectedPresetID: CapturePreset.ID?
    var choseLibrary = false
    var resetLibrary = false
    var requestedNotifications = false

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
        requestNotificationsPermission: { requestedNotifications = true },
        setReplayDuration: { replayDuration = $0 },
        setSaveClipHotkey: { hotkey = $0 },
        setSelectedPreset: { selectedPresetID = $0 },
        chooseClipLibrary: { choseLibrary = true },
        resetClipLibrary: { resetLibrary = true }
    )

    view.setReplayDuration(120)
    view.setSaveClipHotkey(.shiftCommandC)
    view.setSelectedPreset(CapturePreset.storageSaver.id)
    view.chooseClipLibrary()
    view.resetClipLibrary()
    view.requestNotificationsPermission()

    #expect(replayDuration == 120)
    #expect(hotkey == .shiftCommandC)
    #expect(selectedPresetID == CapturePreset.storageSaver.id)
    #expect(choseLibrary)
    #expect(resetLibrary)
    #expect(requestedNotifications)
}

@MainActor
@Test func onboardingPrimaryRailUsesOnlyPageForwardActions() {
    let welcomeView = OnboardingView(initialPage: .welcome)
    let readyView = OnboardingView(initialPage: .ready)
    let replayView = OnboardingView(initialPage: .replay)

    #expect(welcomeView.commandRailPrimaryTitle == "Get Started")
    #expect(readyView.commandRailPrimaryTitle == nil)
    #expect(replayView.commandRailPrimaryTitle == "Continue")
}

@MainActor
@Test func onboardingAccessPrimaryRequestsMissingPermissionBeforeAdvancing() {
    var actions: [String] = []
    let screenBlockedView = OnboardingView(
        settings: .defaults,
        permissionSummary: PermissionSummary(
            microphoneGranted: false,
            screenCaptureStatus: "Screen Recording permission needed",
            screenCaptureGranted: false
        ),
        completeOnboarding: { actions.append("complete") },
        requestScreenCapturePermission: { actions.append("screen") },
        requestMicrophonePermission: { actions.append("microphone") },
        initialPage: .access
    )

    #expect(screenBlockedView.commandRailPrimaryTitle == "Request Access")
    screenBlockedView.performPagePrimaryAction()
    #expect(actions == ["screen"])

    var microphoneSettings = AppSettings.defaults
    microphoneSettings.recordsMicrophone = true
    actions = []
    let microphoneBlockedView = OnboardingView(
        settings: microphoneSettings,
        permissionSummary: PermissionSummary(
            microphoneGranted: false,
            screenCaptureStatus: "Ready",
            screenCaptureGranted: true
        ),
        completeOnboarding: { actions.append("complete") },
        requestScreenCapturePermission: { actions.append("screen") },
        requestMicrophonePermission: { actions.append("microphone") },
        initialPage: .access
    )

    #expect(microphoneBlockedView.commandRailPrimaryTitle == "Request Microphone")
    microphoneBlockedView.performPagePrimaryAction()
    #expect(actions == ["microphone"])
}

@Test func onboardingPagesUseGuidedOrder() {
    #expect(OnboardingPage.allCases == [.welcome, .access, .replay, .ready])
    #expect(OnboardingPage.welcome.number == "01")
    #expect(OnboardingPage.access.title == "Access")
    #expect(OnboardingPage.ready.subtitle == "Replay engine armed.")
}

@Test func onboardingReplayGroupsUseFocusedOrder() {
    #expect(OnboardingReplayGroup.allCases == [.length, .quality, .hotkey, .storage])
    #expect(OnboardingReplayGroup.length.systemImage == "timer")
    #expect(OnboardingReplayGroup.quality.detail.contains("storage"))
    #expect(OnboardingReplayGroup.storage.rawValue == "Storage")
}

@Test func onboardingReadinessRequestsScreenRecordingFirst() {
    var settings = AppSettings.defaults
    settings.recordsMicrophone = true

    let readiness = OnboardingReadiness.evaluate(
        settings: settings,
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
    #expect(readiness.microphoneStatus == .required)
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
    #expect(readiness.notificationsStatus == .optional)
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

@Test func onboardingReadinessStatusRawValuesAreHudLabels() {
    #expect(OnboardingReadiness.ItemStatus.required.rawValue == "REQUIRED")
    #expect(OnboardingReadiness.ItemStatus.ready.rawValue == "READY")
    #expect(OnboardingReadiness.ItemStatus.optional.rawValue == "OPTIONAL")
    #expect(OnboardingReadiness.ItemStatus.later.rawValue == "LATER")
    #expect(OnboardingReadiness.ItemStatus.armed.rawValue == "ARMED")
}

import Foundation
import Testing
@testable import Capturely

@Test func captureRuntimeWaitsUntilOnboardingCompletes() {
    #expect(!CaptureBackend.shouldActivateCaptureRuntime(hasCompletedOnboarding: false))
    #expect(CaptureBackend.shouldActivateCaptureRuntime(hasCompletedOnboarding: true))
}

@Test func manualCaptureRequiresCompletedOnboarding() {
    #expect(!CaptureBackend.shouldStartManualCapture(hasCompletedOnboarding: false))
    #expect(CaptureBackend.shouldStartManualCapture(hasCompletedOnboarding: true))
}

@Test func everySaveHonorsConfiguredReplayDuration() {
    let firstSaveDuration = CaptureBackend.replayDurationSecondsForSave(
        capturedAt: Date(timeIntervalSince1970: 100),
        preset: .balanced,
        lastSuccessfulSaveCapturedAt: nil
    )
    let quickFollowUpDuration = CaptureBackend.replayDurationSecondsForSave(
        capturedAt: Date(timeIntervalSince1970: 118),
        preset: .balanced,
        lastSuccessfulSaveCapturedAt: Date(timeIntervalSince1970: 100)
    )
    let lateFollowUpDuration = CaptureBackend.replayDurationSecondsForSave(
        capturedAt: Date(timeIntervalSince1970: 145),
        preset: .balanced,
        lastSuccessfulSaveCapturedAt: Date(timeIntervalSince1970: 100)
    )

    #expect(firstSaveDuration == TimeInterval(CapturePreset.balanced.replayDurationSeconds))
    #expect(quickFollowUpDuration == 60)
    #expect(lateFollowUpDuration == 60)
}

@Test func replayRetentionTracksConfiguredClipLengthWithSegmentPadding() {
    #expect(CaptureBackend.replayRetentionSeconds(forReplayDuration: 30) == 50)
    #expect(CaptureBackend.replayRetentionSeconds(forReplayDuration: 60) == 80)
    #expect(CaptureBackend.replayRetentionSeconds(forReplayDuration: 300) == 320)
}

@Test func performanceFallbackRequiresSustainedBackpressure() {
    #expect(!CaptureBackend.shouldActivatePerformanceFallback(performance: CapturePerformanceSnapshot(
        startedAt: Date(),
        videoSamplesReceived: 2_000,
        videoSamplesAppended: 1_990,
        videoInputBackpressureDrops: 10
    )))
    #expect(!CaptureBackend.shouldActivatePerformanceFallback(performance: CapturePerformanceSnapshot(
        startedAt: Date(),
        videoSamplesReceived: 2_000,
        videoSamplesAppended: 1_950,
        videoInputBackpressureDrops: 40
    )))
    #expect(CaptureBackend.shouldActivatePerformanceFallback(performance: CapturePerformanceSnapshot(
        startedAt: Date(),
        videoSamplesReceived: 1_000,
        videoSamplesAppended: 940,
        videoInputBackpressureDrops: 35
    )))
}

@Test func resolvedPresetUsesSelectedQualityAndCaptureSettings() {
    let settings = AppSettings(
        selectedPresetID: CapturePreset.editing.id,
        clipLibraryURL: nil,
        saveClipHotkeyDisplayValue: "Option+Command+C",
        captureSourceMode: .selectedDisplay,
        selectedDisplayID: nil,
        replayDurationSeconds: 120,
        recordsSystemAudio: false,
        recordsMicrophone: true,
        microphoneDeviceID: "mic-1"
    )

    let preset = CaptureBackend.resolvedPreset(for: nil, settings: settings)

    #expect(preset.id == CapturePreset.editing.id)
    #expect(preset.maximumHeight == 1440)
    #expect(preset.maximumFramesPerSecond == 60)
    #expect(preset.videoBitrate == 28_000_000)
    #expect(preset.replayDurationSeconds == 120)
    #expect(!preset.recordsSystemAudio)
    #expect(preset.recordsMicrophone)
}

@Test func selectedQualityOverridesLegacyGamePreset() {
    let settings = AppSettings(
        selectedPresetID: CapturePreset.editing.id,
        clipLibraryURL: nil,
        saveClipHotkeyDisplayValue: "Option+Command+C",
        captureSourceMode: .selectedDisplay,
        selectedDisplayID: nil,
        replayDurationSeconds: 30,
        recordsSystemAudio: true,
        recordsMicrophone: false,
        microphoneDeviceID: nil
    )
    let game = Game(displayName: "Low Power Game", presetID: CapturePreset.storageSaver.id)

    let preset = CaptureBackend.resolvedPreset(for: game, settings: settings)

    #expect(preset.id == CapturePreset.editing.id)
    #expect(preset.maximumHeight == 1440)
    #expect(preset.maximumFramesPerSecond == 60)
    #expect(preset.videoBitrate == 28_000_000)
    #expect(preset.replayDurationSeconds == 30)
    #expect(preset.recordsSystemAudio)
    #expect(!preset.recordsMicrophone)
}

@Test func resolvedPresetUsesEditableCustomQualitySettings() {
    let settings = AppSettings(
        selectedPresetID: CapturePreset.custom.id,
        clipLibraryURL: nil,
        saveClipHotkeyDisplayValue: "Option+Command+C",
        captureSourceMode: .selectedDisplay,
        selectedDisplayID: nil,
        replayDurationSeconds: 60,
        recordsSystemAudio: true,
        recordsMicrophone: false,
        microphoneDeviceID: nil,
        customPreset: CustomCapturePresetSettings(maximumHeight: 1440, maximumFramesPerSecond: 120, videoBitrateMbps: 36)
    )

    let preset = CaptureBackend.resolvedPreset(for: nil, settings: settings)

    #expect(preset.id == CapturePreset.custom.id)
    #expect(preset.maximumHeight == 1440)
    #expect(preset.maximumFramesPerSecond == 60)
    #expect(preset.videoBitrate == 36_000_000)
}

import Foundation
import Testing
@testable import Capturely

@Test func recordingStateShowsPermissionBeforeWaitingForGame() {
    let state = RecordingState.derive(
        captureState: .idle,
        permissionSummary: PermissionSummary(
            microphoneGranted: false,
            screenCaptureStatus: "Permission needed",
            screenCaptureGranted: false
        ),
        preset: .balanced,
        bufferDurationSeconds: 0,
        lastSaveResult: nil
    )

    #expect(state == .permissionsNeeded("Screen Recording permission needed"))
    #expect(state.displayTitle == "Screen Recording permission required")
}

@Test func recordingStateAllowsWaitingWhenScreenCaptureIsReady() {
    let state = RecordingState.derive(
        captureState: .idle,
        permissionSummary: PermissionSummary(
            microphoneGranted: false,
            screenCaptureStatus: "Ready",
            screenCaptureGranted: true
        ),
        preset: .balanced,
        bufferDurationSeconds: 0,
        lastSaveResult: nil
    )

    #expect(state == .waitingForGame)
}

@Test func recordingStateWarmsUntilBufferHasVideo() {
    let game = Game(displayName: "Roblox", bundleIdentifier: "com.roblox.Roblox")

    let warming = RecordingState.derive(
        captureState: .recording(game: game, preset: .balanced),
        permissionSummary: PermissionSummary(microphoneGranted: true, screenCaptureStatus: "Ready"),
        preset: .balanced,
        bufferDurationSeconds: 12,
        lastSaveResult: nil
    )

    let ready = RecordingState.derive(
        captureState: .recording(game: game, preset: .balanced),
        permissionSummary: PermissionSummary(microphoneGranted: true, screenCaptureStatus: "Ready"),
        preset: .balanced,
        bufferDurationSeconds: 60,
        lastSaveResult: nil
    )
    let empty = RecordingState.derive(
        captureState: .recording(game: game, preset: .balanced),
        permissionSummary: PermissionSummary(microphoneGranted: true, screenCaptureStatus: "Ready"),
        preset: .balanced,
        bufferDurationSeconds: 0,
        lastSaveResult: nil
    )

    #expect(empty == .bufferWarming(secondsBuffered: 0, targetSeconds: 60))
    #expect(warming == .bufferWarming(secondsBuffered: 12, targetSeconds: 60))
    #expect(warming.displayTitle == "Buffer warming up")
    #expect(warming.detail == "12 seconds ready")
    #expect(ready == .readyToSave(secondsBuffered: 60))
    #expect(ready.displayTitle == "Ready to save")
}

@Test func recordingStateUsesRobloxWaitingMessage() {
    #expect(RecordingState.waitingForGame.displayTitle == "Waiting for Roblox")
}

@Test func captureStateLocksConfigurationOnlyWhileActive() {
    let game = Game(displayName: "Roblox")

    #expect(!CaptureState.idle.locksCaptureConfiguration)
    #expect(!CaptureState.waitingForWindow(game: game).locksCaptureConfiguration)
    #expect(!CaptureState.permissionRequired(reason: "Screen Recording permission needed").locksCaptureConfiguration)
    #expect(!CaptureState.failed(message: "Capture failed").locksCaptureConfiguration)
    #expect(CaptureState.recording(game: game, preset: .balanced).locksCaptureConfiguration)
    #expect(CaptureState.savingClip(game: game).locksCaptureConfiguration)
}

@Test func failedRecordingStatePointsToDiagnostics() {
    let state = RecordingState.failed("Capture writer failed")

    #expect(state.displayTitle == "Capture failed, open diagnostics")
    #expect(state.detail == "Capture writer failed")
}

@Test func captureHealthDetectsStalledVideoSamples() {
    let now = Date(timeIntervalSince1970: 100)
    let health = CaptureHealthSnapshot(
        detectedAppName: "ROBLOX",
        captureState: .recording,
        activeSegmentCount: 2,
        currentBufferDurationSeconds: 30,
        lastVideoSampleAt: Date(timeIntervalSince1970: 80),
        lastAudioSampleAt: nil,
        audioStatus: .none,
        outputFolder: URL(fileURLWithPath: "/tmp/Capturely"),
        lastSaveResult: nil,
        lastError: nil
    )

    #expect(health.isVideoStalled(now: now, threshold: 10))
}

@Test func captureHealthBuildsAudioMonitorDescription() {
    let health = CaptureHealthSnapshot(
        detectedAppName: "ROBLOX",
        captureState: .recording,
        activeSegmentCount: 2,
        currentBufferDurationSeconds: 8,
        lastVideoSampleAt: Date(timeIntervalSince1970: 95),
        lastAudioSampleAt: Date(timeIntervalSince1970: 99),
        audioStatus: .gameOnly,
        audioLevel: 0.42,
        audioQualityScore: 0.86,
        recentAudioLevels: [0.2, 0.4, 0.6],
        audioSampleRate: 48_000,
        audioChannelCount: 2,
        outputFolder: nil,
        lastSaveResult: nil,
        lastError: nil
    )

    #expect(health.hasLiveAudioSamples)
    #expect(health.audioMonitorDescription == "Game only · 86%")
}

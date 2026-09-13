import Foundation
import Testing
@testable import Capturely

@MainActor
@Test func recordingTimerClearsWhenCaptureStops() {
    var health = CaptureHealthSnapshot.empty
    health.currentBufferDurationSeconds = 85
    var view = RecordingView(
        status: RecordingDisplayStatus(captureState: .idle),
        health: health,
        recentClips: []
    )
    #expect(view.displayedBufferSeconds == 0)
    view.status.captureState = .recording(game: Game(displayName: "Roblox"), preset: .balanced)
    #expect(view.displayedBufferSeconds == 60)
    view.health.currentBufferDurationSeconds = 12.7
    #expect(view.displayedBufferSeconds == 12)
}

@Test func capturelySmokeTest() {
    #expect("Capturely".count == 9)
}

@Test func sidebarPagesExcludeOneTimeOnboarding() {
    #expect(CapturelyPage.allCases == [.recording, .library, .settings])
}

@Test func recordingDisplayStatusNormalizesRobloxAndBuildsSubtitle() {
    let game = Game(displayName: "Roblox", bundleIdentifier: "com.roblox.Roblox")
    let status = RecordingDisplayStatus(
        captureState: .recording(game: game, preset: .balanced),
        windowTitle: "Rivals",
        isWindowLocked: true,
        bufferDurationSeconds: 18,
        storageFreeDescription: "412 GB free"
    )

    #expect(status.primaryLine == "REC · ROBLOX")
    #expect(status.subtitle == "Rivals · 18s ready")
    #expect(status.detectedGameLabel == "ROBLOX")
    #expect(status.storageFreeDescription == "412 GB free")
    #expect(status.canSaveClip)
}

@Test func recordingDisplayStatusKeepsSaveDisabledUntilBufferExists() {
    let status = RecordingDisplayStatus(
        captureState: .recording(game: Game(displayName: "Screen Capture"), preset: .balanced),
        windowTitle: "Display 1",
        isWindowLocked: true,
        bufferDurationSeconds: 0
    )

    #expect(status.title == "Buffer warming up")
    #expect(status.subtitle == "Display 1 · 0s ready")
    #expect(status.canSaveClip == false)
    #expect(status.bufferFillFraction == 0.04)
}

@Test func recordingDisplayStatusCompactsRobloxHelperSubtitle() {
    let status = RecordingDisplayStatus(
        captureState: .idle,
        windowTitle: "Roblox Update Helper Helper",
        isWindowLocked: false,
        bufferDurationSeconds: 0
    )

    #expect(status.subtitle == "Roblox")
}

@Test func recordingDisplayStatusWaitsForMinimumSaveableSegment() {
    let status = RecordingDisplayStatus(
        captureState: .recording(game: Game(displayName: "Screen Capture"), preset: .balanced),
        windowTitle: "Display 1",
        isWindowLocked: true,
        bufferDurationSeconds: 1
    )

    #expect(status.title == "Buffer warming up")
    #expect(status.canSaveClip == false)
}

@MainActor
@Test func recordingViewAcceptsRobloxStatusSnapshot() {
    let game = Game(displayName: "Roblox", bundleIdentifier: "com.roblox.Roblox")
    let status = RecordingDisplayStatus(
        captureState: .recording(game: game, preset: .balanced),
        windowTitle: "Rivals",
        isWindowLocked: true
    )
    let view = RecordingView(status: status, recentClips: [])

    #expect(view.status.primaryLine == "REC · ROBLOX")
}

@MainActor
@Test func recordingViewAcceptsManualCaptureControls() {
    var didStart = false
    var didStop = false
    let view = RecordingView(
        recentClips: [],
        startCapture: { didStart = true },
        stopCapture: { didStop = true }
    )

    view.startCapture()
    view.stopCapture()

    #expect(didStart)
    #expect(didStop)
}

@MainActor
@Test func recordingViewRecentClipOpenHandlerCanOpenCardClip() {
    let clipURL = URL(fileURLWithPath: "/tmp/Capturely-Test-Clip.mov")
    let clip = RecentClipDisplay(
        gameName: "ROBLOX",
        experienceName: "Screen Capture",
        time: "12:00:00",
        duration: "12s",
        preset: "Balanced",
        accent: .red,
        thumbnailURL: nil,
        clipURL: clipURL
    )
    var openedClip: RecentClipDisplay?
    let view = RecordingView(
        recentClips: [clip],
        openClip: { openedClip = $0 }
    )

    view.openClip(clip)

    #expect(openedClip == clip)
}

@Test func savedRecentClipUsesRobloxRivalsMetadata() {
    let game = Game(displayName: "Roblox", bundleIdentifier: "com.roblox.Roblox")
    let status = RecordingDisplayStatus(
        captureState: .recording(game: game, preset: .balanced),
        windowTitle: "Rivals",
        isWindowLocked: true
    )

    let clip = RecentClipDisplay.savedNow(status: status)

    #expect(clip.gameName == "ROBLOX")
    #expect(clip.experienceName == "Rivals")
    #expect(clip.duration == "60s")
}

@Test func consoleWindowFitsRecordingDashboard() {
    #expect(CapturelyWindowMetrics.minimumContentWidth == 820)
    #expect(CapturelyWindowMetrics.minimumContentHeight == 560)
    #expect(CapturelyWindowMetrics.idealContentWidth > CapturelyWindowMetrics.minimumContentWidth)
    #expect(CapturelyWindowMetrics.idealContentHeight > CapturelyWindowMetrics.minimumContentHeight)
    #expect(CapturelyWindowMetrics.sidebarIdealWidth == 64)
}

@Test func scanlineRendererUsesOneRowEveryFivePoints() {
    #expect(CyberScanlines.rowCount(for: 0) == 1)
    #expect(CyberScanlines.rowCount(for: 25) == 5)
}

@Test func compactQuickSettingTilesDoNotRepeatSidebarOrHeroStatus() {
    #expect(QuickSettingDisplay.compactDefaults.map(\.label) == ["Quality", "Video", "Audio", "Hotkey"])
    #expect(!QuickSettingDisplay.compactDefaults.map(\.label).contains("Storage"))
    #expect(!QuickSettingDisplay.compactDefaults.map(\.label).contains("Detected Game"))
}

@Test func compactQuickSettingTilesUseAudioHealth() {
    let health = CaptureHealthSnapshot(
        detectedAppName: "ROBLOX",
        captureState: .recording,
        activeSegmentCount: 1,
        currentBufferDurationSeconds: 4,
        lastVideoSampleAt: Date(timeIntervalSince1970: 10),
        lastAudioSampleAt: Date(timeIntervalSince1970: 10),
        audioStatus: .gameOnly,
        audioLevel: 0.5,
        audioQualityScore: 0.79,
        recentAudioLevels: [0.2, 0.5],
        audioSampleRate: 48_000,
        audioChannelCount: 2,
        outputFolder: nil,
        lastSaveResult: nil,
        lastError: nil
    )
    let status = RecordingDisplayStatus(captureState: .recording(game: Game(displayName: "Roblox"), preset: .balanced))
    let settings = AppSettings(
        selectedPresetID: CapturePreset.editing.id,
        clipLibraryURL: nil,
        saveClipHotkeyDisplayValue: "Option+Command+C",
        captureSourceMode: .selectedDisplay,
        selectedDisplayID: nil,
        replayDurationSeconds: 60,
        recordsSystemAudio: true,
        recordsMicrophone: false,
        microphoneDeviceID: nil
    )
    let tiles = QuickSettingDisplay.compact(status: status, health: health, settings: settings)
    let quality = tiles.first { $0.label == "Quality" }
    let audio = tiles.first { $0.label == "Audio" }

    #expect(quality?.value == "Studio")
    #expect(quality?.meterFraction == CapturePreset.editing.qualityScore)
    #expect(audio?.value == "Game only · 79%")
    #expect(audio?.meterFraction == 0.79)
    #expect(audio?.meterStyle == .qualityRamp)
    #expect(audio?.audioLevels == [0.2, 0.5])
}

@Test func compactQuickSettingTilesShowPerformanceModeForStorageSaver() {
    let settings = AppSettings(
        selectedPresetID: CapturePreset.storageSaver.id,
        clipLibraryURL: nil,
        saveClipHotkeyDisplayValue: "Option+Command+C",
        captureSourceMode: .selectedDisplay,
        selectedDisplayID: nil,
        replayDurationSeconds: 60,
        recordsSystemAudio: true,
        recordsMicrophone: false,
        microphoneDeviceID: nil
    )
    let tiles = QuickSettingDisplay.compact(
        status: RecordingDisplayStatus(captureState: .recording(game: Game(displayName: "Roblox"), preset: .storageSaver)),
        health: .empty,
        settings: settings
    )

    #expect(tiles.first { $0.label == "Quality" }?.value == "Performance Mode")
}

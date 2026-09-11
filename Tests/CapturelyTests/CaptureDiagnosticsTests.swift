import Foundation
import Testing
@testable import Capturely

@Test func diagnosticsReportIncludesRuntimeStatusAndEvents() {
    let report = CaptureDiagnosticsReport(
        generatedAt: Date(timeIntervalSince1970: 1_780_697_648),
        detectedAppName: "ROBLOX",
        recordingState: .readyToSave(secondsBuffered: 58.4),
        permissionSummary: PermissionSummary(microphoneGranted: false, screenCaptureStatus: "Ready"),
        health: CaptureHealthSnapshot(
            detectedAppName: "ROBLOX",
            captureState: .recording,
            activeSegmentCount: 6,
            currentBufferDurationSeconds: 58.4,
            lastVideoSampleAt: Date(timeIntervalSince1970: 1_780_697_640),
            lastAudioSampleAt: nil,
            audioStatus: .gameOnly,
            audioLevel: 0.4,
            audioQualityScore: 0.82,
            recentAudioLevels: [0.2, 0.4],
            audioSampleRate: 48_000,
            audioChannelCount: 2,
            performance: CapturePerformanceSnapshot(
                startedAt: Date(timeIntervalSince1970: 1_780_697_620),
                videoSamplesReceived: 120,
                videoSamplesAppended: 118,
                audioSamplesReceived: 80,
                audioSamplesAppended: 80,
                incompleteVideoFramesDropped: 1,
                videoInputBackpressureDrops: 1,
                segmentFlushCount: 3,
                averageVideoAppendMilliseconds: 0.42,
                averageAudioAppendMilliseconds: 0.18,
                lastSegmentFlushMilliseconds: 11.4
            ),
            outputFolder: URL(fileURLWithPath: "/Users/nolan/Movies/Capturely"),
            lastSaveResult: nil,
            lastError: nil
        ),
        recentEvents: [
            CaptureDiagnosticEvent(kind: .captureStarted, message: "Capture started", date: Date(timeIntervalSince1970: 1_780_697_630)),
            CaptureDiagnosticEvent(kind: .bufferReady, message: "Buffer ready", date: Date(timeIntervalSince1970: 1_780_697_640))
        ]
    )

    let text = report.renderText()

    #expect(text.contains("Detected app/game: ROBLOX"))
    #expect(text.contains("Recording state: Ready to save"))
    #expect(text.contains("Screen Recording: Ready"))
    #expect(text.contains("Active segments: 6"))
    #expect(text.contains("Buffer duration: 58.4s"))
    #expect(text.contains("Audio status: Game only"))
    #expect(text.contains("Audio monitor: level 40%, quality 82%, 48000 Hz, 2 channel(s)"))
    #expect(text.contains("Performance"))
    #expect(text.contains("Video samples: 120 received, 118 appended"))
    #expect(text.contains("Audio samples: 80 received, 80 appended"))
    #expect(text.contains("Dropped video frames: 1 incomplete, 1 backpressure"))
    #expect(text.contains("Writer sampled append average: video 0.42ms, audio 0.18ms"))
    #expect(text.contains("Segment flushes: 3, last flush 11.40ms"))
    #expect(text.contains("Recent state transitions"))
    #expect(text.contains("captureStarted"))
    #expect(text.contains("Recent restart attempts"))
}

@Test func diagnosticsReportDoesNotIncludeClipFileContents() {
    let report = CaptureDiagnosticsReport(
        generatedAt: Date(timeIntervalSince1970: 0),
        detectedAppName: nil,
        recordingState: .waitingForGame,
        permissionSummary: PermissionSummary(microphoneGranted: false, screenCaptureStatus: "Not checked"),
        health: .empty,
        recentEvents: [
            CaptureDiagnosticEvent(kind: .saveFailed, message: "Save failed for /tmp/clip.mov", date: Date(timeIntervalSince1970: 0))
        ]
    )

    let text = report.renderText()

    #expect(text.contains("/tmp/clip.mov"))
    #expect(!text.contains("SECRET_FRAME_BYTES"))
    #expect(!text.contains("ROBLOX_SCREENSHOT_PIXELS"))
}

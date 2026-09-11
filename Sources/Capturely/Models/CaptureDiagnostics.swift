import Foundation

enum CaptureDiagnosticEventKind: String, Codable, Equatable, Sendable {
    case appDetected
    case captureStarting
    case captureStarted
    case firstVideoSampleReceived
    case firstAudioSampleReceived
    case bufferReady
    case saveRequested
    case activeSegmentFlushed
    case compositionStarted
    case compositionFinished
    case outputValidated
    case metadataWritten
    case thumbnailGenerated
    case clipIndexed
    case saveFailed
    case editableAudioFailed
    case captureStalledRestarting
    case captureStopped
}

struct CaptureDiagnosticEvent: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var kind: CaptureDiagnosticEventKind
    var message: String
    var date: Date

    init(kind: CaptureDiagnosticEventKind, message: String, date: Date = Date()) {
        self.kind = kind
        self.message = message
        self.date = date
    }
}

struct CaptureDiagnosticsReport: Equatable, Sendable {
    var generatedAt: Date
    var detectedAppName: String?
    var recordingState: RecordingState
    var permissionSummary: PermissionSummary
    var health: CaptureHealthSnapshot
    var recentEvents: [CaptureDiagnosticEvent]

    func renderText() -> String {
        let restarts = recentEvents.filter { $0.kind == .captureStalledRestarting }

        return """
        Capturely Capture Diagnostics
        Generated: \(Self.timestamp(generatedAt))

        Runtime
        - Detected app/game: \(detectedAppName ?? "None")
        - Recording state: \(recordingState.displayTitle)
        - Recording detail: \(recordingState.detail)
        - Capture state: \(health.captureState.rawValue)
        - Screen Recording: \(permissionSummary.screenCaptureStatus)
        - Microphone: \(permissionSummary.microphoneGranted ? "Granted" : "Not granted")
        - Active segments: \(health.activeSegmentCount)
        - Buffer duration: \(String(format: "%.1fs", health.currentBufferDurationSeconds))
        - Last video sample: \(Self.timestampOrNone(health.lastVideoSampleAt))
        - Last audio sample: \(Self.timestampOrNone(health.lastAudioSampleAt))
        - Audio status: \(health.audioStatus.rawValue)
        - Audio monitor: level \(Self.percent(health.audioLevel)), quality \(Self.percent(health.audioQualityScore)), \(Self.audioFormat(health))
        - Output folder: \(health.outputFolder?.path(percentEncoded: false) ?? "Unset")
        - Last save result/error: \(Self.saveResult(health.lastSaveResult, fallbackError: health.lastError))

        Performance
        - Video samples: \(health.performance.videoSamplesReceived) received, \(health.performance.videoSamplesAppended) appended, \(Self.rate(health.performance.videoSamplesPerSecond)) received/sec
        - Audio samples: \(health.performance.audioSamplesReceived) received, \(health.performance.audioSamplesAppended) appended, \(Self.rate(health.performance.audioSamplesPerSecond)) received/sec
        - Dropped video frames: \(health.performance.incompleteVideoFramesDropped) incomplete, \(health.performance.videoInputBackpressureDrops) backpressure
        - Writer sampled append average: video \(Self.milliseconds(health.performance.averageVideoAppendMilliseconds)), audio \(Self.milliseconds(health.performance.averageAudioAppendMilliseconds))
        - Segment flushes: \(health.performance.segmentFlushCount), last flush \(Self.milliseconds(health.performance.lastSegmentFlushMilliseconds))

        Recent state transitions
        \(Self.eventLines(recentEvents))

        Recent restart attempts
        \(Self.eventLines(restarts))

        Privacy note: diagnostics include status, timestamps, and paths only. They do not include screen contents, clip contents, or file contents.
        """
    }

    private static func eventLines(_ events: [CaptureDiagnosticEvent]) -> String {
        guard !events.isEmpty else { return "- None" }
        return events
            .map { "- \(timestamp($0.date)) [\($0.kind.rawValue)] \($0.message)" }
            .joined(separator: "\n")
    }

    private static func timestampOrNone(_ date: Date?) -> String {
        guard let date else { return "None" }
        return timestamp(date)
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func saveResult(_ result: SaveResult?, fallbackError: String?) -> String {
        switch result {
        case .saved(let clip):
            return "Saved \(clip.clipURL.path(percentEncoded: false))"
        case .failed(let message):
            return "Failed: \(message)"
        case nil:
            return fallbackError.map { "Error: \($0)" } ?? "None"
        }
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }

    private static func rate(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func milliseconds(_ value: Double) -> String {
        String(format: "%.2fms", max(value, 0))
    }

    private static func audioFormat(_ health: CaptureHealthSnapshot) -> String {
        let sampleRate = health.audioSampleRate.map { "\(Int($0.rounded())) Hz" } ?? "unknown sample rate"
        let channels = health.audioChannelCount > 0 ? "\(health.audioChannelCount) channel(s)" : "unknown channels"
        return "\(sampleRate), \(channels)"
    }
}

import Foundation

enum RecordingState: Equatable, Sendable {
    case permissionsNeeded(String)
    case waitingForGame
    case startingCapture(Game)
    case recording(Game)
    case bufferWarming(secondsBuffered: TimeInterval, targetSeconds: Int)
    case readyToSave(secondsBuffered: TimeInterval)
    case saving(Game)
    case saved(Clip)
    case warning(String)
    case failed(String)
    case stopped

    var displayTitle: String {
        switch self {
        case .permissionsNeeded:
            return "Screen Recording permission required"
        case .waitingForGame:
            return "Waiting for Roblox"
        case .startingCapture:
            return "Starting capture"
        case .recording:
            return "Recording"
        case .bufferWarming:
            return "Buffer warming up"
        case .readyToSave:
            return "Ready to save"
        case .saving:
            return "Saving replay"
        case .saved:
            return "Saved replay"
        case .warning:
            return "Warning"
        case .failed:
            return "Capture failed, open diagnostics"
        case .stopped:
            return "Stopped"
        }
    }

    var detail: String {
        switch self {
        case .permissionsNeeded(let message), .warning(let message), .failed(let message):
            return message
        case .waitingForGame:
            return "Open Roblox."
        case .startingCapture(let game), .recording(let game):
            return RecordingDisplayStatus.appLabel(for: game)
        case .bufferWarming(let secondsBuffered, _):
            return "\(Int(secondsBuffered.rounded())) seconds ready"
        case .readyToSave(let secondsBuffered):
            return "\(Int(secondsBuffered.rounded()))s buffered"
        case .saving(let game):
            return game.displayName
        case .saved(let clip):
            return clip.gameName
        case .stopped:
            return "Capture is stopped."
        }
    }

    static func derive(
        captureState: CaptureState,
        permissionSummary: PermissionSummary,
        preset: CapturePreset,
        bufferDurationSeconds: TimeInterval,
        lastSaveResult: SaveResult?
    ) -> RecordingState {
        if permissionSummary.needsScreenCapturePermission {
            return .permissionsNeeded("Screen Recording permission needed")
        }

        if preset.recordsMicrophone && !permissionSummary.microphoneGranted {
            return .permissionsNeeded("Microphone permission needed")
        }

        if let lastSaveResult {
            switch lastSaveResult {
            case .saved(let clip):
                return .saved(clip)
            case .failed(let message):
                return .failed(message)
            }
        }

        switch captureState {
        case .idle:
            return .waitingForGame
        case .waitingForWindow(let game):
            return .startingCapture(game)
        case .permissionRequired(let reason):
            return .permissionsNeeded(reason)
        case .recording(_, let preset):
            if bufferDurationSeconds <= 0 {
                return .bufferWarming(secondsBuffered: 0, targetSeconds: preset.replayDurationSeconds)
            }
            if bufferDurationSeconds < TimeInterval(preset.replayDurationSeconds) {
                return .bufferWarming(secondsBuffered: bufferDurationSeconds, targetSeconds: preset.replayDurationSeconds)
            }
            return .readyToSave(secondsBuffered: bufferDurationSeconds)
        case .savingClip(let game):
            return .saving(game)
        case .failed(let message):
            return .failed(message)
        }
    }
}

enum CaptureRuntimeState: String, Codable, Equatable, Sendable {
    case idle
    case waitingForWindow
    case recording
    case saving
    case failed
}

enum AudioTrackStatus: String, Codable, Equatable, Sendable {
    case gameAndMic = "Game + Mic"
    case gameOnly = "Game only"
    case micOnly = "Mic only"
    case none = "None"
    case expectedButMissing = "Expected but missing"
}

enum SaveResult: Equatable, Sendable {
    case saved(Clip)
    case failed(String)
}

struct CapturePerformanceSnapshot: Equatable, Sendable {
    var startedAt: Date?
    var videoSamplesReceived: Int = 0
    var videoSamplesAppended: Int = 0
    var audioSamplesReceived: Int = 0
    var audioSamplesAppended: Int = 0
    var incompleteVideoFramesDropped: Int = 0
    var videoInputBackpressureDrops: Int = 0
    var segmentFlushCount: Int = 0
    var averageVideoAppendMilliseconds: Double = 0
    var averageAudioAppendMilliseconds: Double = 0
    var lastSegmentFlushMilliseconds: Double = 0

    static let empty = CapturePerformanceSnapshot(startedAt: nil)

    var videoSamplesPerSecond: Double {
        samplesPerSecond(videoSamplesReceived)
    }

    var audioSamplesPerSecond: Double {
        samplesPerSecond(audioSamplesReceived)
    }

    private func samplesPerSecond(_ count: Int, now: Date = Date()) -> Double {
        guard let startedAt else { return 0 }
        let elapsed = now.timeIntervalSince(startedAt)
        guard elapsed > 0 else { return 0 }
        return Double(count) / elapsed
    }
}

struct CaptureHealthSnapshot: Equatable, Sendable {
    var detectedAppName: String?
    var captureState: CaptureRuntimeState
    var activeSegmentCount: Int
    var currentBufferDurationSeconds: TimeInterval
    var lastVideoSampleAt: Date?
    var lastAudioSampleAt: Date?
    var audioStatus: AudioTrackStatus
    var audioLevel: Double = 0
    var audioQualityScore: Double = 0
    var recentAudioLevels: [Double] = []
    var audioSampleRate: Double?
    var audioChannelCount: Int = 0
    var performance: CapturePerformanceSnapshot = .empty
    var outputFolder: URL?
    var lastSaveResult: SaveResult?
    var lastError: String?

    static let empty = CaptureHealthSnapshot(
        detectedAppName: nil,
        captureState: .idle,
        activeSegmentCount: 0,
        currentBufferDurationSeconds: 0,
        lastVideoSampleAt: nil,
        lastAudioSampleAt: nil,
        audioStatus: .none,
        audioLevel: 0,
        audioQualityScore: 0,
        recentAudioLevels: [],
        audioSampleRate: nil,
        audioChannelCount: 0,
        performance: .empty,
        outputFolder: nil,
        lastSaveResult: nil,
        lastError: nil
    )

    func isVideoStalled(now: Date = Date(), threshold: TimeInterval = 8) -> Bool {
        guard captureState == .recording else { return false }
        guard let lastVideoSampleAt else { return activeSegmentCount == 0 }
        return now.timeIntervalSince(lastVideoSampleAt) > threshold
    }

    func isAudioStalled(now: Date = Date(), threshold: TimeInterval = 10) -> Bool {
        guard captureState == .recording, audioStatus != .none else { return false }
        guard let lastAudioSampleAt else { return audioStatus == .expectedButMissing }
        return now.timeIntervalSince(lastAudioSampleAt) > threshold
    }

    var hasLiveAudioSamples: Bool {
        lastAudioSampleAt != nil && audioStatus != .none && audioStatus != .expectedButMissing
    }

    var audioMonitorDescription: String {
        guard hasLiveAudioSamples else {
            return audioStatus.rawValue
        }

        let percent = Int((audioQualityScore * 100).rounded())
        return "\(audioStatus.rawValue) · \(percent)%"
    }
}

extension CaptureState {
    var game: Game? {
        switch self {
        case .idle, .permissionRequired, .failed:
            return nil
        case .waitingForWindow(let game),
             .recording(let game, _),
             .savingClip(let game):
            return game
        }
    }

    var runtimeState: CaptureRuntimeState {
        switch self {
        case .idle:
            return .idle
        case .waitingForWindow, .permissionRequired:
            return .waitingForWindow
        case .recording:
            return .recording
        case .savingClip:
            return .saving
        case .failed:
            return .failed
        }
    }

    var isRecording: Bool {
        if case .recording = self {
            return true
        }
        return false
    }

    var locksCaptureConfiguration: Bool {
        switch self {
        case .recording, .savingClip:
            return true
        case .idle, .waitingForWindow, .permissionRequired, .failed:
            return false
        }
    }
}

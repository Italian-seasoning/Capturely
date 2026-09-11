import Foundation

struct RecordingDisplayStatus: Equatable, Sendable {
    var captureState: CaptureState
    var windowTitle: String?
    var isWindowLocked: Bool
    var bufferDurationSeconds: TimeInterval
    var storageFreeDescription: String
    var micStatusDescription: String

    init(
        captureState: CaptureState = .recording(game: .placeholderRoblox, preset: .balanced),
        windowTitle: String? = "Rivals",
        isWindowLocked: Bool = true,
        bufferDurationSeconds: TimeInterval = TimeInterval(CapturePreset.balanced.replayDurationSeconds),
        storageFreeDescription: String = "Local storage ready",
        micStatusDescription: String = "Mic on"
    ) {
        self.captureState = captureState
        self.windowTitle = windowTitle
        self.isWindowLocked = isWindowLocked
        self.bufferDurationSeconds = bufferDurationSeconds
        self.storageFreeDescription = storageFreeDescription
        self.micStatusDescription = micStatusDescription
    }

    var primaryLine: String {
        switch captureState {
        case .idle, .permissionRequired, .failed:
            if let game {
                return "READY · \(Self.appLabel(for: game))"
            }
            return "STANDBY"
        case .waitingForWindow(let game):
            return "READY · \(Self.appLabel(for: game))"
        case .recording(let game, _), .savingClip(let game):
            return "REC · \(Self.appLabel(for: game))"
        }
    }

    var title: String {
        switch captureState {
        case .idle:
            return "Replay buffer is ready"
        case .waitingForWindow:
            return "Finding game window"
        case .permissionRequired:
            return "Permission required"
        case .recording:
            return canSaveClip ? "Replay buffer is live" : "Buffer warming up"
        case .savingClip:
            return "Saving clip"
        case .failed:
            return "Recording unavailable"
        }
    }

    var subtitle: String {
        if case .idle = captureState {
            return cleanedWindowTitle.map(Self.compactWindowLabel(for:)) ?? "Ready"
        }
        if case .waitingForWindow = captureState {
            return cleanedWindowTitle.map(Self.compactWindowLabel(for:)) ?? "Finding window"
        }

        let parts = [
            cleanedWindowTitle.map(Self.compactWindowLabel(for:)),
            bufferDescription,
            isWindowLocked ? nil : "Finding window"
        ].compactMap { $0 }

        return parts.joined(separator: " · ")
    }

    var detectedGameLabel: String {
        game.map(Self.appLabel(for:)) ?? "None"
    }

    var bufferLengthDescription: String {
        bufferDescription ?? "No buffer"
    }

    var isRecording: Bool {
        if case .recording = captureState {
            return true
        }
        return false
    }

    var canSaveClip: Bool {
        isRecording && bufferDurationSeconds >= Self.minimumSaveableBufferSeconds
    }

    var bufferFillFraction: Double {
        switch captureState {
        case .recording(_, let preset):
            guard preset.replayDurationSeconds > 0 else { return 0 }
            return min(max(bufferDurationSeconds / TimeInterval(preset.replayDurationSeconds), 0.04), 1)
        case .savingClip:
            return 0.90
        case .waitingForWindow:
            return 0.18
        case .idle, .permissionRequired, .failed:
            return 0.0
        }
    }

    var game: Game? {
        switch captureState {
        case .idle:
            return nil
        case .waitingForWindow(let game),
             .recording(let game, _),
             .savingClip(let game):
            return game
        case .permissionRequired, .failed:
            return nil
        }
    }

    private var preset: CapturePreset? {
        switch captureState {
        case .recording(_, let preset):
            return preset
        default:
            return nil
        }
    }

    private var cleanedWindowTitle: String? {
        guard let title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }
        return title
    }

    private var bufferDescription: String? {
        guard let preset else {
            return nil
        }
        let roundedSeconds = Int(bufferDurationSeconds.rounded())
        if roundedSeconds <= 0 {
            return "0s ready"
        }
        if roundedSeconds < preset.replayDurationSeconds {
            return "\(roundedSeconds)s ready"
        }
        return "\(preset.replayDurationSeconds)s buffer"
    }

    static func appLabel(for game: Game) -> String {
        let joined = [game.displayName, game.bundleIdentifier ?? ""].joined(separator: " ").lowercased()
        if joined.contains("roblox") {
            return "ROBLOX"
        }
        return game.displayName.uppercased()
    }

    private static func compactWindowLabel(for title: String) -> String {
        let lowercasedTitle = title.lowercased()
        if lowercasedTitle.contains("roblox") {
            return "Roblox"
        }
        if lowercasedTitle.contains("display") {
            return title
        }
        return title
    }
}

private extension RecordingDisplayStatus {
    static let minimumSaveableBufferSeconds: TimeInterval = 4
}

private extension Game {
    static let placeholderRoblox = Game(
        displayName: "Roblox",
        bundleIdentifier: "com.roblox.Roblox"
    )
}

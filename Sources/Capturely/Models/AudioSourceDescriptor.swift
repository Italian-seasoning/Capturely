import Foundation

enum AudioSourceKind: String, Codable, Hashable, Sendable {
    case system
    case microphone
    case application
}

struct AudioSourceDescriptor: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var kind: AudioSourceKind
    var displayName: String
    var bundleIdentifier: String?
    var gain: Double

    static func application(
        displayName: String,
        bundleIdentifier: String,
        gain: Double = 1
    ) -> Self {
        Self(
            id: "application:\(bundleIdentifier)",
            kind: .application,
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            gain: min(max(gain, 0), 1.5)
        )
    }

    static func system(gain: Double = 1) -> Self {
        Self(
            id: "system",
            kind: .system,
            displayName: "System Audio",
            bundleIdentifier: nil,
            gain: min(max(gain, 0), 1.5)
        )
    }

    static func microphone(deviceID: String?, gain: Double = 1) -> Self {
        Self(
            id: "microphone:\(deviceID ?? "default")",
            kind: .microphone,
            displayName: "Microphone",
            bundleIdentifier: nil,
            gain: min(max(gain, 0), 1.5)
        )
    }
}

struct ClipAudioTrack: Codable, Equatable, Sendable {
    var trackIndex: Int
    var source: AudioSourceDescriptor
}

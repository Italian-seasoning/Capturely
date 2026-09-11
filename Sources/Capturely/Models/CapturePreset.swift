import Foundation

struct CapturePreset: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case balanced
        case editing
        case storageSaver
        case custom
    }

    enum Codec: String, Codable, Sendable {
        case hevc
        case h264
    }

    var id: String
    var kind: Kind
    var displayName: String
    var replayDurationSeconds: Int
    var codec: Codec
    var maximumFramesPerSecond: Int
    var maximumHeight: Int
    var videoBitrate: Int?
    var recordsMicrophone: Bool
    var recordsSystemAudio: Bool
    var audioGains: [Double]? = nil

    var qualityScore: Double {
        switch kind {
        case .storageSaver:
            return 0.28
        case .balanced:
            return 0.62
        case .editing:
            return 0.92
        case .custom:
            return 0.72
        }
    }

    var bitrateDescription: String {
        guard let videoBitrate else { return "Automatic" }
        return "\(videoBitrate / 1_000_000) Mbps"
    }

    var storageEstimateDescription: String {
        guard let videoBitrate else { return "Varies by scene" }
        let bytesPerMinute = Double(videoBitrate) / 8 * 60
        return "\(ByteCountFormatter.string(fromByteCount: Int64(bytesPerMinute), countStyle: .file)) / min"
    }

    static let balanced = CapturePreset(
        id: "balanced",
        kind: .balanced,
        displayName: "Rivals",
        replayDurationSeconds: 60,
        codec: .hevc,
        maximumFramesPerSecond: 60,
        maximumHeight: 1080,
        videoBitrate: 16_000_000,
        recordsMicrophone: false,
        recordsSystemAudio: true
    )

    static let editing = CapturePreset(
        id: "editing",
        kind: .editing,
        displayName: "Studio",
        replayDurationSeconds: 60,
        codec: .hevc,
        maximumFramesPerSecond: 60,
        maximumHeight: 1440,
        videoBitrate: 28_000_000,
        recordsMicrophone: false,
        recordsSystemAudio: true
    )

    static let storageSaver = CapturePreset(
        id: "storage-saver",
        kind: .storageSaver,
        displayName: "Light",
        replayDurationSeconds: 60,
        codec: .hevc,
        maximumFramesPerSecond: 30,
        maximumHeight: 720,
        videoBitrate: 5_000_000,
        recordsMicrophone: false,
        recordsSystemAudio: true
    )

    static let custom = CapturePreset(
        id: "custom",
        kind: .custom,
        displayName: "Custom",
        replayDurationSeconds: 60,
        codec: .hevc,
        maximumFramesPerSecond: 30,
        maximumHeight: 1080,
        videoBitrate: 10_000_000,
        recordsMicrophone: false,
        recordsSystemAudio: true
    )

    static let all: [CapturePreset] = [.storageSaver, .balanced, .editing, .custom]

    static func preset(id: CapturePreset.ID) -> CapturePreset {
        all.first { $0.id == id } ?? .balanced
    }

    static func preset(id: CapturePreset.ID, settings: AppSettings) -> CapturePreset {
        guard id == Self.custom.id else {
            return preset(id: id)
        }

        var preset = Self.custom
        let customPreset = settings.customPreset.performanceSafe
        preset.maximumHeight = customPreset.maximumHeight
        preset.maximumFramesPerSecond = customPreset.maximumFramesPerSecond
        preset.videoBitrate = customPreset.videoBitrateMbps * 1_000_000
        preset.codec = customPreset.codec ?? .hevc
        return preset
    }

    func applying(settings: AppSettings) -> CapturePreset {
        var copy = self
        copy.replayDurationSeconds = settings.replayDurationSeconds
        copy.recordsSystemAudio = settings.recordsSystemAudio
        copy.recordsMicrophone = settings.recordsMicrophone
        copy.audioGains = (settings.recordsSystemAudio ? [settings.systemAudioMix] : [])
            + (settings.recordsMicrophone ? [settings.microphoneMix] : [])
        return copy
    }
}

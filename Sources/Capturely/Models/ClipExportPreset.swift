import AVFoundation

enum ClipExportPreset: String, CaseIterable, Identifiable, Sendable {
    case original
    case hd1080
    case hd720

    var id: Self { self }

    var displayName: String {
        switch self {
        case .original: "Original"
        case .hd1080: "1080p"
        case .hd720: "720p"
        }
    }

    var filenameSuffix: String {
        switch self {
        case .original: "original"
        case .hd1080: "1080p"
        case .hd720: "720p"
        }
    }

    var assetExportPreset: String? {
        switch self {
        case .original: nil
        case .hd1080: AVAssetExportPreset1920x1080
        case .hd720: AVAssetExportPreset1280x720
        }
    }
}

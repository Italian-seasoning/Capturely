import Foundation

enum CaptureSourceMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case selectedDisplay
    case gameWindow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .selectedDisplay:
            return "Selected Screen"
        case .gameWindow:
            return "Game Window"
        }
    }
}

struct CaptureDisplayOption: Identifiable, Equatable, Sendable {
    var id: UInt32 { displayID }
    var displayID: UInt32
    var name: String
    var width: Int
    var height: Int

    var detail: String {
        "\(width)x\(height)"
    }
}

struct MicrophoneDeviceOption: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
}

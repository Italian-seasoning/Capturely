import Foundation

enum HotkeyModifier: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case option
    case command
    case shift
    case control

    var displayValue: String {
        switch self {
        case .option:
            return "Option"
        case .command:
            return "Command"
        case .shift:
            return "Shift"
        case .control:
            return "Control"
        }
    }

    var glyph: String {
        switch self {
        case .option:
            return "⌥"
        case .command:
            return "⌘"
        case .shift:
            return "⇧"
        case .control:
            return "⌃"
        }
    }
}

struct SaveClipHotkey: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String { "\(modifiers.map(\.rawValue).joined(separator: "-"))-\(key.lowercased())" }
    var key: String
    var modifiers: [HotkeyModifier]

    var displayValue: String {
        "\(modifiers.map(\.displayValue).joined(separator: "+"))+\(key.uppercased())"
    }

    var compactDisplayValue: String {
        "\(modifiers.map(\.glyph).joined())\(key.uppercased())"
    }

    static let optionCommandC = SaveClipHotkey(key: "c", modifiers: [.option, .command])
    static let optionCommandR = SaveClipHotkey(key: "r", modifiers: [.option, .command])
    static let shiftCommandC = SaveClipHotkey(key: "c", modifiers: [.shift, .command])
    static let controlOptionC = SaveClipHotkey(key: "c", modifiers: [.control, .option])

    static let choices: [SaveClipHotkey] = [
        .optionCommandC,
        .shiftCommandC,
        .controlOptionC,
        .optionCommandR
    ]
}

struct CustomCapturePresetSettings: Codable, Equatable, Hashable, Sendable {
    var maximumHeight: Int
    var maximumFramesPerSecond: Int
    var videoBitrateMbps: Int
    var codec: CapturePreset.Codec? = nil

    static let defaults = CustomCapturePresetSettings(
        maximumHeight: 1080,
        maximumFramesPerSecond: 60,
        videoBitrateMbps: 16
    )

    var performanceSafe: CustomCapturePresetSettings {
        CustomCapturePresetSettings(
            maximumHeight: min(max(maximumHeight, 720), 1440),
            maximumFramesPerSecond: min(max(maximumFramesPerSecond, 24), 60),
            videoBitrateMbps: min(max(videoBitrateMbps, 5), 36),
            codec: codec
        )
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var selectedPresetID: CapturePreset.ID
    var clipLibraryURL: URL?
    var saveClipHotkeyDisplayValue: String
    var saveClipHotkey: SaveClipHotkey
    var captureSourceMode: CaptureSourceMode
    var selectedDisplayID: UInt32?
    var replayDurationSeconds: Int
    var recordsSystemAudio: Bool
    var recordsMicrophone: Bool
    var microphoneDeviceID: String?
    var systemAudioMix: Double
    var microphoneMix: Double
    var customPreset: CustomCapturePresetSettings
    var hasCompletedOnboarding: Bool
    var automaticGameSessions = true
    var keepsEditableAudio = true
    var libraryLimitGB = 0
    var logsGameProcess = true

    static let defaults = AppSettings(
        selectedPresetID: CapturePreset.balanced.id,
        clipLibraryURL: nil,
        saveClipHotkeyDisplayValue: "Option+Command+C",
        saveClipHotkey: .optionCommandC,
        captureSourceMode: .selectedDisplay,
        selectedDisplayID: nil,
        replayDurationSeconds: 60,
        recordsSystemAudio: true,
        recordsMicrophone: false,
        microphoneDeviceID: nil,
        systemAudioMix: 1,
        microphoneMix: 0.82,
        customPreset: .defaults,
        hasCompletedOnboarding: false
    )

    enum CodingKeys: String, CodingKey {
        case selectedPresetID
        case clipLibraryURL
        case saveClipHotkeyDisplayValue
        case saveClipHotkey
        case captureSourceMode
        case selectedDisplayID
        case replayDurationSeconds
        case recordsSystemAudio
        case recordsMicrophone
        case microphoneDeviceID
        case systemAudioMix
        case microphoneMix
        case customPreset
        case hasCompletedOnboarding
        case automaticGameSessions, keepsEditableAudio, libraryLimitGB
        case logsGameProcess
    }

    init(
        selectedPresetID: CapturePreset.ID,
        clipLibraryURL: URL?,
        saveClipHotkeyDisplayValue: String,
        saveClipHotkey: SaveClipHotkey = .optionCommandC,
        captureSourceMode: CaptureSourceMode,
        selectedDisplayID: UInt32?,
        replayDurationSeconds: Int,
        recordsSystemAudio: Bool,
        recordsMicrophone: Bool,
        microphoneDeviceID: String?,
        systemAudioMix: Double = 1,
        microphoneMix: Double = 0.82,
        customPreset: CustomCapturePresetSettings = .defaults,
        hasCompletedOnboarding: Bool = false
    ) {
        self.selectedPresetID = selectedPresetID
        self.clipLibraryURL = clipLibraryURL
        self.saveClipHotkeyDisplayValue = saveClipHotkeyDisplayValue
        self.saveClipHotkey = saveClipHotkey
        self.captureSourceMode = captureSourceMode
        self.selectedDisplayID = selectedDisplayID
        self.replayDurationSeconds = replayDurationSeconds
        self.recordsSystemAudio = recordsSystemAudio
        self.recordsMicrophone = recordsMicrophone
        self.microphoneDeviceID = microphoneDeviceID
        self.systemAudioMix = systemAudioMix
        self.microphoneMix = microphoneMix
        self.customPreset = customPreset.performanceSafe
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.selectedPresetID = try container.decodeIfPresent(CapturePreset.ID.self, forKey: .selectedPresetID) ?? Self.defaults.selectedPresetID
        self.clipLibraryURL = try container.decodeIfPresent(URL.self, forKey: .clipLibraryURL)
        self.saveClipHotkeyDisplayValue = try container.decodeIfPresent(String.self, forKey: .saveClipHotkeyDisplayValue) ?? Self.defaults.saveClipHotkeyDisplayValue
        self.saveClipHotkey = try container.decodeIfPresent(SaveClipHotkey.self, forKey: .saveClipHotkey) ?? Self.defaults.saveClipHotkey
        self.captureSourceMode = try container.decodeIfPresent(CaptureSourceMode.self, forKey: .captureSourceMode) ?? Self.defaults.captureSourceMode
        self.selectedDisplayID = try container.decodeIfPresent(UInt32.self, forKey: .selectedDisplayID)
        self.replayDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .replayDurationSeconds) ?? Self.defaults.replayDurationSeconds
        self.recordsSystemAudio = try container.decodeIfPresent(Bool.self, forKey: .recordsSystemAudio) ?? Self.defaults.recordsSystemAudio
        self.recordsMicrophone = try container.decodeIfPresent(Bool.self, forKey: .recordsMicrophone) ?? Self.defaults.recordsMicrophone
        self.microphoneDeviceID = try container.decodeIfPresent(String.self, forKey: .microphoneDeviceID)
        self.systemAudioMix = try container.decodeIfPresent(Double.self, forKey: .systemAudioMix) ?? Self.defaults.systemAudioMix
        self.microphoneMix = try container.decodeIfPresent(Double.self, forKey: .microphoneMix) ?? Self.defaults.microphoneMix
        self.customPreset = (try container.decodeIfPresent(CustomCapturePresetSettings.self, forKey: .customPreset) ?? Self.defaults.customPreset).performanceSafe
        self.hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? Self.defaults.hasCompletedOnboarding
        automaticGameSessions = try container.decodeIfPresent(Bool.self, forKey: .automaticGameSessions) ?? true
        logsGameProcess = try container.decodeIfPresent(Bool.self, forKey: .logsGameProcess) ?? true
        keepsEditableAudio = try container.decodeIfPresent(Bool.self, forKey: .keepsEditableAudio) ?? true
        libraryLimitGB = min(1000, max(0, try container.decodeIfPresent(Int.self, forKey: .libraryLimitGB) ?? 0))
    }
}

struct AppSettingsStore: Sendable {
    var fileURL: URL

    func load() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .defaults
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.capturely.decode(AppSettings.self, from: data)
    }

    func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.capturely.encode(settings)
        try data.write(to: fileURL, options: [.atomic])
    }

    func saveAsync(_ settings: AppSettings) async throws {
        try await Task.detached(priority: .utility) {
            try save(settings)
        }.value
    }
}

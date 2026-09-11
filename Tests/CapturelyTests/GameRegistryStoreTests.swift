import Foundation
import Testing
@testable import Capturely

@Test func gameRegistryPersistsGamesAsJSON() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("games.json")

    let store = GameRegistryStore(fileURL: file)
    let game = Game(displayName: "Valorant", bundleIdentifier: "com.riotgames.valorant")
    try store.save([game])

    let loaded = try store.load()

    #expect(loaded == [game])
}

@Test func appSettingsPersistsCaptureControls() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let file = directory.appendingPathComponent("settings.json")
    let store = AppSettingsStore(fileURL: file)
    let settings = AppSettings(
        selectedPresetID: CapturePreset.editing.id,
        clipLibraryURL: URL(fileURLWithPath: "/tmp/Capturely-Clips", isDirectory: true),
        saveClipHotkeyDisplayValue: "Option+Command+C",
        captureSourceMode: .selectedDisplay,
        selectedDisplayID: 42,
        replayDurationSeconds: 120,
        recordsSystemAudio: true,
        recordsMicrophone: true,
        microphoneDeviceID: "mic-1",
        systemAudioMix: 0.75,
        microphoneMix: 1.1,
        customPreset: CustomCapturePresetSettings(maximumHeight: 1440, maximumFramesPerSecond: 120, videoBitrateMbps: 32),
        hasCompletedOnboarding: true
    )

    try store.save(settings)

    #expect(try store.load() == settings)
}

@Test func appSettingsDecodesLegacyFilesWithDefaults() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let file = directory.appendingPathComponent("settings.json")
    try Data(#"{"selectedPresetID":"balanced","saveClipHotkeyDisplayValue":"Option+Command+C"}"#.utf8).write(to: file)
    let loaded = try AppSettingsStore(fileURL: file).load()

    #expect(loaded.captureSourceMode == .selectedDisplay)
    #expect(loaded.replayDurationSeconds == 60)
    #expect(loaded.recordsSystemAudio)
    #expect(!loaded.recordsMicrophone)
    #expect(loaded.saveClipHotkey == .optionCommandC)
    #expect(loaded.systemAudioMix == 1)
    #expect(loaded.microphoneMix == 0.82)
    #expect(loaded.customPreset == .defaults)
    #expect(!loaded.hasCompletedOnboarding)
}

@Test func appSettingsClampsCustomPresetForPerformance() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let file = directory.appendingPathComponent("settings.json")
    try Data("""
    {
      "selectedPresetID": "custom",
      "saveClipHotkeyDisplayValue": "Option+Command+C",
      "customPreset": {
        "maximumHeight": 2160,
        "maximumFramesPerSecond": 120,
        "videoBitrateMbps": 80
      }
    }
    """.utf8).write(to: file)

    let loaded = try AppSettingsStore(fileURL: file).load()

    #expect(loaded.customPreset.maximumHeight == 1440)
    #expect(loaded.customPreset.maximumFramesPerSecond == 60)
    #expect(loaded.customPreset.videoBitrateMbps == 36)
}

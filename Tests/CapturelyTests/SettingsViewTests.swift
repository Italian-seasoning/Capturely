import Foundation
import Testing
@testable import Capturely

@MainActor
@Test func settingsViewBindingsCallConfiguredActions() {
    var selectedPresetID: CapturePreset.ID?
    var replayDuration: Int?
    var captureSourceMode: CaptureSourceMode?
    var selectedDisplayID: UInt32??
    var recordsSystemAudio: Bool?
    var recordsMicrophone: Bool?
    var microphoneDeviceID: String??
    var saveClipHotkey: SaveClipHotkey?
    var customPresets: [CustomCapturePresetSettings] = []
    var systemAudioMix: Double?
    var microphoneMix: Double?
    var didRequestScreenCapturePermission = false

    let settings = AppSettings(
        selectedPresetID: CapturePreset.balanced.id,
        clipLibraryURL: nil,
        saveClipHotkeyDisplayValue: "Option+Command+C",
        captureSourceMode: .selectedDisplay,
        selectedDisplayID: nil,
        replayDurationSeconds: 60,
        recordsSystemAudio: true,
        recordsMicrophone: false,
        microphoneDeviceID: nil,
        systemAudioMix: 1,
        microphoneMix: 0.82,
        customPreset: .defaults
    )
    let view = SettingsView(
        settings: settings,
        setSelectedPreset: { selectedPresetID = $0 },
        setReplayDuration: { replayDuration = $0 },
        setCaptureSourceMode: { captureSourceMode = $0 },
        setSelectedDisplayID: { selectedDisplayID = $0 },
        setRecordsSystemAudio: { recordsSystemAudio = $0 },
        setRecordsMicrophone: { recordsMicrophone = $0 },
        setMicrophoneDeviceID: { microphoneDeviceID = $0 },
        setSaveClipHotkey: { saveClipHotkey = $0 },
        setCustomPreset: { customPresets.append($0) },
        setSystemAudioMix: { systemAudioMix = $0 },
        setMicrophoneMix: { microphoneMix = $0 },
        requestScreenCapturePermission: { didRequestScreenCapturePermission = true }
    )

    #expect(view.selectedPresetBinding.wrappedValue == CapturePreset.balanced.id)
    #expect(view.replayDurationBinding.wrappedValue == 60)
    #expect(view.captureSourceBinding.wrappedValue == .selectedDisplay)
    #expect(view.selectedDisplayBinding.wrappedValue == nil)
    #expect(view.recordsSystemAudioBinding.wrappedValue)
    #expect(!view.recordsMicrophoneBinding.wrappedValue)
    #expect(view.microphoneDeviceBinding.wrappedValue == "")
    #expect(view.hotkeyBinding.wrappedValue == .optionCommandC)

    view.selectedPresetBinding.wrappedValue = CapturePreset.editing.id
    view.replayDurationBinding.wrappedValue = 120
    view.captureSourceBinding.wrappedValue = .selectedDisplay
    view.selectedDisplayBinding.wrappedValue = 42
    view.recordsSystemAudioBinding.wrappedValue = false
    view.recordsMicrophoneBinding.wrappedValue = true
    view.microphoneDeviceBinding.wrappedValue = "mic-1"
    view.microphoneDeviceBinding.wrappedValue = ""
    view.hotkeyBinding.wrappedValue = .shiftCommandC
    view.customHeightBinding.wrappedValue = 1440
    view.customFrameRateBinding.wrappedValue = 120
    view.customBitrateBinding.wrappedValue = 32
    view.systemAudioMixBinding.wrappedValue = 0.75
    view.microphoneMixBinding.wrappedValue = 1.1
    view.requestScreenCapturePermission()

    #expect(selectedPresetID == CapturePreset.editing.id)
    #expect(replayDuration == 120)
    #expect(captureSourceMode == .selectedDisplay)
    #expect(selectedDisplayID == 42)
    #expect(recordsSystemAudio == false)
    #expect(recordsMicrophone == true)
    #expect(microphoneDeviceID != nil)
    #expect(microphoneDeviceID! == nil)
    #expect(saveClipHotkey == .shiftCommandC)
    #expect(customPresets.map(\.maximumHeight).contains(1440))
    #expect(customPresets.map(\.maximumFramesPerSecond).contains(60))
    #expect(customPresets.map(\.videoBitrateMbps).contains(32))
    #expect(systemAudioMix == 0.75)
    #expect(microphoneMix == 1.1)
    #expect(didRequestScreenCapturePermission)
}

@MainActor
@Test func settingsViewButtonsCallConfiguredActions() {
    let scannedGame = Game(displayName: "Test Game", bundleIdentifier: "com.example.game")
    var calls: [String] = []
    var addedGame: Game?
    var removedGame: Game?

    let view = SettingsView(
        chooseClipLibrary: { calls.append("chooseClipLibrary") },
        resetClipLibrary: { calls.append("resetClipLibrary") },
        refreshCaptureDevices: { calls.append("refreshCaptureDevices") },
        addRunningApp: { calls.append("addRunningApp") },
        chooseApp: { calls.append("chooseApp") },
        scanApplications: { calls.append("scanApplications") },
        addScannedApplication: { addedGame = $0 },
        removeGame: { removedGame = $0 }
    )

    view.chooseClipLibrary()
    view.resetClipLibrary()
    view.refreshCaptureDevices()
    view.addRunningApp()
    view.chooseApp()
    view.scanApplications()
    view.addScannedApplication(scannedGame)
    view.removeGame(scannedGame)

    #expect(calls == [
        "chooseClipLibrary",
        "resetClipLibrary",
        "refreshCaptureDevices",
        "addRunningApp",
        "chooseApp",
        "scanApplications"
    ])
    #expect(addedGame == scannedGame)
    #expect(removedGame == scannedGame)
}

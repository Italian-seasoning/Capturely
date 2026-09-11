import SwiftUI

struct SettingsView: View {
    var settings: AppSettings = .defaults
    var permissionSummary: PermissionSummary = PermissionSummary(microphoneGranted: false, screenCaptureStatus: "Not checked")
    var displayOptions: [CaptureDisplayOption] = []
    var microphoneOptions: [MicrophoneDeviceOption] = []
    var isLocked: Bool = false
    var games: [Game] = []
    var scannedApplications: [Game] = []
    var message: String?
    var setSelectedPreset: (CapturePreset.ID) -> Void = { _ in }
    var setReplayDuration: (Int) -> Void = { _ in }
    var setCaptureSourceMode: (CaptureSourceMode) -> Void = { _ in }
    var setSelectedDisplayID: (UInt32?) -> Void = { _ in }
    var setRecordsSystemAudio: (Bool) -> Void = { _ in }
    var setRecordsMicrophone: (Bool) -> Void = { _ in }
    var setMicrophoneDeviceID: (String?) -> Void = { _ in }
    var setSaveClipHotkey: (SaveClipHotkey) -> Void = { _ in }
    var setCustomPreset: (CustomCapturePresetSettings) -> Void = { _ in }
    var setSystemAudioMix: (Double) -> Void = { _ in }
    var setMicrophoneMix: (Double) -> Void = { _ in }
    var requestScreenCapturePermission: () -> Void = {}
    var chooseClipLibrary: () -> Void = {}
    var resetClipLibrary: () -> Void = {}
    var refreshCaptureDevices: () -> Void = {}
    var addRunningApp: () -> Void = {}
    var chooseApp: () -> Void = {}
    var scanApplications: () -> Void = {}
    var addScannedApplication: (Game) -> Void = { _ in }
    var removeGame: (Game) -> Void = { _ in }
    var setAutomaticGameSessions: (Bool) -> Void = { _ in }
    var setKeepsEditableAudio: (Bool) -> Void = { _ in }
    var setLibraryLimitGB: (Int) -> Void = { _ in }
    var setLogsGameProcess: (Bool) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("03 / SETTINGS")
                        .font(.caption.monospaced().weight(.bold))
                        .tracking(2)
                        .foregroundStyle(CyberTheme.red)
                    Text("Make it yours.")
                        .font(.system(size: 36, weight: .black))
                        .fontWidth(.condensed)
                        .tracking(-1.5)
                }
                .padding(.bottom, 6)

                CyberSettingsSection(title: "Replay Workflow") {
                    Toggle("Log game process while capturing", isOn: Binding(get: { settings.logsGameProcess }, set: setLogsGameProcess))
                    Text("Local CSV: game CPU, memory, traffic and capture health every 2s, with samples beside clips. Traffic is not ping; unavailable counters stay blank. Session logs cap at 10 MB.").font(.caption).foregroundStyle(CyberTheme.muted)
                    Toggle("Automatic game sessions", isOn: Binding(get: { settings.automaticGameSessions }, set: setAutomaticGameSessions))
                    Text("Buffer registered games, including Roblox, from launch to exit. Manual Stop lasts until the next launch.").font(.caption).foregroundStyle(CyberTheme.muted)
                    Toggle("Keep separate game / mic audio for editing", isOn: Binding(get: { settings.keepsEditableAudio }, set: setKeepsEditableAudio))
                    Text("Dual-source saves keep an extra original; allow roughly twice the storage.").font(.caption).foregroundStyle(CyberTheme.muted)
                    Picker("Automatic library cleanup", selection: Binding(get: { settings.libraryLimitGB }, set: setLibraryLimitGB)) {
                        Text("Off").tag(0)
                        ForEach([5, 10, 25, 50, 100, 250, 500, 1000], id: \.self) { Text("\($0) GB").tag($0) }
                    }
                    Text("Oldest unstarred clips move to Trash. Starred and open clips are kept. Trash still occupies disk space.").font(.caption).foregroundStyle(CyberTheme.muted)
                    Text("⌥⌘1 = 15s · ⌥⌘2 = 30s · ⌥⌘3 = 60s").font(.caption.monospaced())
                    Text("Saves available footage while the buffer fills; retains at least 60s for these shortcuts.").font(.caption).foregroundStyle(CyberTheme.muted)
                }

            if isLocked {
                    CyberPanel(padding: 10, cut: 8, isHot: true) {
                    Label("Stop capture to change source, quality, or audio devices.", systemImage: "lock.fill")
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(CyberTheme.muted)
                }
            }

                CyberSettingsSection(title: "Capture Source") {
                CyberSegmentedControl(
                    label: "Source",
                    selection: captureSourceBinding,
                    choices: CaptureSourceMode.allCases.map { CyberChoice(value: $0, label: $0.displayName) },
                    isEnabled: !isLocked
                )

                CyberMenuPicker(
                    label: "Display",
                    selection: selectedDisplayBinding,
                    choices: [CyberChoice<UInt32?>(value: nil, label: "Auto")] + displayOptions.map {
                        CyberChoice<UInt32?>(value: Optional($0.displayID), label: "\($0.name) · \($0.detail)")
                    },
                    isEnabled: !isLocked && settings.captureSourceMode == .selectedDisplay
                )

                Button("Refresh Displays", action: refreshCaptureDevices)
                    .buttonStyle(CyberButtonStyle(tone: .secondary, isEnabled: !isLocked))
                    .disabled(isLocked)
            }

                CyberSettingsSection(title: "Quality") {
                CyberSegmentedControl(
                    label: "Clipping Quality",
                    selection: selectedPresetBinding,
                    choices: CapturePreset.all.map { CyberChoice(value: $0.id, label: $0.displayName) },
                    isEnabled: !isLocked
                )

                CyberSegmentedControl(
                    label: "Replay Duration",
                    selection: replayDurationBinding,
                    choices: [
                        CyberChoice(value: 30, label: "30s"),
                        CyberChoice(value: 60, label: "60s"),
                        CyberChoice(value: 120, label: "2m"),
                        CyberChoice(value: 300, label: "5m")
                    ],
                    isEnabled: !isLocked
                )

                if settings.selectedPresetID == CapturePreset.custom.id {
                    CyberSegmentedControl(
                        label: "Codec",
                        selection: Binding(get: { settings.customPreset.codec ?? .hevc }, set: { codec in
                            var custom = settings.customPreset
                            custom.codec = codec
                            setCustomPreset(custom)
                        }),
                        choices: [CyberChoice(value: CapturePreset.Codec.hevc, label: "HEVC · efficient"), CyberChoice(value: .h264, label: "H.264 · compatible")],
                        isEnabled: !isLocked
                    )
                    CyberSegmentedControl(
                        label: "Resolution Cap",
                        selection: customHeightBinding,
                        choices: [
                            CyberChoice(value: 720, label: "720p"),
                            CyberChoice(value: 1080, label: "1080p"),
                            CyberChoice(value: 1440, label: "1440p")
                        ],
                        isEnabled: !isLocked
                    )

                    CyberSegmentedControl(
                        label: "Frame Rate Cap",
                        selection: customFrameRateBinding,
                        choices: [
                            CyberChoice(value: 30, label: "30 fps"),
                            CyberChoice(value: 60, label: "60 fps")
                        ],
                        isEnabled: !isLocked
                    )

                    CyberStepper(
                        label: "Bitrate",
                        value: customBitrateBinding,
                        range: 5...36,
                        suffix: "Mbps",
                        isEnabled: !isLocked
                    )
                }

                    CyberInfoRow(label: "Current Quality", value: selectedPreset.displayName)
                    Text("Light: 720p30 for minimum load. Rivals: 1080p60 for fast action. Studio: 1440p60 for more detail. Custom: tune resolution, codec, and bitrate.")
                        .font(.caption)
                        .foregroundStyle(CyberTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    CyberInfoRow(label: "Resolution Cap", value: "\(selectedPreset.maximumHeight)p")
                    CyberInfoRow(label: "Frame Rate Cap", value: "\(selectedPreset.maximumFramesPerSecond) fps")
                    CyberInfoRow(label: "Bitrate", value: selectedPreset.bitrateDescription)
                    CyberInfoRow(label: "Storage Estimate", value: selectedPreset.storageEstimateDescription)
            }

                CyberSettingsSection(title: "Audio") {
                CyberToggle(label: "System Audio", isOn: recordsSystemAudioBinding, isEnabled: !isLocked)

                CyberToggle(label: "Microphone", isOn: recordsMicrophoneBinding, isEnabled: !isLocked)

                CyberMenuPicker(
                    label: "Microphone Device",
                    selection: microphoneDeviceBinding,
                    choices: [CyberChoice(value: "", label: "System Default")] + microphoneOptions.map {
                        CyberChoice(value: $0.id, label: $0.name)
                    },
                    isEnabled: !isLocked && settings.recordsMicrophone
                )

                VStack(alignment: .leading) {
                    Text("System Mix \(Self.percent(settings.systemAudioMix))")
                            .font(.caption.weight(.semibold).monospaced())
                            .foregroundStyle(CyberTheme.muted)
                    CyberSlider(value: systemAudioMixBinding, range: 0...1.5, isEnabled: !isLocked && settings.recordsSystemAudio)
                }

                VStack(alignment: .leading) {
                    Text("Mic Mix \(Self.percent(settings.microphoneMix))")
                            .font(.caption.weight(.semibold).monospaced())
                            .foregroundStyle(CyberTheme.muted)
                    CyberSlider(value: microphoneMixBinding, range: 0...1.5, isEnabled: !isLocked && settings.recordsMicrophone)
                }

                    CyberInfoRow(label: "Microphone Permission", value: permissionSummary.microphoneGranted ? "Granted" : "Not granted")
            }

                CyberSettingsSection(title: "Hotkey") {
                CyberSegmentedControl(
                    label: "Save Clip",
                    selection: hotkeyBinding,
                    choices: SaveClipHotkey.choices.map { CyberChoice(value: $0, label: $0.compactDisplayValue) },
                    isEnabled: !isLocked
                )

                    CyberInfoRow(label: "Menu Display", value: settings.saveClipHotkey.compactDisplayValue)
            }

                CyberSettingsSection(title: "Save Location") {
                    CyberInfoRow(label: "Clip Folder", value: settings.clipLibraryURL?.path(percentEncoded: false) ?? "~/Movies/Capturely/Clips")
                HStack {
                    Button("Choose Folder...", action: chooseClipLibrary)
                            .buttonStyle(CyberButtonStyle(tone: .secondary, isEnabled: !isLocked))
                    Button("Use Default", action: resetClipLibrary)
                            .buttonStyle(CyberButtonStyle(tone: .ghost, isEnabled: !isLocked))
                }
                .disabled(isLocked)
            }

                CyberSettingsSection(title: "Games") {
                HStack {
                    Button("Add Running App", action: addRunningApp)
                            .buttonStyle(CyberButtonStyle(tone: .secondary, isEnabled: !isLocked))
                    Button("Choose App...", action: chooseApp)
                            .buttonStyle(CyberButtonStyle(tone: .secondary, isEnabled: !isLocked))
                    Button("Scan Applications", action: scanApplications)
                            .buttonStyle(CyberButtonStyle(tone: .ghost, isEnabled: !isLocked))
                }
                .disabled(isLocked)

                if let message {
                    Text(message)
                            .font(.caption.monospaced())
                            .foregroundStyle(CyberTheme.muted)
                }

                if games.isEmpty {
                    Text("No games added")
                            .font(.caption.monospaced())
                            .foregroundStyle(CyberTheme.muted)
                } else {
                    ForEach(games) { game in
                        GameSettingsRow(game: game, trailingSystemImage: "minus.circle", action: { removeGame(game) })
                            .disabled(isLocked)
                    }
                }
            }

            if !scannedApplications.isEmpty {
                    CyberSettingsSection(title: "Scan Results") {
                    ForEach(scannedApplications.prefix(20)) { game in
                        GameSettingsRow(game: game, trailingSystemImage: "plus.circle", action: { addScannedApplication(game) })
                            .disabled(isLocked)
                    }
                }
            }

                CyberSettingsSection(title: "Permissions") {
                    PermissionActionRow(
                        label: "Screen & System Audio",
                        value: permissionSummary.screenCaptureStatus,
                        actionTitle: permissionSummary.screenCaptureActionTitle,
                        systemImage: permissionSummary.screenCaptureGranted ? "checkmark.shield" : "lock.shield",
                        isEnabled: !isLocked && !permissionSummary.screenCaptureGranted,
                        action: requestScreenCapturePermission
                    )
                    CyberInfoRow(label: "Microphone", value: settings.recordsMicrophone ? "Enabled" : "Optional")
                    CyberInfoRow(label: "Notifications", value: "Used for recording and saved-clip alerts")
                    CyberInfoRow(label: "Save Clip Hotkey", value: settings.saveClipHotkey.displayValue)
                }
            }
            .padding(24)
        }
        .background(CyberTheme.void)
        .tint(CyberTheme.red)
    }

    private var selectedPreset: CapturePreset {
        CapturePreset.preset(id: settings.selectedPresetID, settings: settings)
    }

    var selectedPresetBinding: Binding<CapturePreset.ID> {
        Binding(
            get: { settings.selectedPresetID },
            set: { setSelectedPreset($0) }
        )
    }

    var replayDurationBinding: Binding<Int> {
        Binding(
            get: { settings.replayDurationSeconds },
            set: { setReplayDuration($0) }
        )
    }

    var captureSourceBinding: Binding<CaptureSourceMode> {
        Binding(
            get: { settings.captureSourceMode },
            set: { setCaptureSourceMode($0) }
        )
    }

    var selectedDisplayBinding: Binding<UInt32?> {
        Binding(
            get: { settings.selectedDisplayID },
            set: { setSelectedDisplayID($0) }
        )
    }

    var recordsSystemAudioBinding: Binding<Bool> {
        Binding(
            get: { settings.recordsSystemAudio },
            set: { setRecordsSystemAudio($0) }
        )
    }

    var recordsMicrophoneBinding: Binding<Bool> {
        Binding(
            get: { settings.recordsMicrophone },
            set: { setRecordsMicrophone($0) }
        )
    }

    var microphoneDeviceBinding: Binding<String> {
        Binding(
            get: { settings.microphoneDeviceID ?? "" },
            set: { setMicrophoneDeviceID($0.isEmpty ? nil : $0) }
        )
    }

    var hotkeyBinding: Binding<SaveClipHotkey> {
        Binding(
            get: { settings.saveClipHotkey },
            set: { setSaveClipHotkey($0) }
        )
    }

    var customHeightBinding: Binding<Int> {
        Binding(
            get: { settings.customPreset.maximumHeight },
            set: { value in
                var customPreset = settings.customPreset
                customPreset.maximumHeight = value
                setCustomPreset(customPreset)
            }
        )
    }

    var customFrameRateBinding: Binding<Int> {
        Binding(
            get: { settings.customPreset.maximumFramesPerSecond },
            set: { value in
                var customPreset = settings.customPreset
                customPreset.maximumFramesPerSecond = value
                setCustomPreset(customPreset)
            }
        )
    }

    var customBitrateBinding: Binding<Int> {
        Binding(
            get: { settings.customPreset.videoBitrateMbps },
            set: { value in
                var customPreset = settings.customPreset
                customPreset.videoBitrateMbps = value
                setCustomPreset(customPreset)
            }
        )
    }

    var systemAudioMixBinding: Binding<Double> {
        Binding(
            get: { settings.systemAudioMix },
            set: { setSystemAudioMix($0) }
        )
    }

    var microphoneMixBinding: Binding<Double> {
        Binding(
            get: { settings.microphoneMix },
            set: { setMicrophoneMix($0) }
        )
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

struct CyberSettingsSection<Content: View>: View {
    var title: String
    var content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        CyberPanel(padding: 18, cut: 3) {
            VStack(alignment: .leading, spacing: 10) {
                CyberSectionTitle(title: title)
                content
                    .font(.caption.monospaced())
            }
        }
    }
}

struct CyberInfoRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label.uppercased())
                .font(.caption2.weight(.heavy).monospaced())
                .tracking(0.8)
                .foregroundStyle(CyberTheme.muted)
                .frame(width: 132, alignment: .leading)
            Text(value)
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(CyberTheme.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}

struct PermissionActionRow: View {
    var label: String
    var value: String
    var actionTitle: String
    var systemImage: String
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label.uppercased())
                .font(.caption2.weight(.heavy).monospaced())
                .tracking(0.8)
                .foregroundStyle(CyberTheme.muted)
                .frame(width: 132, alignment: .leading)
            Text(value)
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(CyberTheme.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button(action: action) {
                Label(actionTitle, systemImage: systemImage)
                    .labelStyle(.iconOnly)
                    .frame(width: 18, height: 16)
            }
            .buttonStyle(CyberButtonStyle(tone: .ghost, isEnabled: isEnabled))
            .disabled(!isEnabled)
            .accessibilityLabel(actionTitle)
            .help(actionTitle)
        }
    }
}

struct CyberChoice<Value: Hashable>: Identifiable {
    var value: Value
    var label: String

    var id: Value { value }
}

struct CyberSegmentedControl<Value: Hashable>: View {
    var label: String
    @Binding var selection: Value
    var choices: [CyberChoice<Value>]
    var isEnabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CyberControlLabel(label)
            HStack(spacing: 4) {
                ForEach(choices) { choice in
                    Button {
                        guard isEnabled else { return }
                        selection = choice.value
                    } label: {
                        Text(choice.label.uppercased())
                            .font(.caption2.weight(.heavy).monospaced())
                            .tracking(0.6)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                    }
                    .buttonStyle(.plain)
                            .foregroundStyle(selection == choice.value ? CyberTheme.void : CyberTheme.muted)
                    .background(
                        CutCornerRectangle(cut: 5)
                                    .fill(selection == choice.value ? CyberTheme.red : CyberTheme.void.opacity(0.62))
                            .overlay(
                                CutCornerRectangle(cut: 5)
                                    .stroke(selection == choice.value ? CyberTheme.red.opacity(0.82) : CyberTheme.dim.opacity(0.70), lineWidth: 1)
                            )
                    )
                    .opacity(isEnabled ? 1 : 0.42)
                    .disabled(!isEnabled)
                    .accessibilityAddTraits(selection == choice.value ? .isSelected : [])
                }
            }
        }
    }
}

struct CyberMenuPicker<Value: Hashable>: View {
    var label: String
    @Binding var selection: Value
    var choices: [CyberChoice<Value>]
    var isEnabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CyberControlLabel(label)
            Menu {
                ForEach(choices) { choice in
                    Button(choice.label) {
                        selection = choice.value
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedLabel.uppercased())
                        .font(.caption.weight(.heavy).monospaced())
                        .tracking(0.5)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.heavy))
                }
                .foregroundStyle(isEnabled ? CyberTheme.text : CyberTheme.dim)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    CutCornerRectangle(cut: 6)
                        .fill(CyberTheme.void.opacity(0.66))
                        .overlay(
                            CutCornerRectangle(cut: 6)
                                .stroke(isEnabled ? CyberTheme.deepRed.opacity(0.78) : CyberTheme.dim.opacity(0.50), lineWidth: 1)
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .disabled(!isEnabled)
        }
    }

    private var selectedLabel: String {
        choices.first { $0.value == selection }?.label ?? "None"
    }
}

struct CyberToggle: View {
    var label: String
    @Binding var isOn: Bool
    var isEnabled: Bool = true

    var body: some View {
        Button {
            guard isEnabled else { return }
            isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                CutCornerRectangle(cut: 4)
                    .fill(isOn ? CyberTheme.red : CyberTheme.void.opacity(0.74))
                    .overlay(
                        CutCornerRectangle(cut: 4)
                            .stroke(isOn ? CyberTheme.text.opacity(0.22) : CyberTheme.dim.opacity(0.80), lineWidth: 1)
                    )
                    .frame(width: 34, height: 18)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Rectangle()
                            .fill(isOn ? CyberTheme.text : CyberTheme.muted)
                            .frame(width: 10, height: 10)
                            .padding(.horizontal, 5)
                    }

                Text(label.uppercased())
                    .font(.caption.weight(.heavy).monospaced())
                    .tracking(0.7)
                    .foregroundStyle(isEnabled ? CyberTheme.text : CyberTheme.dim)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.42)
        .disabled(!isEnabled)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct CyberSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var isEnabled: Bool = true

    var body: some View {
        Slider(value: $value, in: range)
            .tint(CyberTheme.red)
            .disabled(!isEnabled)
            .accessibilityLabel("Audio gain")
            .accessibilityValue("\(Int(value * 100)) percent")
    }
}

struct CyberStepper: View {
    var label: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var suffix: String
    var isEnabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CyberControlLabel(label)
            HStack(spacing: 8) {
                Button {
                    guard isEnabled else { return }
                    value = max(range.lowerBound, value - 1)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(CyberButtonStyle(tone: .ghost, isEnabled: isEnabled && value > range.lowerBound))
                .disabled(!isEnabled || value <= range.lowerBound)

                Text("\(value) \(suffix)".uppercased())
                    .font(.caption.weight(.heavy).monospaced())
                    .tracking(0.7)
                    .foregroundStyle(CyberTheme.text)
                    .frame(width: 92)
                    .frame(height: 30)
                    .background(
                        CutCornerRectangle(cut: 6)
                            .fill(CyberTheme.void.opacity(0.70))
                            .overlay(
                                CutCornerRectangle(cut: 6)
                                    .stroke(CyberTheme.deepRed.opacity(0.70), lineWidth: 1)
                            )
                    )

                Button {
                    guard isEnabled else { return }
                    value = min(range.upperBound, value + 1)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(CyberButtonStyle(tone: .secondary, isEnabled: isEnabled && value < range.upperBound))
                .disabled(!isEnabled || value >= range.upperBound)
            }
        }
    }
}

struct CyberControlLabel: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.heavy).monospaced())
            .tracking(0.8)
            .foregroundStyle(CyberTheme.muted)
    }
}

struct GameSettingsRow: View {
    var game: Game
    var trailingSystemImage: String
    var action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "app")
                .foregroundStyle(CyberTheme.red.opacity(0.76))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(game.displayName)
                    .font(.subheadline.weight(.heavy).monospaced())
                Text(game.bundleIdentifier ?? game.executableURL?.path(percentEncoded: false) ?? "No identifier")
                    .font(.caption.monospaced())
                    .foregroundStyle(CyberTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: action) {
                Image(systemName: trailingSystemImage)
            }
            .buttonStyle(CyberButtonStyle(tone: .ghost))
        }
        .padding(8)
        .background(
            CutCornerRectangle(cut: 7)
                .fill(CyberTheme.void.opacity(0.56))
                .overlay(
                    CutCornerRectangle(cut: 7)
                        .stroke(CyberTheme.deepRed.opacity(0.42), lineWidth: 1)
                )
        )
    }
}

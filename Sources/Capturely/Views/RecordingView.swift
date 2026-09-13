import AppKit
import SwiftUI

struct RecordingView: View {
    var status: RecordingDisplayStatus = RecordingDisplayStatus()
    var recordingState: RecordingState = .waitingForGame
    var health: CaptureHealthSnapshot = .empty
    var settings: AppSettings = .defaults
    var isDebugVisible: Bool = false
    var recentEvents: [CaptureDiagnosticEvent] = []
    var startCapture: () -> Void = {}
    var stopCapture: () -> Void = {}
    var saveClip: () -> Void = {
        NotificationCenter.default.post(name: .capturelySaveClipRequested, object: nil)
    }
    var toggleDebug: () -> Void = {}
    var exportDiagnostics: () throws -> URL = { URL(fileURLWithPath: "/tmp/Capturely-Diagnostics.txt") }
    var openClip: (RecentClipDisplay) -> Void = { clip in
        if let clipURL = clip.clipURL {
            NSWorkspace.shared.open(clipURL)
        }
    }
    var recentClips: [RecentClipDisplay]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let clipColumns = [
        GridItem(.adaptive(minimum: 170, maximum: 320), spacing: 12)
    ]

    init(
        status: RecordingDisplayStatus = RecordingDisplayStatus(),
        recordingState: RecordingState = .waitingForGame,
        health: CaptureHealthSnapshot = .empty,
        settings: AppSettings = .defaults,
        isDebugVisible: Bool = false,
        recentEvents: [CaptureDiagnosticEvent] = [],
        recentClips: [RecentClipDisplay] = RecentClipDisplay.samples,
        startCapture: @escaping () -> Void = {},
        stopCapture: @escaping () -> Void = {},
        saveClip: @escaping () -> Void = {
            NotificationCenter.default.post(name: .capturelySaveClipRequested, object: nil)
        },
        toggleDebug: @escaping () -> Void = {},
        exportDiagnostics: @escaping () throws -> URL = { URL(fileURLWithPath: "/tmp/Capturely-Diagnostics.txt") },
        openClip: @escaping (RecentClipDisplay) -> Void = { clip in
            if let clipURL = clip.clipURL {
                NSWorkspace.shared.open(clipURL)
            }
        }
    ) {
        self.status = status
        self.recordingState = recordingState
        self.health = health
        self.settings = settings
        self.isDebugVisible = isDebugVisible
        self.recentEvents = recentEvents
        self.startCapture = startCapture
        self.stopCapture = stopCapture
        self.saveClip = saveClip
        self.toggleDebug = toggleDebug
        self.exportDiagnostics = exportDiagnostics
        self.openClip = openClip
        self.recentClips = recentClips
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("01 / RECORDING")
                            .font(.caption.monospaced().weight(.bold))
                            .tracking(2)
                            .foregroundStyle(CyberTheme.red)
                        Text("Never miss a moment.")
                            .font(.system(size: 36, weight: .black))
                            .fontWidth(.condensed)
                            .tracking(-1.5)
                    }
                    Spacer()
                }
                CyberPanel(padding: 22, cut: 3, isHot: true) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Label("REPLAY BUFFER", systemImage: "arrow.counterclockwise")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .tracking(1.2)
                            Spacer()
                            Text(status.isRecording ? "● LIVE" : "○ STANDBY")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(status.isRecording ? CyberTheme.coral : CyberTheme.muted)
                        }
                        HStack(alignment: .center, spacing: 24) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(status.isRecording ? "REPLAY ARMED" : "READY TO ROLL.")
                                    .font(.system(size: 29, weight: .black)).fontWidth(.condensed)
                                    .foregroundStyle(CyberTheme.red)
                                    .padding(.bottom, 12)
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(String(format: "%02d", displayedBufferSeconds))
                                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                                        .fontWidth(.compressed)
                                        .monospacedDigit()
                                        .tracking(-1)
                                        .foregroundStyle(CyberTheme.red)
                                        .contentTransition(.numericText())
                                    Text("SEC")
                                        .font(.caption.monospaced().weight(.bold))
                                        .foregroundStyle(CyberTheme.muted)
                                }
                                Text("OF \(settings.replayDurationSeconds) SECONDS")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .tracking(1.6)
                                    .foregroundStyle(CyberTheme.muted)
                                HStack(spacing: 4) {
                                    ForEach(0..<14, id: \.self) { index in
                                        Rectangle().fill(CyberTheme.red.opacity(index < 9 ? 0.8 : 0.16))
                                            .frame(width: 8, height: 12)
                                            .rotationEffect(.degrees(18))
                                    }
                                }.padding(.top, 12).accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            heroControls
                        }
                        MeterBar(fraction: status.bufferFillFraction, tint: CyberTheme.red)
                        heroStatus
                    }
                }

                Button {
                        NotificationCenter.default.post(name: .capturelyOpenPageRequested, object: CapturelyPage.settings)
                } label: {
                    HStack(spacing: 20) {
                        metric("PROFILE", value: activePreset.displayName, detail: activePreset.codec.rawValue.uppercased())
                        metric("VIDEO", value: "\(activePreset.maximumHeight)p", detail: "\(activePreset.maximumFramesPerSecond) fps cap")
                        metric("BITRATE", value: activePreset.bitrateDescription, detail: activePreset.storageEstimateDescription)
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(CyberTheme.red)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(CyberTheme.panel)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Configure capture. \(activePreset.displayName), \(activePreset.maximumHeight)p, \(activePreset.maximumFramesPerSecond) frames per second.")
                .help("Configure capture")

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            CyberSectionTitle(title: "Recent clips")
                            Spacer()
                            Button {
                                toggleDebug()
                            } label: {
                                Image(systemName: isDebugVisible ? "stethoscope.circle.fill" : "stethoscope")
                                    .font(.system(size: 13, weight: .heavy))
                                    .frame(width: 18, height: 16)
                            }
                            .buttonStyle(CyberButtonStyle(tone: .ghost))
                            .accessibilityLabel("Diagnostics")
                            .help("Toggle capture diagnostics")
                            Button("View all", systemImage: "arrow.up.right") {
                                NotificationCenter.default.post(name: .capturelyOpenPageRequested, object: CapturelyPage.library)
                            }
                            .buttonStyle(CyberButtonStyle(tone: .ghost))
                        }

                        LazyVGrid(columns: clipColumns, alignment: .leading, spacing: 8) {
                            ForEach(recentClips.prefix(3)) { clip in
                                RecentClipCard(clip: clip) {
                                    openClip(clip)
                                }
                            }
                        }
                        if recentClips.isEmpty {
                            HStack(spacing: 16) {
                                Image(systemName: "film.stack")
                                    .font(.title)
                                    .foregroundStyle(CyberTheme.red)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Nothing saved. Yet.").font(.headline)
                                    Text("Start capture, play, then press \(settings.saveClipHotkey.compactDisplayValue) to save.")
                                        .font(.caption).foregroundStyle(CyberTheme.muted)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        }
                    }
                if isDebugVisible {
                    DebugStatusPanel(
                        health: health,
                        recordingState: recordingState,
                        recentEvents: recentEvents,
                        exportDiagnostics: exportDiagnostics
                    )
                }
            }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(recordingBackground)
    }

    private func performSaveClip() {
        saveClip()
    }

    var displayedBufferSeconds: Int {
        status.isRecording ? Int(min(health.currentBufferDurationSeconds, Double(settings.replayDurationSeconds))) : 0
    }

    private var activePreset: CapturePreset {
        if case .recording(_, let preset) = status.captureState { return preset }
        return CapturePreset.preset(id: settings.selectedPresetID, settings: settings)
    }

    private func metric(_ label: String, value: String, detail: String) -> some View {
            VStack(alignment: .leading, spacing: 5) {
                Text(label).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(CyberTheme.muted)
                Text(value).font(.system(size: 18, weight: .bold)).fontWidth(.condensed).foregroundStyle(CyberTheme.text).lineLimit(1)
                Text(detail).font(.caption2.monospaced()).foregroundStyle(CyberTheme.muted).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(status.subtitle)
                .font(.caption.monospaced())
                .foregroundStyle(CyberTheme.muted)
            RecordingStateLine(recordingState: recordingState)
            if status.isRecording {
                AudioWaveformStrip(health: health, reduceMotion: reduceMotion)
            }
        }
    }

    private var heroControls: some View {
        VStack(spacing: 10) {
            CaptureRunControl(
                isRecording: status.isRecording,
                reduceMotion: reduceMotion,
                startCapture: startCapture,
                stopCapture: stopCapture
            )
            SaveClipControl(
                isEnabled: status.canSaveClip,
                reduceMotion: reduceMotion,
                hotkey: settings.saveClipHotkey,
                saveClip: performSaveClip
            )
        }
    }

    private var recordingBackground: some View {
        CyberTheme.void
    }
}

struct RecordingStateLine: View {
    var recordingState: RecordingState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(recordingState.displayTitle)
                .font(.caption.weight(.heavy).monospaced())
                .tracking(0.4)
            Text(recordingState.detail)
                .font(.caption.monospaced())
                .foregroundStyle(CyberTheme.muted)
                .lineLimit(1)
        }
    }

    private var icon: String {
        switch recordingState {
        case .permissionsNeeded:
            return "lock.shield"
        case .waitingForGame, .stopped:
            return "hourglass"
        case .startingCapture, .bufferWarming:
            return "timer"
        case .recording, .readyToSave:
            return "record.circle"
        case .saving:
            return "square.and.arrow.down"
        case .saved:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .failed:
            return "xmark.octagon"
        }
    }

    private var tint: Color {
        switch recordingState {
        case .failed, .permissionsNeeded:
            return CyberTheme.coral
        case .warning:
            return CyberTheme.warning
        case .saved, .readyToSave:
            return CyberTheme.success
        default:
            return CyberTheme.muted
        }
    }
}

struct RecordingHeader: View {
    var status: RecordingDisplayStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Rectangle()
                    .fill(status.isRecording ? CyberTheme.red : CyberTheme.dim)
                    .frame(width: 8, height: 8)

                Text(status.primaryLine)
                    .font(.caption2.weight(.heavy).monospaced())
                    .tracking(1.0)
                    .foregroundStyle(status.isRecording ? CyberTheme.red : CyberTheme.muted)
            }

            Text(status.title)
                .font(.system(size: 23, weight: .black, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(CyberTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.86)

            Text(status.subtitle)
                .font(.caption.monospaced())
                .foregroundStyle(CyberTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }
}

struct AudioWaveformStrip: View {
    var health: CaptureHealthSnapshot
    var reduceMotion: Bool

    var body: some View {
        HStack(spacing: 7) {
            AudioLevelBars(
                levels: health.recentAudioLevels,
                isActive: health.hasLiveAudioSamples,
                reduceMotion: reduceMotion,
                height: 13
            )

            Text(health.audioMonitorDescription)
                .font(.caption2.monospaced())
                .foregroundStyle(health.hasLiveAudioSamples ? CyberTheme.text.opacity(0.72) : CyberTheme.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(height: 13)
        .accessibilityLabel("Audio monitor")
        .accessibilityValue(health.audioMonitorDescription)
    }
}

struct SaveClipControl: View {
    var isEnabled: Bool
    var reduceMotion: Bool
    var hotkey: SaveClipHotkey = .optionCommandC
    var saveClip: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button {
            guard isEnabled else { return }
            saveClip()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("SAVE REPLAY")
                        .font(.system(size: 18, weight: .black))
                        .fontWidth(.condensed)
                    Text(hotkey.compactDisplayValue)
                        .font(.caption.monospaced().weight(.semibold))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.down.right")
                    .font(.system(size: 24, weight: .light))
            }
            .padding(.horizontal, 18)
            .frame(width: 196, height: 76)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? CyberTheme.void : CyberTheme.muted)
        .background(
            CutCornerRectangle(cut: 12)
                .fill(isEnabled ? CyberTheme.red.opacity(isHovering ? 0.86 : 1) : CyberTheme.panelRaised)
                .overlay(
                    CutCornerRectangle(cut: 12)
                        .stroke(CyberTheme.red.opacity(isEnabled ? 1 : 0.18), lineWidth: 1)
                )
        )
        .disabled(!isEnabled)
        .animation(reduceMotion ? nil : .smooth(duration: 0.14, extraBounce: 0), value: isHovering)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Save replay")
        .accessibilityHint("Save the most recent buffered footage")
    }
}

struct CaptureRunControl: View {
    var isRecording: Bool
    var reduceMotion: Bool
    var startCapture: () -> Void
    var stopCapture: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            if isRecording {
                stopCapture()
            } else {
                startCapture()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isRecording ? "stop.fill" : "record.circle")
                    .foregroundStyle(isRecording ? CyberTheme.coral : CyberTheme.red)
                Text(isRecording ? "Stop capture" : "Start capture")
                    .font(.system(size: 12, weight: .bold))
            }
            .frame(width: 196, height: 38)
        }
        .buttonStyle(.plain)
        .foregroundStyle(CyberTheme.text)
        .background(
            CutCornerRectangle(cut: 3)
                .fill(runTint.opacity(isHovering ? 0.88 : 0.72))
                .overlay(
                    CutCornerRectangle(cut: 3)
                        .stroke(CyberTheme.text.opacity(0.16), lineWidth: 1)
                )
        )
        .animation(reduceMotion ? nil : .smooth(duration: 0.14, extraBounce: 0), value: isHovering)
        .animation(reduceMotion ? nil : .smooth(duration: 0.16, extraBounce: 0), value: isRecording)
        .onHover { isHovering = $0 }
    }

    private var runTint: Color {
        isRecording ? CyberTheme.deepRed : CyberTheme.panelRaised
    }
}

struct QuickSettingDisplay: Identifiable, Equatable, Sendable {
    var id: String { label }
    var label: String
    var value: String
    var systemImage: String
    var meterFraction: Double
    var meterStyle: MeterBar.Style = .neutral
    var audioLevels: [Double] = []
    var tint: Color = .white.opacity(0.68)

    static let compactDefaults = [
        QuickSettingDisplay(label: "Quality", value: "Balanced", systemImage: "slider.horizontal.3", meterFraction: 0.62, tint: .green),
        QuickSettingDisplay(label: "Video", value: "1080p60", systemImage: "display", meterFraction: 0.76),
        QuickSettingDisplay(label: "Audio", value: "Game Audio", systemImage: "waveform", meterFraction: 0.82, meterStyle: .qualityRamp),
        QuickSettingDisplay(label: "Hotkey", value: "⌥⌘C", systemImage: "keyboard", meterFraction: 1.0)
    ]

    static func compact(status: RecordingDisplayStatus, health: CaptureHealthSnapshot, settings: AppSettings = .defaults) -> [QuickSettingDisplay] {
        let preset = CapturePreset.preset(id: settings.selectedPresetID, settings: settings)
        return [
            QuickSettingDisplay(
                label: "Quality",
                value: preset.kind == .storageSaver ? "Performance Mode" : preset.displayName,
                systemImage: "slider.horizontal.3",
                meterFraction: preset.qualityScore,
                tint: qualityTint(for: preset.kind)
            ),
            QuickSettingDisplay(
                label: "Video",
                value: status.isRecording ? "\(preset.maximumHeight)p" : "Standby",
                systemImage: "display",
                meterFraction: status.isRecording ? max(0.18, status.bufferFillFraction) : 0.08,
                tint: CyberTheme.cyan
            ),
            QuickSettingDisplay(
                label: "Audio",
                value: health.audioMonitorDescription,
                systemImage: "waveform",
                meterFraction: health.audioQualityScore,
                meterStyle: .qualityRamp,
                audioLevels: health.recentAudioLevels,
                tint: CyberTheme.cyan.opacity(0.82)
            ),
            QuickSettingDisplay(
                label: "Hotkey",
                value: settings.saveClipHotkey.compactDisplayValue,
                systemImage: "keyboard",
                meterFraction: 1.0,
                tint: CyberTheme.warning.opacity(0.84)
            )
        ]
    }

    private static func qualityTint(for kind: CapturePreset.Kind) -> Color {
        switch kind {
        case .storageSaver:
            return Color(red: 0.20, green: 0.50, blue: 1.0)
        case .balanced:
            return Color(red: 0.18, green: 0.78, blue: 0.42)
        case .editing:
            return Color(red: 1.0, green: 0.25, blue: 0.18)
        case .custom:
            return Color(red: 0.98, green: 0.78, blue: 0.16)
        }
    }
}

struct RecentClipDisplay: Identifiable, Equatable, Sendable {
    var id = UUID()
    var gameName: String
    var experienceName: String
    var time: String
    var duration: String
    var preset: String
    var accent: Color
    var thumbnailURL: URL?
    var clipURL: URL?

    @MainActor static var samples: [RecentClipDisplay] { [
        RecentClipDisplay(gameName: "ROBLOX", experienceName: "Rivals", time: "11:43:29", duration: "60s", preset: "Balanced", accent: CyberTheme.red, thumbnailURL: nil, clipURL: nil),
        RecentClipDisplay(gameName: "ROBLOX", experienceName: "Rivals", time: "11:41:08", duration: "60s", preset: "Balanced", accent: CyberTheme.deepRed, thumbnailURL: nil, clipURL: nil),
        RecentClipDisplay(gameName: "ROBLOX", experienceName: "Rivals", time: "11:39:55", duration: "60s", preset: "Balanced", accent: CyberTheme.dim, thumbnailURL: nil, clipURL: nil)
    ] }

    static func savedNow(status: RecordingDisplayStatus) -> RecentClipDisplay {
        RecentClipDisplay(
            gameName: status.detectedGameLabel,
            experienceName: status.windowTitle ?? "Rivals",
            time: Self.timeFormatter.string(from: Date()),
            duration: "60s",
            preset: "Balanced",
            accent: .red,
            thumbnailURL: nil,
            clipURL: nil
        )
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct RecentClipCard: View {
    var clip: RecentClipDisplay
    var openClip: () -> Void = {}
    @State private var isHovering = false
    @State private var thumbnailImage: NSImage?

    var body: some View {
        Button(action: openClip) {
            content
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(clip.gameName), \(clip.experienceName), \(clip.duration)")
        .help(clip.clipURL == nil ? "Clip unavailable" : "Open clip")
        .task(id: clip.thumbnailURL) {
            await loadThumbnail()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                if let image = thumbnailImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    CutCornerRectangle(cut: 7)
                        .fill(
                            LinearGradient(
                                colors: [
                                    clip.accent.opacity(isHovering ? 0.50 : 0.38),
                                    Color.white.opacity(0.08),
                                    Color.black.opacity(0.48)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .clipShape(CutCornerRectangle(cut: 7))
            .clipped()
            .overlay(
                CutCornerRectangle(cut: 7)
                    .stroke(CyberTheme.red.opacity(0.20), lineWidth: 1)
            )

            Text(clip.gameName)
                .font(.caption2.weight(.heavy).monospaced())
                .tracking(0.7)
                .foregroundStyle(isHovering ? CyberTheme.text : CyberTheme.muted)

            Text(clip.experienceName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CyberTheme.text)
                .lineLimit(1)

            Text("\(clip.time) · \(clip.duration)")
                .font(.caption.monospaced())
                .foregroundStyle(CyberTheme.muted)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 102, alignment: .leading)
        .background(
            CutCornerRectangle(cut: 8)
                .fill(isHovering ? CyberTheme.panelRaised : CyberTheme.panel)
                .overlay(
                    CutCornerRectangle(cut: 8)
                        .stroke((isHovering ? CyberTheme.red : CyberTheme.deepRed).opacity(isHovering ? 0.66 : 0.42), lineWidth: 1)
                )
        )
        .animation(.smooth(duration: 0.14, extraBounce: 0), value: isHovering)
        .onHover { isHovering = $0 }
    }

    @MainActor
    private func loadThumbnail() async {
        guard let data = await ClipPreviewLoader.thumbnailData(at: clip.thumbnailURL) else {
            thumbnailImage = nil
            return
        }
        thumbnailImage = NSImage(data: data)
    }
}

struct DebugStatusPanel: View {
    var health: CaptureHealthSnapshot
    var recordingState: RecordingState
    var recentEvents: [CaptureDiagnosticEvent]
    var exportDiagnostics: () throws -> URL
    @State private var exportMessage: String?

    var body: some View {
        ConsoleCard(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Capture Diagnostics")
                        .font(.caption.weight(.heavy).monospaced())
                        .tracking(0.7)
                        .foregroundStyle(CyberTheme.muted)
                    Spacer()
                    Button {
                        do {
                            let url = try exportDiagnostics()
                            exportMessage = url.lastPathComponent
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } catch {
                            exportMessage = error.localizedDescription
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .buttonStyle(CyberButtonStyle(tone: .ghost))
                    .help("Export capture diagnostics")
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    DebugRow(label: "Detected app", value: health.detectedAppName ?? "None")
                    DebugRow(label: "Capture state", value: recordingState.displayTitle)
                    DebugRow(label: "Segments", value: "\(health.activeSegmentCount)")
                    DebugRow(label: "Buffer", value: String(format: "%.1fs", health.currentBufferDurationSeconds))
                    DebugRow(label: "Frames encoded", value: "\(health.performance.videoSamplesAppended)")
                    DebugRow(label: "Encoder drops", value: "\(health.performance.videoInputBackpressureDrops)")
                    DebugRow(label: "Append cost", value: String(format: "%.2f ms (sampled)", health.performance.averageVideoAppendMilliseconds))
                    DebugRow(label: "Segment finish", value: String(format: "%.1f ms", health.performance.lastSegmentFlushMilliseconds))
                    DebugRow(label: "Last video", value: Self.timestamp(health.lastVideoSampleAt))
                    DebugRow(label: "Last audio", value: Self.timestamp(health.lastAudioSampleAt))
                    DebugRow(label: "Audio tracks", value: health.audioStatus.rawValue)
                    DebugRow(label: "Audio level", value: Self.percent(health.audioLevel))
                    DebugRow(label: "Audio quality", value: Self.percent(health.audioQualityScore))
                    DebugRow(label: "Audio format", value: Self.audioFormat(health))
                    DebugRow(label: "Save status", value: Self.saveStatus(health.lastSaveResult))
                    DebugRow(label: "Output folder", value: health.outputFolder?.path(percentEncoded: false) ?? "Unset")
                    DebugRow(label: "Last error", value: health.lastError ?? "None")
                }
                if let exportMessage {
                    Text(exportMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Divider()
                    .overlay(CyberTheme.deepRed.opacity(0.72))
                Text("Recent Events")
                    .font(.caption2.weight(.semibold).monospaced())
                    .foregroundStyle(CyberTheme.muted)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(recentEvents.suffix(8)) { event in
                        HStack(spacing: 6) {
                            Text(Self.eventTimestamp(event.date))
                                .font(.caption2.monospaced())
                                .foregroundStyle(CyberTheme.muted)
                            Text(event.kind.rawValue)
                                .font(.caption2.weight(.semibold).monospaced())
                            Text(event.message)
                                .font(.caption2)
                                .foregroundStyle(CyberTheme.muted)
                                .lineLimit(1)
                        }
                    }
                    if recentEvents.isEmpty {
                        Text("No events yet")
                            .font(.caption2)
                            .foregroundStyle(CyberTheme.muted)
                    }
                }
            }
        }
    }

    private static func timestamp(_ date: Date?) -> String {
        guard let date else { return "None" }
        return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .medium)
    }

    private static func saveStatus(_ result: SaveResult?) -> String {
        switch result {
        case .saved:
            return "Saved"
        case .failed(let message):
            return "Failed: \(message)"
        case nil:
            return "Ready"
        }
    }

    private static func eventTimestamp(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .medium)
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }

    private static func audioFormat(_ health: CaptureHealthSnapshot) -> String {
        let sampleRate = health.audioSampleRate.map { "\(Int($0.rounded())) Hz" } ?? "Unknown Hz"
        let channels = health.audioChannelCount > 0 ? "\(health.audioChannelCount) ch" : "Unknown ch"
        return "\(sampleRate), \(channels)"
    }
}

struct DebugRow: View {
    var label: String
    var value: String

    var body: some View {
        GridRow {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CyberTheme.muted)
            Text(value)
                .font(.caption2.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

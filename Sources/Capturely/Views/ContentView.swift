import AppKit
import SwiftUI

enum CapturelyPage: String, CaseIterable, Identifiable {
    case recording = "Recording"
    case library = "Library"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .recording:
            return "record.circle"
        case .library:
            return "film.stack"
        case .settings:
            return "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var backend: CaptureBackend
    @State private var selectedPage: CapturelyPage = .recording
    @State private var isOnboardingSettingsOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var navigation

    var body: some View {
        Group {
            if backend.settings.hasCompletedOnboarding || isOnboardingSettingsOpen {
                mainInterface
            } else {
                OnboardingView(
                    settings: backend.settings,
                    permissionSummary: backend.permissionSummary,
                    completeOnboarding: {
                        backend.completeOnboarding()
                        isOnboardingSettingsOpen = false
                        selectedPage = .recording
                    },
                    openSettings: {
                        isOnboardingSettingsOpen = true
                        selectedPage = .settings
                    },
                    requestScreenCapturePermission: backend.requestScreenCapturePermission,
                    requestMicrophonePermission: backend.requestMicrophonePermission,
                    requestNotificationsPermission: backend.requestNotificationsPermission,
                    setReplayDuration: backend.setReplayDuration,
                    setSaveClipHotkey: backend.setSaveClipHotkey,
                    setSelectedPreset: backend.setSelectedPreset,
                    chooseClipLibrary: backend.chooseClipLibrary,
                    resetClipLibrary: backend.resetClipLibrary
                )
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .capturelyOpenPageRequested)) { notification in
            if let page = notification.object as? CapturelyPage {
                withAnimation(.smooth(duration: 0.18, extraBounce: 0)) {
                    selectedPage = page
                }
            }
        }
    }

    private var mainInterface: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(alignment: .center, spacing: 10) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(CyberTheme.red)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.top, 54)
                .padding(.bottom, 20)

                VStack(spacing: 4) {
                    ForEach(CapturelyPage.allCases) { page in
                        Button {
                            withAnimation(reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.18)) {
                                selectedPage = page
                            }
                        } label: {
                            Image(systemName: page.systemImage).font(.system(size: 24, weight: .light))
                            .foregroundStyle(selectedPage == page ? CyberTheme.red : CyberTheme.muted)
                            .frame(width: 48, height: 48)
                            .background(selectedPage == page ? CyberTheme.red.opacity(0.08) : .clear)
                            .overlay(alignment: .leading) {
                                if selectedPage == page {
                                    Rectangle().fill(CyberTheme.red).frame(width: 3, height: 34)
                                        .shadow(color: CyberTheme.red.opacity(0.5), radius: 6)
                                        .matchedGeometryEffect(id: "selection", in: navigation)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(page.rawValue)
                        .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
                        .help(page.rawValue)
                    }
                }
                .padding(.horizontal, 8)

                Spacer(minLength: 0)
                Button {
                    NotificationCenter.default.post(name: .capturelyToggleOverlayRequested, object: nil)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "rectangle.on.rectangle").font(.system(size: 20))
                        Text("⌥⌘O").font(.caption.monospaced())
                    }.foregroundStyle(CyberTheme.red).frame(width: 48, height: 56)
                }
                .buttonStyle(.plain)
                .help("Toggle in-game overlay · ⌥⌘O")
                .accessibilityLabel("Toggle in-game overlay")
                .padding(.bottom, 24)
            }
            .frame(
                minWidth: CapturelyWindowMetrics.sidebarMinWidth,
                idealWidth: CapturelyWindowMetrics.sidebarIdealWidth,
                maxWidth: CapturelyWindowMetrics.sidebarMaxWidth
            )
            .background(
                CyberTheme.void
                    .overlay(alignment: .trailing) {
                        GeometryReader { geometry in
                            Path { path in
                                let x = geometry.size.width
                                let h = geometry.size.height
                                path.move(to: CGPoint(x: x, y: 34))
                                path.addLine(to: CGPoint(x: x, y: 138))
                                path.addLine(to: CGPoint(x: x - 7, y: 145))
                                path.addLine(to: CGPoint(x: x - 7, y: h - 120))
                                path.addLine(to: CGPoint(x: x, y: h - 113))
                                path.addLine(to: CGPoint(x: x, y: h))
                            }.stroke(CyberTheme.red.opacity(0.45), lineWidth: 1)
                        }.allowsHitTesting(false)
                    }
            )

            VStack(spacing: 0) {
                detailView
                    .id(selectedPage)
                    .transition(.opacity.combined(with: .offset(x: reduceMotion ? 0 : 10)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let message = backend.libraryMessage {
                    Text(message).font(.caption).foregroundStyle(CyberTheme.muted).padding(8)
                }
                PerformancePanel(backend: backend)
            }.padding(.top, 28)
        }
        .background(CyberTheme.void)
        .foregroundStyle(CyberTheme.text)
        .transaction { if reduceMotion { $0.animation = nil } }
        .sheet(item: $backend.editingClip) { clip in
            ClipEditorView(clip: clip) { start, end, gains in
                try await backend.saveEditedClip(clip, start: start, end: end, gains: gains)
            }
        }
        .overlay(alignment: .top) {
            CyberTitlebarRail()
                .frame(height: 34)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            CyberWindowControls()
                .padding(.leading, 12)
                .padding(.top, 11)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedPage {
        case .recording:
            RecordingView(
                status: backend.status,
                recordingState: backend.recordingState,
                health: backend.health,
                settings: backend.settings,
                isDebugVisible: backend.isDebugVisible,
                recentEvents: backend.recentEvents,
                recentClips: backend.recentClips,
                startCapture: backend.startCaptureRequested,
                stopCapture: backend.stopCaptureRequested,
                saveClip: backend.saveClipRequested,
                toggleDebug: backend.toggleDebugVisibility,
                exportDiagnostics: backend.exportDiagnostics
            )
        case .library:
            LibraryView(
                clips: backend.clips,
                reveal: backend.reveal,
                play: backend.play,
                export: backend.export,
                share: backend.share,
                delete: backend.delete,
                edit: { backend.editingClip = $0 },
                toggleStar: backend.toggleStar,
                isBusy: backend.isLibraryBusy
            )
        case .settings:
            SettingsView(
                settings: backend.settings,
                permissionSummary: backend.permissionSummary,
                displayOptions: backend.displayOptions,
                microphoneOptions: backend.microphoneOptions,
                isLocked: backend.isCaptureConfigurationLocked,
                games: backend.games,
                scannedApplications: backend.scannedApplications,
                message: backend.gameRegistryMessage,
                setSelectedPreset: backend.setSelectedPreset,
                setReplayDuration: backend.setReplayDuration,
                setCaptureSourceMode: backend.setCaptureSourceMode,
                setSelectedDisplayID: backend.setSelectedDisplayID,
                setRecordsSystemAudio: backend.setRecordsSystemAudio,
                setRecordsMicrophone: backend.setRecordsMicrophone,
                setMicrophoneDeviceID: backend.setMicrophoneDeviceID,
                setSaveClipHotkey: backend.setSaveClipHotkey,
                setCustomPreset: backend.setCustomPreset,
                setSystemAudioMix: backend.setSystemAudioMix,
                setMicrophoneMix: backend.setMicrophoneMix,
                requestScreenCapturePermission: backend.requestScreenCapturePermission,
                chooseClipLibrary: backend.chooseClipLibrary,
                resetClipLibrary: backend.resetClipLibrary,
                refreshCaptureDevices: {
                    Task { await backend.refreshCaptureDevices() }
                },
                addRunningApp: backend.addRunningApp,
                chooseApp: backend.addChosenApp,
                scanApplications: backend.scanApplications,
                addScannedApplication: backend.addScannedApplication,
                removeGame: backend.removeGame,
                setAutomaticGameSessions: backend.setAutomaticGameSessions,
                setKeepsEditableAudio: backend.setKeepsEditableAudio,
                setLibraryLimitGB: backend.setLibraryLimitGB,
                setLogsGameProcess: backend.setLogsGameProcess
            )
        }
    }
}

private struct CyberTitlebarRail: View {
    var body: some View {
        Rectangle()
            .fill(CyberTheme.void)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                CyberTheme.deepRed.opacity(0.0),
                                CyberTheme.red.opacity(0.52),
                                CyberTheme.deepRed.opacity(0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 5) {
                    ForEach(0..<9, id: \.self) { _ in
                        Rectangle()
                            .fill(CyberTheme.red.opacity(0.45))
                            .frame(width: 12, height: 2)
                    }
                }
                .padding(.top, 7)
                .padding(.trailing, 14)
            }
    }
}

private struct CyberWindowControls: View {
    var body: some View {
        HStack(spacing: 7) {
            WindowCommandButton(
                accessibilityLabel: "Hide window",
                color: CyberTheme.coral,
                symbol: "xmark",
                action: closeWindow
            )
            WindowCommandButton(
                accessibilityLabel: "Minimize window",
                color: CyberTheme.warning,
                symbol: "minus",
                action: minimizeWindow
            )
            WindowCommandButton(
                accessibilityLabel: "Zoom window",
                color: CyberTheme.success,
                symbol: "plus",
                action: zoomWindow
            )
        }
    }

    private func closeWindow() {
        CapturelyWindowPresenter.hideMainWindow()
    }

    private func minimizeWindow() {
        activeWindow?.miniaturize(nil)
    }

    private func zoomWindow() {
        activeWindow?.zoom(nil)
    }

    private var activeWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow
    }
}

private struct WindowCommandButton: View {
    var accessibilityLabel: String
    var color: Color
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(CyberTheme.void.opacity(0.78))
                .frame(width: 17, height: 14)
                .background(
                    CutCornerRectangle(cut: 4)
                        .fill(color.opacity(0.92))
                        .overlay(
                            CutCornerRectangle(cut: 4)
                                .stroke(color.opacity(0.95), lineWidth: 1)
                        )
                )
                .background(
                    CutCornerRectangle(cut: 4)
                        .fill(CyberTheme.deepRed.opacity(0.45))
                        .offset(x: 2, y: 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }
}

struct SidebarRow: View {
    var page: CapturelyPage
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: page.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? CyberTheme.void : CyberTheme.muted)
                .frame(width: 18)

            Text(page.rawValue)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? CyberTheme.void : CyberTheme.muted)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            CutCornerRectangle(cut: 6)
                .fill(isSelected ? CyberTheme.red : Color.clear)
                .overlay(
                    CutCornerRectangle(cut: 6)
                        .stroke(isSelected ? CyberTheme.red.opacity(0.72) : Color.clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
    }
}

struct SidebarStatusFooter: View {
    var status: RecordingDisplayStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Rectangle()
                    .fill(status.isRecording ? CyberTheme.red : CyberTheme.dim)
                    .frame(width: 7, height: 7)
                Text(status.isRecording ? "Buffering" : "Standby")
                    .font(.caption.weight(.heavy).monospaced())
                    .tracking(0.5)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 5) {
                SidebarStatusLine(systemImage: "timer", text: status.bufferLengthDescription)
                SidebarStatusLine(systemImage: "mic", text: status.micStatusDescription)
                SidebarStatusLine(systemImage: "internaldrive", text: status.storageFreeDescription)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CutCornerRectangle(cut: 8)
                .fill(CyberTheme.panel)
                .overlay(
                    CutCornerRectangle(cut: 8)
                        .stroke(CyberTheme.deepRed.opacity(0.58), lineWidth: 1)
                )
        )
    }
}

struct SidebarStatusLine: View {
    var systemImage: String
    var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CyberTheme.red.opacity(0.78))
                .frame(width: 14)

            Text(text)
                .font(.caption2.monospaced())
                .foregroundStyle(CyberTheme.muted)
                .lineLimit(1)
        }
        .frame(height: 15, alignment: .leading)
    }
}

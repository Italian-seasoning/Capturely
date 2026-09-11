import SwiftUI
import Sparkle

@main
struct CapturelyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var hotkeyService = HotkeyService()
    @StateObject private var backend = CaptureBackend()
    @StateObject private var gameOverlay = GameOverlayController()
    private let updater = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup("Capturely", id: "main") {
            ContentView()
                .environmentObject(backend)
                .frame(
                    minWidth: CapturelyWindowMetrics.minimumContentWidth,
                    idealWidth: CapturelyWindowMetrics.idealContentWidth,
                    minHeight: CapturelyWindowMetrics.minimumContentHeight,
                    idealHeight: CapturelyWindowMetrics.idealContentHeight
                )
                .background(FixedWindowConfigurator())
                .task {
                    await backend.start()
                }
                .onReceive(NotificationCenter.default.publisher(for: .capturelySaveClipRequested)) { _ in
                    backend.saveClipRequested()
                }
                .onReceive(NotificationCenter.default.publisher(for: .capturelyToggleOverlayRequested)) { _ in
                    gameOverlay.toggle(backend: backend)
                }
                .onReceive(NotificationCenter.default.publisher(for: .capturelySaveDurationRequested)) { notification in
                    if let seconds = notification.object as? Int { backend.saveReplay(seconds: seconds) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .capturelyReplaySaved)) { notification in
                    if let clip = notification.object as? Clip { gameOverlay.showSaved(clip: clip) }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    backend.stopProcessLogging()
                    hotkeyService.stop()
                }
                .overlay(alignment: .bottom) {
                    if let message = hotkeyService.registrationError {
                        Text(message).font(.caption).padding(10).background(CyberTheme.panel).foregroundStyle(CyberTheme.warning)
                    }
                }
                .task {
                    hotkeyService.start(hotkey: backend.settings.saveClipHotkey) {
                        NotificationCenter.default.post(name: .capturelySaveClipRequested, object: nil)
                    }
                }
                .onChange(of: backend.settings.saveClipHotkey) { _, hotkey in
                    hotkeyService.start(hotkey: hotkey) {
                        NotificationCenter.default.post(name: .capturelySaveClipRequested, object: nil)
                    }
                }
        }

        MenuBarExtra(menuTitle, systemImage: backend.status.isRecording ? "record.circle.fill" : "record.circle") {
            Text(backend.recordingState.displayTitle)
            if let detectedApp = backend.health.detectedAppName {
                Text(detectedApp)
            }
            Divider()
            Button("Save Clip") {
                NotificationCenter.default.post(name: .capturelySaveClipRequested, object: nil)
            }
            .disabled(!backend.status.canSaveClip)
            Divider()
            Button(gameOverlay.isVisible ? "Hide In-Game Overlay (⌥⌘O)" : "Show In-Game Overlay (⌥⌘O)") {
                gameOverlay.toggle(backend: backend)
            }
            Button("Open Capturely") {
                CapturelyWindowPresenter.showMainWindow()
            }
            Button("Open Library") {
                open(.library)
            }
            Button("Open Settings") {
                open(.settings)
            }
            Button("Check for Updates…") {
                updater.checkForUpdates(nil)
            }
            Button("Export Diagnostics") {
                do {
                    let url = try backend.exportDiagnostics()
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } catch {
                    backend.toggleDebugVisibility()
                }
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var menuTitle: String {
        backend.status.isRecording ? "Capturely REC" : "Capturely"
    }

    private func open(_ page: CapturelyPage) {
        CapturelyWindowPresenter.showMainWindow()
        NotificationCenter.default.post(name: .capturelyOpenPageRequested, object: page)
    }
}

extension Notification.Name {
    static let capturelySaveClipRequested = Notification.Name("capturely.saveClipRequested")
    static let capturelyOpenPageRequested = Notification.Name("capturely.openPageRequested")
    static let capturelyToggleOverlayRequested = Notification.Name("capturely.toggleOverlayRequested")
    static let capturelySaveDurationRequested = Notification.Name("capturely.saveDurationRequested")
    static let capturelyReplaySaved = Notification.Name("capturely.replaySaved")
}

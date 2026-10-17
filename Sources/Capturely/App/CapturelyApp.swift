import SwiftUI
import Sparkle
import Combine

@main
struct CapturelyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var hotkeyService = HotkeyService()
    // Child views observe telemetry; owning it here must not invalidate the scenes.
    @State private var backend = CaptureBackend()
    @StateObject private var gameOverlay = GameOverlayController()
    private let updater = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        Window("Capturely", id: "main") {
            CapturelyWindowContent(backend: backend, hotkeyService: hotkeyService, gameOverlay: gameOverlay)
        }

        MenuBarExtra {
            CapturelyMenuContent(backend: backend, gameOverlay: gameOverlay, updater: updater)
        } label: {
            CapturelyMenuLabel(backend: backend)
        }
    }
}

struct CapturelyWindowContent: View {
    @ObservedObject var backend: CaptureBackend
    @ObservedObject var hotkeyService: HotkeyService
    let gameOverlay: GameOverlayController

    var body: some View {
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
            .onReceive(NotificationCenter.default.publisher(for: .capturelyBookmarkRequested)) { _ in
                backend.bookmarkMoment()
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
}

struct CapturelyMenuContent: View {
    @ObservedObject var backend: CaptureBackend
    @ObservedObject var gameOverlay: GameOverlayController
    let updater: SPUStandardUpdaterController

    var body: some View {
        Group {
            Text(backend.recordingState.displayTitle)
            if let detectedApp = backend.health.detectedAppName {
                Text(detectedApp)
            }
            Divider()
            Button("Save Clip") {
                NotificationCenter.default.post(name: .capturelySaveClipRequested, object: nil)
            }
            .disabled(!backend.status.canSaveClip)
            Button("Bookmark moment (⌃⌥⌘B)") { backend.bookmarkMoment() }
                .disabled(!backend.status.isRecording)
            if let time = backend.lastBookmarkAt, backend.status.isRecording {
                Text("Bookmarked at \(time.formatted(date: .omitted, time: .standard))")
            }
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

    private func open(_ page: CapturelyPage) {
        CapturelyWindowPresenter.showMainWindow()
        NotificationCenter.default.post(name: .capturelyOpenPageRequested, object: page)
    }
}

struct CapturelyMenuLabel: View {
    let recordingChanges: AnyPublisher<Bool, Never>
    @State private var isRecording = false

    init(backend: CaptureBackend) {
        self.init(status: backend.$status.eraseToAnyPublisher())
    }

    init(status: AnyPublisher<RecordingDisplayStatus, Never>) {
        recordingChanges = status.map(\.isRecording).removeDuplicates().eraseToAnyPublisher()
    }

    var body: some View {
        Label(isRecording ? "Capturely REC" : "Capturely",
              systemImage: isRecording ? "record.circle.fill" : "record.circle")
            .onReceive(recordingChanges) { isRecording = $0 }
    }
}

extension Notification.Name {
    static let capturelySaveClipRequested = Notification.Name("capturely.saveClipRequested")
    static let capturelyOpenPageRequested = Notification.Name("capturely.openPageRequested")
    static let capturelyToggleOverlayRequested = Notification.Name("capturely.toggleOverlayRequested")
    static let capturelySaveDurationRequested = Notification.Name("capturely.saveDurationRequested")
    static let capturelyReplaySaved = Notification.Name("capturely.replaySaved")
    static let capturelyBookmarkRequested = Notification.Name("capturely.bookmarkRequested")
}

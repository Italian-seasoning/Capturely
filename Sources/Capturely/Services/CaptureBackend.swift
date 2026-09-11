import AppKit
import AVFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class CaptureBackend: ObservableObject {
    @Published private(set) var status = RecordingDisplayStatus(captureState: .idle, windowTitle: nil, isWindowLocked: false)
    @Published private(set) var recordingState: RecordingState = .waitingForGame
    @Published private(set) var health = CaptureHealthSnapshot.empty
    @Published private(set) var recentClips: [RecentClipDisplay] = []
    @Published private(set) var clips: [Clip] = []
    @Published private(set) var permissionSummary = PermissionSummary(microphoneGranted: false, screenCaptureStatus: "Not checked")
    @Published private(set) var recentEvents: [CaptureDiagnosticEvent] = []
    @Published private(set) var lastDiagnosticsExportURL: URL?
    @Published private(set) var games: [Game] = []
    @Published private(set) var scannedApplications: [Game] = []
    @Published private(set) var gameRegistryMessage: String?
    @Published private(set) var settings: AppSettings = .defaults
    @Published private(set) var displayOptions: [CaptureDisplayOption] = []
    @Published private(set) var microphoneOptions: [MicrophoneDeviceOption] = []
    @Published private(set) var isCaptureConfigurationLocked = false
    @Published var isDebugVisible = false
    @Published private(set) var resourceUsage = ResourceUsage.empty
    @Published private(set) var isLibraryBusy = false
    @Published private(set) var libraryMessage: String?
    @Published var editingClip: Clip?
    private var resourceSampler = ResourceSampler()
    private let gameProcessLogger = GameProcessLogger()
    @Published private(set) var gameProcessSample = GameProcessSample()
    private var suppressedGamePID: pid_t?

    private let appPaths: AppPaths
    private let processMonitor: ProcessMonitor
    private let permissionService: PermissionService
    private let captureCoordinator: CaptureCoordinator
    private let notificationService: NotificationService
    private let gameRegistryStore: GameRegistryStore
    private let appSettingsStore: AppSettingsStore
    private let clipIndexStore: ClipIndexStore
    private var currentMatch: RunningGameMatch?
    private var isManualCaptureActive = false
    private var isSaveInProgress = false
    private var lastAcceptedSaveRequestAt: Date?
    private var lastSuccessfulSaveCapturedAt: Date?
    private var lastSaveResult: SaveResult?
    private var lastError: String?
    private var healthMonitorTask: Task<Void, Never>?
    private var settingsSaveTask: Task<Void, Never>?
    private var hasReportedBufferReady = false
    private var hasStarted = false
    private var hasActivatedCaptureRuntime = false
    private var isPerformanceFallbackActive = false
    private var isStartingManualCapture = false

    init(
        appPaths: AppPaths = AppPaths(),
        processMonitor: ProcessMonitor = ProcessMonitor(),
        permissionService: PermissionService = PermissionService(),
        notificationService: NotificationService = NotificationService()
    ) {
        self.appPaths = appPaths
        self.processMonitor = processMonitor
        self.permissionService = permissionService
        self.notificationService = notificationService

        let applicationSupport = (try? appPaths.applicationSupportDirectory)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Capturely", isDirectory: true)
        let replayWriter = ReplaySegmentWriter(
            directory: applicationSupport.appendingPathComponent("ReplaySegments", isDirectory: true),
            maximumDurationSeconds: Self.replayRetentionSeconds(forReplayDuration: AppSettings.defaults.replayDurationSeconds)
        )
        self.captureCoordinator = CaptureCoordinator(replaySegmentWriter: replayWriter)
        self.gameRegistryStore = GameRegistryStore(fileURL: applicationSupport.appendingPathComponent("games.json"))
        self.appSettingsStore = AppSettingsStore(fileURL: applicationSupport.appendingPathComponent("settings.json"))
        self.clipIndexStore = ClipIndexStore(fileURL: applicationSupport.appendingPathComponent("clips.json"))
        self.captureCoordinator.onDiagnosticEvent = { [weak self] event in
            Task { @MainActor in
                self?.record(event)
            }
        }
        replayWriter.onAudioMonitorUpdated = { [weak self] in
            Task { @MainActor in
                self?.updateHealthOnly(lastError: self?.lastError)
            }
        }
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        do {
            settings = try appSettingsStore.load()
            configureReplayRetention()
            games = ApplicationScanner.merge(existing: Self.defaultGames, incoming: try gameRegistryStore.load())
            try gameRegistryStore.save(games)
            clips = try await clipIndexStore.loadAsync()
            recentClips = clips.map(RecentClipDisplay.init(clip:))

            await permissionService.refresh()
            permissionSummary = permissionService.summary

            processMonitor.onMatchChanged = { [weak self] match in
                Task { @MainActor in
                    await self?.handleMatchChanged(match)
                }
            }
            if Self.shouldActivateCaptureRuntime(hasCompletedOnboarding: settings.hasCompletedOnboarding) {
                await activateCaptureRuntime()
            }
            updateDerivedState()
            startHealthMonitoring()
        } catch {
            lastError = error.localizedDescription
            captureFailed(error.localizedDescription, windowTitle: nil)
        }
    }

    func saveClipRequested() {
        Task {
            await saveClip()
        }
    }

    func saveReplay(seconds: Int) {
        guard [15, 30, 60].contains(seconds) else { return }
        Task { await saveClip(duration: seconds) }
    }

    func setAutomaticGameSessions(_ enabled: Bool) {
        settings.automaticGameSessions = enabled
        scheduleSettingsSave()
        Task {
            if enabled { await handleMatchChanged(processMonitor.currentMatch) }
            else if !isManualCaptureActive { await captureCoordinator.stop(); updateDerivedState() }
        }
    }

    func setKeepsEditableAudio(_ enabled: Bool) {
        settings.keepsEditableAudio = enabled
        scheduleSettingsSave()
    }
    func setLogsGameProcess(_ enabled: Bool) {
        settings.logsGameProcess = enabled
        scheduleSettingsSave()
        if !enabled { gameProcessLogger.stop(); gameProcessSample = GameProcessSample(status: "Process logging is off") }
    }
    func stopProcessLogging() { gameProcessLogger.stop() }
    func revealProcessLog() {
        if let url = gameProcessSample.logURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func setLibraryLimitGB(_ value: Int) {
        settings.libraryLimitGB = min(1000, max(0, value))
        scheduleSettingsSave()
        Task { await enforceLibraryLimit() }
    }

    func startCaptureRequested() {
        guard Self.shouldStartManualCapture(hasCompletedOnboarding: settings.hasCompletedOnboarding) else { return }
        Task {
            suppressedGamePID = nil
            if settings.captureSourceMode == .gameWindow {
                guard let match = currentMatch else {
                    gameRegistryMessage = "Open a configured game before starting Game Window capture"
                    recordingState = .waitingForGame
                    return
                }
                await handleMatchChanged(match, manuallyRequested: true)
            } else {
                await startManualCapture()
            }
        }
    }

    func stopCaptureRequested() {
        suppressedGamePID = currentMatch?.processIdentifier
        Task {
            await stopManualCapture()
        }
    }

    func toggleDebugVisibility() {
        isDebugVisible.toggle()
    }

    func refreshCaptureDevices() async {
        guard canChangeCaptureConfiguration() else { return }
        displayOptions = await DisplayScanner().scanDisplays()
        microphoneOptions = Self.microphoneDeviceOptions()
        if settings.selectedDisplayID == nil {
            settings.selectedDisplayID = displayOptions.first?.displayID
            scheduleSettingsSave()
        }
    }

    func setSelectedPreset(_ presetID: CapturePreset.ID) {
        updateSettings { $0.selectedPresetID = presetID }
    }

    func setReplayDuration(_ seconds: Int) {
        updateSettings { $0.replayDurationSeconds = seconds }
    }

    func setSaveClipHotkey(_ hotkey: SaveClipHotkey) {
        updateSettings {
            $0.saveClipHotkey = hotkey
            $0.saveClipHotkeyDisplayValue = hotkey.displayValue
        }
    }

    func setCustomPreset(_ customPreset: CustomCapturePresetSettings) {
        updateSettings { $0.customPreset = customPreset.performanceSafe }
    }

    func setSystemAudioMix(_ value: Double) {
        updateSettings { $0.systemAudioMix = Self.clampedMix(value) }
    }

    func setMicrophoneMix(_ value: Double) {
        updateSettings { $0.microphoneMix = Self.clampedMix(value) }
    }

    func completeOnboarding() {
        guard !settings.hasCompletedOnboarding else { return }
        settings.hasCompletedOnboarding = true
        scheduleSettingsSave()
        Task {
            await activateCaptureRuntime()
        }
    }

    func setCaptureSourceMode(_ mode: CaptureSourceMode) {
        updateSettings { $0.captureSourceMode = mode }
    }

    func setSelectedDisplayID(_ displayID: UInt32?) {
        updateSettings { $0.selectedDisplayID = displayID }
    }

    func setRecordsSystemAudio(_ enabled: Bool) {
        updateSettings { $0.recordsSystemAudio = enabled }
    }

    func setRecordsMicrophone(_ enabled: Bool) {
        guard canChangeCaptureConfiguration() else { return }
        Task {
            if enabled {
                await permissionService.requestMicrophone()
                permissionSummary = permissionService.summary
            }
            updateSettings { $0.recordsMicrophone = enabled && permissionSummary.microphoneGranted }
        }
    }

    func requestScreenCapturePermission() {
        guard canChangeCaptureConfiguration() else { return }
        Task {
            await permissionService.requestScreenCapture()
            permissionSummary = permissionService.summary
            if permissionSummary.screenCaptureGranted {
                gameRegistryMessage = "Screen Recording ready"
            } else {
                gameRegistryMessage = "Grant Screen Recording in System Settings, then relaunch Capturely"
                openScreenRecordingSettings()
            }
            updateDerivedState(windowTitle: currentMatch?.detectedAppName, isWindowLocked: captureCoordinator.state.isRecording)
        }
    }

    func requestMicrophonePermission() {
        guard canChangeCaptureConfiguration() else { return }
        Task {
            await permissionService.requestMicrophone()
            permissionSummary = permissionService.summary
            updateSettings { $0.recordsMicrophone = permissionSummary.microphoneGranted }
            if !permissionSummary.microphoneGranted && !permissionSummary.microphoneCanRequest {
                openPrivacySettings(pane: "Privacy_Microphone")
            }
        }
    }

    func requestNotificationsPermission() {
        Task {
            await permissionService.requestNotifications()
            permissionSummary = permissionService.summary
            if !permissionSummary.notificationsGranted && !permissionSummary.notificationsCanRequest {
                openNotificationSettings()
            }
        }
    }

    func setMicrophoneDeviceID(_ id: String?) {
        updateSettings { $0.microphoneDeviceID = id }
    }

    func chooseClipLibrary() {
        guard canChangeCaptureConfiguration() else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        updateSettings { $0.clipLibraryURL = url }
    }

    func resetClipLibrary() {
        updateSettings { $0.clipLibraryURL = nil }
    }

    func addRunningApp() {
        guard canChangeCaptureConfiguration() else { return }
        let candidates = NSWorkspace.shared.runningApplications.compactMap { app -> Game? in
            let snapshot = RunningAppSnapshot(
                processIdentifier: app.processIdentifier,
                bundleIdentifier: app.bundleIdentifier,
                executableURL: app.executableURL,
                localizedName: app.localizedName
            )
            return ApplicationScanner.game(fromRunningAppSnapshot: snapshot)
        }

        guard let game = candidates.first(where: { $0.displayName.localizedCaseInsensitiveContains("roblox") }) ?? candidates.first(where: { $0.bundleIdentifier != Bundle.main.bundleIdentifier }) else {
            gameRegistryMessage = "No running app found"
            return
        }

        addGame(game)
    }

    func addChosenApp() {
        guard canChangeCaptureConfiguration() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            addGame(try ApplicationScanner.game(fromApplicationURL: url))
        } catch {
            gameRegistryMessage = "Could not add app: \(error.localizedDescription)"
        }
    }

    func scanApplications() {
        guard canChangeCaptureConfiguration() else { return }
        scannedApplications = ApplicationScanner().scanApplicationDirectories()
        gameRegistryMessage = scannedApplications.isEmpty ? "No apps found" : "Found \(scannedApplications.count) apps"
    }

    func addScannedApplication(_ game: Game) {
        guard canChangeCaptureConfiguration() else { return }
        addGame(game)
    }

    func removeGame(_ game: Game) {
        guard canChangeCaptureConfiguration() else { return }
        games.removeAll { $0.id == game.id || $0.matchesIdentity(of: game) }
        persistGamesAndRestartMonitor(message: "Removed \(game.displayName)")
    }

    @discardableResult
    func exportDiagnostics() throws -> URL {
        let fileURL = try writeDiagnosticsReport(prefix: "Capturely-Diagnostics")
        record(.init(kind: .appDetected, message: "Diagnostics exported: \(fileURL.path(percentEncoded: false))"))
        return fileURL
    }

    @discardableResult
    private func writeDiagnosticsReport(prefix: String) throws -> URL {
        let directory = try appPaths.applicationSupportDirectory.appendingPathComponent("Diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("\(prefix)-\(Self.fileTimestamp.string(from: Date())).txt")
        let report = CaptureDiagnosticsReport(
            generatedAt: Date(),
            detectedAppName: health.detectedAppName,
            recordingState: recordingState,
            permissionSummary: permissionSummary,
            health: health,
            recentEvents: recentEvents
        )
        try report.renderText().write(to: fileURL, atomically: true, encoding: .utf8)
        lastDiagnosticsExportURL = fileURL
        return fileURL
    }

    func reveal(_ clip: Clip) {
        NSWorkspace.shared.activateFileViewerSelecting([clip.clipURL])
    }

    func play(_ clip: Clip) {
        NSWorkspace.shared.open(clip.clipURL)
    }

    func export(_ clip: Clip) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.quickTimeMovie]
        panel.nameFieldStringValue = "\(clip.sourceAppName ?? clip.gameName)-\(Self.fileTimestamp.string(from: clip.capturedAt)).mov"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.copyItem(at: clip.clipURL, to: url)
            gameRegistryMessage = "Exported \(clip.gameName)"
        } catch {
            lastError = error.localizedDescription
            updateDerivedState()
        }
    }

    func share(_ clip: Clip) {
        guard let view = NSApp.keyWindow?.contentView else {
            reveal(clip)
            return
        }
        NSSharingServicePicker(items: [clip.clipURL]).show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }

    func delete(_ clip: Clip) {
        Task {
            await deleteClip(clip)
        }
    }

    func toggleStar(_ clip: Clip) {
        guard !isLibraryBusy, !isSaveInProgress, let index = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        var updated = clips
        updated[index].isStarred = updated[index].isStarred != true
        do {
            try clipIndexStore.save(updated)
            clips = updated
            libraryMessage = updated[index].isStarred == true ? "Starred clip protected from automatic cleanup." : "Clip unstarred."
        } catch { libraryMessage = error.localizedDescription }
    }

    func saveEditedClip(_ source: Clip, start: Double, end: Double, gains: [Double]) async throws {
        guard !isLibraryBusy, !isSaveInProgress else { throw ClipEditorError.busy }
        isLibraryBusy = true
        defer { isLibraryBusy = false }
        let folder = source.folderURL.deletingLastPathComponent().appendingPathComponent("Edit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let output = folder.appendingPathComponent("clip.mov")
            try await ClipEditor.export(source: source.editableSourceURL ?? source.clipURL, output: output, start: start, end: end, gains: gains)
            let thumbnail = folder.appendingPathComponent("thumbnail.jpg")
            try? await VideoThumbnailGenerator().generateThumbnail(for: output, outputURL: thumbnail)
            let clip = Clip(id: UUID(), gameID: source.gameID, gameName: source.gameName,
                sourceAppName: source.sourceAppName, capturedAt: Date(), durationSeconds: max(1, Int((end - start).rounded())),
                presetName: "\(source.presetName) · Edited", folderURL: folder, clipURL: output,
                metadataURL: folder.appendingPathComponent("metadata.json"), thumbnailURL: thumbnail)
            try JSONEncoder.capturely.encode(clip).write(to: clip.metadataURL, options: .atomic)
            var updated = clips
            updated.insert(clip, at: 0)
            try await clipIndexStore.saveAsync(updated)
            clips = updated
            recentClips = clips.map(RecentClipDisplay.init(clip:))
            libraryMessage = "Edited copy saved."
            Task { await enforceLibraryLimit(protecting: clip.id) }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    private func removeClipFromLibrary(_ clip: Clip) throws {
        var trashed: NSURL?
        try FileManager.default.trashItem(at: clip.folderURL, resultingItemURL: &trashed)
        let updated = clips.filter { $0.id != clip.id }
        do { try clipIndexStore.save(updated) }
        catch {
            if let trashed { try? FileManager.default.moveItem(at: trashed as URL, to: clip.folderURL) }
            throw error
        }
        clips = updated
        recentClips = clips.map(RecentClipDisplay.init(clip:))
    }

    private func enforceLibraryLimit(protecting id: UUID? = nil) async {
        guard settings.libraryLimitGB > 0, !isLibraryBusy, !isSaveInProgress || id != nil else { return }
        isLibraryBusy = true
        defer { isLibraryBusy = false }
        let snapshot = clips
        let entries = await Task.detached(priority: .utility) { LibraryStorage.inventory(snapshot) }.value
        let limit = Int64(settings.libraryLimitGB) * 1_000_000_000
        let removals = LibraryStorage.removals(entries: entries, limitBytes: limit, protectedIDs: Set([id, editingClip?.id].compactMap { $0 }))
        do {
            for clip in removals { try removeClipFromLibrary(clip) }
            let remainingBytes = entries.filter { entry in !removals.contains(where: { $0.id == entry.clip.id }) }.reduce(Int64(0)) { $0 + $1.bytes }
            libraryMessage = remainingBytes > limit ? "Library exceeds limit: protected or unrecognized files were kept."
                : removals.isEmpty ? "Library is within its limit." : "Moved \(removals.count) old clips to Trash. Empty Trash manually to reclaim space."
        } catch { libraryMessage = "Cleanup stopped: \(error.localizedDescription)" }
    }

    private func deleteClip(_ clip: Clip) async {
        guard !isLibraryBusy, !isSaveInProgress else { libraryMessage = "Wait for the current save or edit to finish."; return }
        isLibraryBusy = true
        defer { isLibraryBusy = false }
        do {
            try removeClipFromLibrary(clip)
            lastSaveResult = nil
            updateDerivedState()
        } catch {
            libraryMessage = error.localizedDescription
            updateDerivedState()
        }
    }

    private func handleMatchChanged(_ match: RunningGameMatch?, manuallyRequested: Bool = false) async {
        guard !isManualCaptureActive else {
            currentMatch = match
            return
        }

        currentMatch = match

        if match?.processIdentifier != suppressedGamePID { suppressedGamePID = nil }
        if let match, !manuallyRequested,
           (!settings.automaticGameSessions || suppressedGamePID == match.processIdentifier) {
            updateDerivedState()
            return
        }

        guard let match else {
            await captureCoordinator.stop()
            lastError = nil
            hasReportedBufferReady = false
            isPerformanceFallbackActive = false
            record(.init(kind: .appDetected, message: "Configured game disappeared"))
            updateDerivedState(windowTitle: nil, isWindowLocked: false)
            return
        }

        hasReportedBufferReady = false
        isPerformanceFallbackActive = false
        record(.init(kind: .appDetected, message: "Detected \(match.detectedAppName ?? match.game.displayName)"))
        updateDerivedState(windowTitle: match.detectedAppName, isWindowLocked: false)
        let preset = runtimePreset(for: match.game)
        guard await preparePermissionsForCapture(preset: preset, windowTitle: match.detectedAppName) else { return }
        if captureCoordinator.state.isRecording {
            await captureCoordinator.stop()
        }
        await captureCoordinator.start(
            match: match,
            preset: preset,
            sourceMode: settings.captureSourceMode,
            selectedDisplayID: settings.selectedDisplayID,
            microphoneDeviceID: settings.microphoneDeviceID
        )
        updateDerivedState(windowTitle: match.detectedAppName, isWindowLocked: captureCoordinator.state.isRecording)

        if captureCoordinator.state.isRecording {
            try? await notificationService.requestAuthorization()
            try? await notificationService.notifyRecordingStarted(gameName: match.game.displayName)
        }
    }

    private func startManualCapture() async {
        guard !isStartingManualCapture, !captureCoordinator.state.isRecording else {
            gameRegistryMessage = "Capture is already running"
            return
        }
        isStartingManualCapture = true
        defer { isStartingManualCapture = false }
        await permissionService.refresh()
        permissionSummary = permissionService.summary
        lastSaveResult = nil
        lastError = nil
        hasReportedBufferReady = false
        isPerformanceFallbackActive = false
        isManualCaptureActive = true

        let game = manualCaptureGame
        let match = RunningGameMatch(
            game: game,
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            detectedAppName: selectedDisplayName ?? "Selected Screen"
        )
        record(.init(kind: .captureStarting, message: "Manual screen capture requested"))
        updateDerivedState(windowTitle: match.detectedAppName, isWindowLocked: false)

        let preset = runtimePreset(for: game)
        guard await preparePermissionsForCapture(preset: preset, windowTitle: match.detectedAppName) else {
            isManualCaptureActive = false
            return
        }

        await captureCoordinator.start(
            match: match,
            preset: preset,
            sourceMode: .selectedDisplay,
            selectedDisplayID: settings.selectedDisplayID,
            microphoneDeviceID: settings.microphoneDeviceID
        )

        if captureCoordinator.state.isRecording {
            try? await notificationService.requestAuthorization()
            try? await notificationService.notifyRecordingStarted(gameName: game.displayName)
        } else {
            isManualCaptureActive = false
        }
        updateDerivedState(windowTitle: match.detectedAppName, isWindowLocked: captureCoordinator.state.isRecording)
    }

    private func stopManualCapture() async {
        guard captureCoordinator.state.isRecording else {
            gameRegistryMessage = "Capture is not running"
            updateDerivedState()
            return
        }

        record(.init(kind: .captureStopped, message: "Manual capture stopped"))
        isManualCaptureActive = false
        isPerformanceFallbackActive = false
        await captureCoordinator.stop()
        currentMatch = processMonitor.currentMatch
        lastSaveResult = nil
        updateDerivedState(windowTitle: currentMatch?.detectedAppName, isWindowLocked: false)
    }

    private func addGame(_ game: Game) {
        let before = games.count
        games = ApplicationScanner.merge(existing: games, incoming: [game])
        let message = games.count == before ? "\(game.displayName) already added" : "Added \(game.displayName)"
        persistGamesAndRestartMonitor(message: message)
    }

    private func persistGamesAndRestartMonitor(message: String) {
        do {
            try gameRegistryStore.save(games)
            gameRegistryMessage = message
            if hasActivatedCaptureRuntime {
                processMonitor.start(games: games)
            }
        } catch {
            gameRegistryMessage = "Could not save games: \(error.localizedDescription)"
        }
    }

    private func activateCaptureRuntime() async {
        guard !hasActivatedCaptureRuntime else { return }
        hasActivatedCaptureRuntime = true
        await refreshCaptureDevices()
        processMonitor.start(games: games)
    }

    private func saveClip(duration: Int? = nil) async {
        guard !isLibraryBusy else { libraryMessage = "Wait for the current library edit to finish."; return }
        let capturedAt = Date()
        let loggingPID = currentMatch?.processIdentifier
        if let lastAcceptedSaveRequestAt,
           capturedAt.timeIntervalSince(lastAcceptedSaveRequestAt) < Self.saveRequestCoalescingInterval {
            record(.init(kind: .saveRequested, message: "Duplicate save request ignored"))
            return
        }

        guard !isSaveInProgress else {
            record(.init(kind: .saveRequested, message: "Duplicate save request ignored while saving"))
            return
        }
        lastAcceptedSaveRequestAt = capturedAt
        isSaveInProgress = true
        defer {
            isSaveInProgress = false
        }

        record(.init(kind: .saveRequested, message: "Save requested"))
        guard captureCoordinator.state.isRecording else {
            lastSaveResult = .failed("Capture is not running")
            record(.init(kind: .saveFailed, message: "Save failed: capture is not running"))
            updateDerivedState()
            return
        }
        guard let game = captureCoordinator.state.game ?? currentMatch?.game else {
            lastSaveResult = .failed("No detected game")
            record(.init(kind: .saveFailed, message: "Save failed: no detected game"))
            updateDerivedState()
            return
        }
        let preset = activeCapturePreset(for: game)
        let replayDurationSeconds = duration.map(TimeInterval.init) ?? replayDurationSecondsForSave(capturedAt: capturedAt, preset: preset)

        do {
            status = RecordingDisplayStatus(
                captureState: .savingClip(game: game),
                windowTitle: currentMatch?.detectedAppName,
                isWindowLocked: true,
                bufferDurationSeconds: captureCoordinator.replaySegmentWriter.currentBufferDurationSeconds
            )
            recordingState = .saving(game)
            let destination = try clipDestination(gameName: game.displayName, capturedAt: capturedAt)
            var clip = try await captureCoordinator.saveClip(
                game: game,
                preset: preset,
                destination: destination,
                clipIndexStore: clipIndexStore,
                capturedAt: capturedAt,
                replayDurationSeconds: replayDurationSeconds,
                sourceAppName: sourceAppName(forSavedGame: game),
                audioGain: audioOutputGain(for: preset),
                keepsEditableAudio: settings.keepsEditableAudio
            )
            if settings.logsGameProcess {
                let url = clip.folderURL.appendingPathComponent("process-log.csv")
                do {
                    if try gameProcessLogger.saveWindow(pid: loggingPID, endingAt: capturedAt, duration: Double(clip.durationSeconds), to: url) {
                        clip.processLogURL = url
                        try JSONEncoder.capturely.encode(clip).write(to: clip.metadataURL, options: .atomic)
                        try clipIndexStore.save([clip] + clips)
                    }
                } catch { libraryMessage = "Video saved; process log failed: \(error.localizedDescription)" }
            }
            clips.insert(clip, at: 0)
            recentClips = clips.map(RecentClipDisplay.init(clip:))
            lastSaveResult = .saved(clip)
            lastSuccessfulSaveCapturedAt = capturedAt
            lastError = nil
            NotificationCenter.default.post(name: .capturelyReplaySaved, object: clip)
            updateDerivedState(windowTitle: currentMatch?.detectedAppName, isWindowLocked: captureCoordinator.state.isRecording)
            try? await notificationService.notifyClipSaved(gameName: game.displayName)
            await enforceLibraryLimit(protecting: clip.id)
        } catch CaptureCoordinatorError.noReplaySegmentsAvailable {
            lastSaveResult = .failed("Replay buffer is empty")
            record(.init(kind: .saveFailed, message: "Save failed: replay buffer is empty"))
            _ = try? writeDiagnosticsReport(prefix: "Capturely-SaveFailure")
            updateDerivedState(windowTitle: currentMatch?.detectedAppName, isWindowLocked: captureCoordinator.state.isRecording)
        } catch {
            lastSaveResult = .failed(error.localizedDescription)
            lastError = error.localizedDescription
            record(.init(kind: .saveFailed, message: "Save failed: \(error.localizedDescription)"))
            _ = try? writeDiagnosticsReport(prefix: "Capturely-SaveFailure")
            captureFailed(error.localizedDescription, windowTitle: currentMatch?.detectedAppName)
        }
    }

    private func updateDerivedState(windowTitle: String? = nil, isWindowLocked: Bool = false) {
        let metrics = captureCoordinator.replaySegmentWriter.healthMetrics
        let outputFolder = try? (settings.clipLibraryURL ?? appPaths.defaultClipLibraryDirectory)
        isCaptureConfigurationLocked = captureCoordinator.state.locksCaptureConfiguration
        health = CaptureHealthSnapshot(
            detectedAppName: displayedCaptureName,
            captureState: captureCoordinator.state.runtimeState,
            activeSegmentCount: metrics.activeSegmentCount,
            currentBufferDurationSeconds: metrics.currentBufferDurationSeconds,
            lastVideoSampleAt: metrics.lastVideoSampleAt,
            lastAudioSampleAt: metrics.lastAudioSampleAt,
            audioStatus: metrics.audioStatus,
            audioLevel: metrics.audioLevel,
            audioQualityScore: metrics.audioQualityScore,
            recentAudioLevels: metrics.recentAudioLevels,
            audioSampleRate: metrics.audioSampleRate,
            audioChannelCount: metrics.audioChannelCount,
            performance: metrics.performance,
            outputFolder: outputFolder,
            lastSaveResult: lastSaveResult,
            lastError: lastError
        )
        recordingState = RecordingState.derive(
            captureState: captureCoordinator.state,
            permissionSummary: permissionSummary,
            preset: runtimePreset(for: captureCoordinator.state.game ?? currentMatch?.game),
            bufferDurationSeconds: metrics.currentBufferDurationSeconds,
            lastSaveResult: lastSaveResult
        )
        if !hasReportedBufferReady,
           case .readyToSave = recordingState {
            hasReportedBufferReady = true
            record(.init(kind: .bufferReady, message: "Replay buffer ready: \(String(format: "%.1fs", metrics.currentBufferDurationSeconds))"))
        }

        status = RecordingDisplayStatus(
            captureState: captureCoordinator.state,
            windowTitle: windowTitle ?? currentMatch?.game.preferredWindowTitle ?? selectedDisplayName,
            isWindowLocked: isWindowLocked,
            bufferDurationSeconds: metrics.currentBufferDurationSeconds,
            storageFreeDescription: "Local storage ready",
            micStatusDescription: permissionSummary.microphoneGranted ? "Mic on" : "Mic optional"
        )
    }

    private func captureFailed(_ message: String, windowTitle: String?) {
        status = RecordingDisplayStatus(captureState: .failed(message: message), windowTitle: windowTitle, isWindowLocked: false)
        recordingState = .failed(message)
        updateHealthOnly(lastError: message)
    }

    private func updateHealthOnly(lastError: String?) {
        let metrics = captureCoordinator.replaySegmentWriter.healthMetrics
        isCaptureConfigurationLocked = captureCoordinator.state.locksCaptureConfiguration
        health = CaptureHealthSnapshot(
            detectedAppName: displayedCaptureName,
            captureState: captureCoordinator.state.runtimeState,
            activeSegmentCount: metrics.activeSegmentCount,
            currentBufferDurationSeconds: metrics.currentBufferDurationSeconds,
            lastVideoSampleAt: metrics.lastVideoSampleAt,
            lastAudioSampleAt: metrics.lastAudioSampleAt,
            audioStatus: metrics.audioStatus,
            audioLevel: metrics.audioLevel,
            audioQualityScore: metrics.audioQualityScore,
            recentAudioLevels: metrics.recentAudioLevels,
            audioSampleRate: metrics.audioSampleRate,
            audioChannelCount: metrics.audioChannelCount,
            performance: metrics.performance,
            outputFolder: try? (settings.clipLibraryURL ?? appPaths.defaultClipLibraryDirectory),
            lastSaveResult: lastSaveResult,
            lastError: lastError
        )
    }

    private func startHealthMonitoring() {
        healthMonitorTask?.cancel()
        healthMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await self?.checkCaptureHealth()
            }
        }
    }

    private func checkCaptureHealth() async {
        updateDerivedState(windowTitle: currentMatch?.detectedAppName, isWindowLocked: captureCoordinator.state.isRecording)
        resourceUsage = resourceSampler.sample(performance: health.performance, recording: captureCoordinator.state.isRecording)
        gameProcessSample = gameProcessLogger.sample(
            pid: settings.logsGameProcess && captureCoordinator.state.isRecording ? currentMatch?.processIdentifier : nil,
            appUsage: resourceUsage, performance: health.performance)
        if !settings.logsGameProcess { gameProcessSample.status = "Process logging is off" }
        if await activatePerformanceFallbackIfNeeded() {
            return
        }
        guard health.isVideoStalled(), let match = currentMatch, captureCoordinator.state.isRecording else {
            if health.isVideoStalled(), isManualCaptureActive, captureCoordinator.state.isRecording {
                await restartManualCaptureAfterStall()
            }
            return
        }
        lastError = "Video samples stalled; restarting capture"
        recordingState = .warning("Capture stalled, restarting")
        record(.init(kind: .captureStalledRestarting, message: "Video samples stalled; restarting capture"))
        await captureCoordinator.stop()
        await captureCoordinator.start(
            match: match,
            preset: runtimePreset(for: match.game),
            sourceMode: settings.captureSourceMode,
            selectedDisplayID: settings.selectedDisplayID,
            microphoneDeviceID: settings.microphoneDeviceID
        )
        updateDerivedState(windowTitle: match.detectedAppName, isWindowLocked: captureCoordinator.state.isRecording)
    }

    private func activatePerformanceFallbackIfNeeded() async -> Bool {
        guard !isPerformanceFallbackActive,
              captureCoordinator.state.isRecording,
              Self.shouldActivatePerformanceFallback(performance: health.performance) else {
            return false
        }

        isPerformanceFallbackActive = true
        lastError = "Capture backpressure detected; Performance Mode active"
        gameRegistryMessage = "Performance Mode active"
        recordingState = .warning("Capture backpressure detected; using Performance Mode")
        record(.init(kind: .captureStalledRestarting, message: "Capture backpressure detected; restarting in Performance Mode"))

        if isManualCaptureActive {
            let game = manualCaptureGame
            let match = RunningGameMatch(
                game: game,
                processIdentifier: ProcessInfo.processInfo.processIdentifier,
                detectedAppName: selectedDisplayName ?? "Selected Screen"
            )
            await captureCoordinator.stop()
            await captureCoordinator.start(
                match: match,
                preset: runtimePreset(for: game),
                sourceMode: .selectedDisplay,
                selectedDisplayID: settings.selectedDisplayID,
                microphoneDeviceID: settings.microphoneDeviceID
            )
            updateDerivedState(windowTitle: match.detectedAppName, isWindowLocked: captureCoordinator.state.isRecording)
            return true
        }

        guard let match = currentMatch else { return false }
        await captureCoordinator.stop()
        await captureCoordinator.start(
            match: match,
            preset: runtimePreset(for: match.game),
            sourceMode: settings.captureSourceMode,
            selectedDisplayID: settings.selectedDisplayID,
            microphoneDeviceID: settings.microphoneDeviceID
        )
        updateDerivedState(windowTitle: match.detectedAppName, isWindowLocked: captureCoordinator.state.isRecording)
        return true
    }

    private func preparePermissionsForCapture(preset: CapturePreset, windowTitle: String?) async -> Bool {
        await permissionService.refresh()
        permissionSummary = permissionService.summary

        if permissionSummary.needsScreenCapturePermission {
            let reason = "Screen Recording permission needed"
            lastError = reason
            await captureCoordinator.markPermissionRequired(reason)
            record(.init(kind: .saveFailed, message: "Capture blocked: \(reason)"))
            updateDerivedState(windowTitle: windowTitle, isWindowLocked: false)
            return false
        }

        if preset.recordsMicrophone && !permissionSummary.microphoneGranted {
            let reason = "Microphone permission needed"
            lastError = reason
            await captureCoordinator.markPermissionRequired(reason)
            record(.init(kind: .saveFailed, message: "Capture blocked: \(reason)"))
            updateDerivedState(windowTitle: windowTitle, isWindowLocked: false)
            return false
        }

        lastError = nil
        return true
    }

    private func openScreenRecordingSettings() {
        openPrivacySettings(pane: "Privacy_ScreenCapture")
    }

    private func openPrivacySettings(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    nonisolated static func shouldActivatePerformanceFallback(performance: CapturePerformanceSnapshot) -> Bool {
        guard performance.videoInputBackpressureDrops >= performanceFallbackBackpressureDropThreshold else {
            return false
        }
        let received = max(performance.videoSamplesReceived, 1)
        return Double(performance.videoInputBackpressureDrops) / Double(received) >= performanceFallbackBackpressureRatioThreshold
    }

    private func record(_ event: CaptureDiagnosticEvent) {
        recentEvents.append(event)
        if recentEvents.count > 80 {
            recentEvents.removeFirst(recentEvents.count - 80)
        }
    }

    private func preset(for game: Game?) -> CapturePreset {
        Self.resolvedPreset(for: game, settings: settings)
    }

    private func runtimePreset(for game: Game?) -> CapturePreset {
        guard isPerformanceFallbackActive else {
            return preset(for: game)
        }
        var fallback = CapturePreset.storageSaver.applying(settings: settings)
        fallback.displayName = "Performance Mode"
        return fallback
    }

    private func activeCapturePreset(for game: Game) -> CapturePreset {
        if case .recording(_, let preset) = captureCoordinator.state {
            return preset
        }
        return runtimePreset(for: game)
    }

    nonisolated static func resolvedPreset(for game: Game?, settings: AppSettings) -> CapturePreset {
        // The quality control is authoritative, including for previously registered games.
        let presetID = settings.selectedPresetID
        return CapturePreset.preset(id: presetID, settings: settings).applying(settings: settings)
    }

    nonisolated static func shouldActivateCaptureRuntime(hasCompletedOnboarding: Bool) -> Bool {
        hasCompletedOnboarding
    }

    nonisolated static func shouldStartManualCapture(hasCompletedOnboarding: Bool) -> Bool {
        hasCompletedOnboarding
    }

    private func restartManualCaptureAfterStall() async {
        let game = manualCaptureGame
        let match = RunningGameMatch(
            game: game,
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            detectedAppName: selectedDisplayName ?? "Selected Screen"
        )
        lastError = "Video samples stalled; restarting capture"
        recordingState = .warning("Capture stalled, restarting")
        record(.init(kind: .captureStalledRestarting, message: "Manual screen capture stalled; restarting capture"))
        await captureCoordinator.stop()
        await captureCoordinator.start(
            match: match,
            preset: runtimePreset(for: game),
            sourceMode: .selectedDisplay,
            selectedDisplayID: settings.selectedDisplayID,
            microphoneDeviceID: settings.microphoneDeviceID
        )
        updateDerivedState(windowTitle: match.detectedAppName, isWindowLocked: captureCoordinator.state.isRecording)
    }

    private var displayedCaptureName: String? {
        if isManualCaptureActive {
            return selectedDisplayName ?? manualCaptureGame.displayName
        }
        return currentMatch?.detectedAppName ?? currentMatch?.game.displayName
    }

    private var selectedDisplayName: String? {
        if let selectedDisplayID = settings.selectedDisplayID,
           let display = displayOptions.first(where: { $0.displayID == selectedDisplayID }) {
            return "\(display.name) \(display.detail)"
        }
        return displayOptions.first.map { "\($0.name) \($0.detail)" }
    }

    private func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        guard canChangeCaptureConfiguration() else { return }

        mutate(&settings)
        isPerformanceFallbackActive = false
        configureReplayRetention()
        scheduleSettingsSave()
        gameRegistryMessage = "Settings saved"
        updateDerivedState(windowTitle: currentMatch?.detectedAppName, isWindowLocked: captureCoordinator.state.isRecording)
    }

    private func configureReplayRetention() {
        captureCoordinator.replaySegmentWriter.updateMaximumDurationSeconds(
            Self.replayRetentionSeconds(forReplayDuration: max(60, settings.replayDurationSeconds))
        )
    }

    private func scheduleSettingsSave() {
        settingsSaveTask?.cancel()
        let store = appSettingsStore
        let settings = settings
        settingsSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(400))
                try await store.saveAsync(settings)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self?.gameRegistryMessage = "Settings saved"
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self?.gameRegistryMessage = "Could not save settings: \(error.localizedDescription)"
                }
            }
        }
    }

    nonisolated static func replayRetentionSeconds(forReplayDuration replayDurationSeconds: Int) -> TimeInterval {
        max(10, TimeInterval(replayDurationSeconds) + replayRetentionPaddingSeconds)
    }

    func persistSettingsImmediatelyForTesting() async {
        settingsSaveTask?.cancel()
        do {
            try await appSettingsStore.saveAsync(settings)
            gameRegistryMessage = "Settings saved"
        } catch {
            gameRegistryMessage = "Could not save settings: \(error.localizedDescription)"
        }
    }

    private func canChangeCaptureConfiguration() -> Bool {
        guard !isCaptureConfigurationLocked else {
            gameRegistryMessage = "Settings are locked while recording"
            return false
        }
        return true
    }

    private func clipDestination(gameName: String, capturedAt: Date) throws -> ClipDestination {
        let root: URL
        if let clipLibraryURL = settings.clipLibraryURL {
            root = clipLibraryURL
        } else {
            root = try appPaths.defaultClipLibraryDirectory
        }
        return ClipPathBuilder(root: root, calendar: .current, timeZone: .current).uniqueDestination(forGameName: gameName, capturedAt: capturedAt)
    }

    private func replayDurationSecondsForSave(capturedAt: Date, preset: CapturePreset) -> TimeInterval {
        Self.replayDurationSecondsForSave(
            capturedAt: capturedAt,
            preset: preset,
            lastSuccessfulSaveCapturedAt: lastSuccessfulSaveCapturedAt
        )
    }

    nonisolated static func replayDurationSecondsForSave(
        capturedAt: Date,
        preset: CapturePreset,
        lastSuccessfulSaveCapturedAt: Date?
    ) -> TimeInterval {
        TimeInterval(preset.replayDurationSeconds)
    }

    private func sourceAppName(forSavedGame game: Game) -> String? {
        guard game.displayName == manualCaptureGame.displayName else {
            return game.displayName
        }
        return currentMatch?.game.displayName ?? currentMatch?.detectedAppName
    }

    private func audioOutputGain(for preset: CapturePreset) -> Double {
        // Each source carries its own gain into the replay export.
        1
    }

    private static func clampedMix(_ value: Double) -> Double {
        min(max(value, 0), 1.5)
    }

    private static let defaultGames = [
        Game(
            displayName: "Roblox",
            bundleIdentifier: "com.roblox.RobloxPlayer",
            appURL: URL(fileURLWithPath: "/Applications/Roblox.app", isDirectory: true),
            executableURL: URL(fileURLWithPath: "/Applications/Roblox.app/Contents/MacOS/RobloxPlayer"),
            presetID: nil
        )
    ]

    private var manualCaptureGame: Game {
        Game(
            displayName: "Screen Capture",
            bundleIdentifier: nil,
            preferredWindowTitle: selectedDisplayName ?? "Selected Screen",
            presetID: settings.selectedPresetID
        )
    }

    private static let fileTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter
    }()

    private static let saveRequestCoalescingInterval: TimeInterval = 1.25
    private nonisolated static let replayRetentionPaddingSeconds: TimeInterval = ReplaySegmentWriter.defaultSegmentDurationSeconds
    private nonisolated static let performanceFallbackBackpressureDropThreshold = 30
    private nonisolated static let performanceFallbackBackpressureRatioThreshold = 0.03

    private static func microphoneDeviceOptions() -> [MicrophoneDeviceOption] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices.map {
            MicrophoneDeviceOption(id: $0.uniqueID, name: $0.localizedName)
        }
    }
}

private extension RecentClipDisplay {
    init(clip: Clip) {
        self.init(
            gameName: RecordingDisplayStatus.appLabel(for: Game(displayName: clip.sourceAppName ?? clip.gameName)),
            experienceName: clip.gameName,
            time: Self.clipTimeFormatter.string(from: clip.capturedAt),
            duration: "\(clip.durationSeconds)s",
            preset: clip.presetName,
            accent: .red,
            thumbnailURL: clip.thumbnailURL,
            clipURL: clip.clipURL
        )
    }

    static let clipTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

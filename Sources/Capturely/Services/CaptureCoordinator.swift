import AVFoundation
import AppKit
import Combine
import Foundation
import ScreenCaptureKit

@MainActor
final class CaptureCoordinator: NSObject, ObservableObject {
    @Published private(set) var state: CaptureState = .idle
    var onDiagnosticEvent: (@Sendable (CaptureDiagnosticEvent) -> Void)? {
        didSet {
            replaySegmentWriter.onDiagnosticEvent = onDiagnosticEvent
        }
    }

    private let windowResolver = GameWindowResolver()
    let replaySegmentWriter: ReplaySegmentWriter
    private let replayComposer: any ReplayComposing
    private let thumbnailGenerator: any ThumbnailGenerating
    private let sampleHandlerQueue = DispatchQueue(label: "capturely.stream.samples", qos: .utility)
    private lazy var applicationAudioCapture = ApplicationAudioCapture(writer: replaySegmentWriter)
    private var stream: SCStream?
    private var isStarting = false
    private var generation = 0
    let frameBarPlugin = FrameBarPlugin()
    private var replayBookmarks = ReplayBookmarks()

    @discardableResult func bookmark(now: Date = Date()) -> Bool {
        guard state.isRecording else { return false }
        return replayBookmarks.add(now: now)
    }
    private var filterContext: (RunningGameMatch, CaptureSourceMode, UInt32?)?
    private var frameBarPIDs: [pid_t] = []
    private var workspaceObservers = Set<AnyCancellable>()
    private var refreshingFilter = false

    /// Refresh only on companion process changes, never on each captured frame.
    func refreshFrameBarExclusion() async {
        guard !refreshingFilter, let activeStream = stream, let context = filterContext, context.1 == .selectedDisplay else { return }
        let pids = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "app.italianseasoning.FrameBar" }.map(\.processIdentifier).sorted()
        guard pids != frameBarPIDs else { return }
        refreshingFilter = true
        defer { refreshingFilter = false }
        do {
            guard let source = try await windowResolver.resolveSource(for: context.0, mode: context.1, selectedDisplayID: context.2), stream === activeStream else { return }
            try await activeStream.updateContentFilter(source.filter)
            if stream === activeStream { frameBarPIDs = pids }
        } catch {
            onDiagnosticEvent?(CaptureDiagnosticEvent(kind: .companionWarning, message: "FrameBar exclusion update failed: \(error.localizedDescription)"))
        }
    }

    init(
        replaySegmentWriter: ReplaySegmentWriter,
        replayComposer: any ReplayComposing = ReplayComposer(),
        thumbnailGenerator: any ThumbnailGenerating = VideoThumbnailGenerator()
    ) {
        self.replaySegmentWriter = replaySegmentWriter
        self.replayComposer = replayComposer
        self.thumbnailGenerator = thumbnailGenerator
        super.init()
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name).sink { [weak self] _ in
                Task { @MainActor in await self?.refreshFrameBarExclusion() }
            }.store(in: &workspaceObservers)
        }
    }

    func start(
        match: RunningGameMatch,
        preset: CapturePreset,
        sourceMode: CaptureSourceMode = .selectedDisplay,
        selectedDisplayID: UInt32? = nil,
        microphoneDeviceID: String? = nil,
        isolatedAudioSources: [AudioSourceDescriptor] = []
    ) async {
        guard !isStarting, stream == nil else { return }
        isStarting = true
        defer { isStarting = false }
        generation += 1
        let startedGeneration = generation
        do {
            if state != .waitingForWindow(game: match.game) {
                onDiagnosticEvent?(CaptureDiagnosticEvent(kind: .captureStarting, message: "Capture starting for \(match.game.displayName)"))
            }

            guard let resolvedSource = try await windowResolver.resolveSource(
                for: match,
                mode: sourceMode,
                selectedDisplayID: selectedDisplayID
            ) else {
                guard generation == startedGeneration else { return }
                let waitingState = CaptureState.waitingForWindow(game: match.game)
                if state != waitingState { state = waitingState }
                return
            }
            guard generation == startedGeneration else { return }

            let configuration = SCStreamConfiguration()
            let captureSize = Self.cappedCaptureSize(
                width: resolvedSource.width,
                height: resolvedSource.height,
                maximumHeight: preset.maximumHeight
            )
            configuration.width = captureSize.width
            configuration.height = captureSize.height
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, preset.maximumFramesPerSecond)))
            configuration.queueDepth = 2
            configuration.showsCursor = false
            configuration.pixelFormat = Self.streamPixelFormatForEncoding
            let audioSources = Self.resolvedAudioSources(
                preset: preset,
                isolatedAudioSources: isolatedAudioSources,
                microphoneDeviceID: microphoneDeviceID
            )
            let applicationSources = audioSources.filter { $0.kind == .application }
            let capturesBroadSystemAudio = preset.recordsSystemAudio && applicationSources.isEmpty
            configuration.capturesAudio = capturesBroadSystemAudio
            configuration.captureMicrophone = preset.recordsMicrophone
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            configuration.excludesCurrentProcessAudio = true
            configuration.microphoneCaptureDeviceID = microphoneDeviceID

            let stream = SCStream(filter: resolvedSource.filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleHandlerQueue)
            if capturesBroadSystemAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleHandlerQueue)
            }
            if preset.recordsMicrophone {
                try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleHandlerQueue)
            }

            try replaySegmentWriter.startRecording(preset: preset, audioSources: audioSources)
            replayBookmarks.reset()
            self.stream = stream
            filterContext = (match, sourceMode, selectedDisplayID)
            frameBarPIDs = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "app.italianseasoning.FrameBar" }.map(\.processIdentifier).sorted()
            try await stream.startCapture()
            guard generation == startedGeneration else {
                try? await stream.stopCapture()
                return
            }
            applicationAudioCapture.onDiagnosticEvent = onDiagnosticEvent
            await applicationAudioCapture.start(sources: applicationSources, selectedDisplayID: selectedDisplayID)
            guard generation == startedGeneration else {
                await applicationAudioCapture.stop()
                return
            }
            state = .recording(game: match.game, preset: preset)
            onDiagnosticEvent?(CaptureDiagnosticEvent(kind: .captureStarted, message: "Capture started for \(match.game.displayName)"))
        } catch {
            guard generation == startedGeneration else { return }
            self.stream = nil
            await applicationAudioCapture.stop()
            await replaySegmentWriter.stopRecording()
            state = .failed(message: error.localizedDescription)
            onDiagnosticEvent?(CaptureDiagnosticEvent(kind: .saveFailed, message: "Capture failed: \(error.localizedDescription)"))
        }
    }

    func stop() async {
        replayBookmarks.reset()
        filterContext = nil
        frameBarPlugin.sample(pid: nil)
        generation += 1
        let stoppingStream = stream
        stream = nil
        await applicationAudioCapture.stop()
        do {
            try await stoppingStream?.stopCapture()
            state = .idle
        } catch {
            state = .failed(message: error.localizedDescription)
        }
        await replaySegmentWriter.stopRecording()
    }

    func markPermissionRequired(_ reason: String) async {
        generation += 1
        try? await stream?.stopCapture()
        stream = nil
        await applicationAudioCapture.stop()
        await replaySegmentWriter.stopRecording()
        state = .permissionRequired(reason: reason)
    }

    func saveClip(
        game: Game,
        preset: CapturePreset,
        destination: ClipDestination,
        clipIndexStore: ClipIndexStore,
        capturedAt: Date = Date(),
        replayDurationSeconds: TimeInterval? = nil,
        sourceAppName: String? = nil,
        audioGain: Double = 1,
        keepsEditableAudio: Bool = false
    ) async throws -> Clip {
        // Keep the save's data even if capture stops while the active segment flushes.
        let telemetrySamples = frameBarPlugin.samples
        let bookmarkBuffer = replayBookmarks
        await replaySegmentWriter.flushActiveSegmentForClip(minimumDurationSeconds: Self.minimumActiveSegmentFlushDurationSeconds)
        let requestedDurationSeconds = replayDurationSeconds ?? TimeInterval(preset.replayDurationSeconds)
        let snapshotDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Capturely-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: snapshotDirectory) }
        let selectedSegments = try replaySegmentWriter.snapshotSegments(forReplayDuration: requestedDurationSeconds, to: snapshotDirectory)
        let telemetry = FrameBarPlugin.timeline(samples: telemetrySamples, segments: selectedSegments, duration: requestedDurationSeconds)
        let bookmarks = bookmarkBuffer.snapshot(segments: selectedSegments, duration: requestedDurationSeconds)
        guard !selectedSegments.isEmpty else {
            onDiagnosticEvent?(CaptureDiagnosticEvent(kind: .saveFailed, message: "Save failed: replay buffer is empty"))
            throw CaptureCoordinatorError.noReplaySegmentsAvailable
        }

        try FileManager.default.createDirectory(at: destination.folder, withIntermediateDirectories: true)
        onDiagnosticEvent?(CaptureDiagnosticEvent(
            kind: .compositionStarted,
            message: "Composition started with \(selectedSegments.count) segment(s), \(String(format: "%.1fs", requestedDurationSeconds)) requested, output \(destination.clipFile.path(percentEncoded: false))"
        ))
        do {
            let result = try await replayComposer.compose(
                segments: selectedSegments,
                outputURL: destination.clipFile,
                targetDurationSeconds: requestedDurationSeconds,
                audioGain: audioGain
            )
            onDiagnosticEvent?(CaptureDiagnosticEvent(
                kind: .compositionFinished,
                message: "Composition finished via \(result.strategy.rawValue) in \(String(format: "%.1fms", result.elapsedMilliseconds))"
            ))
        } catch {
            cleanupFailedDestination(destination)
            onDiagnosticEvent?(CaptureDiagnosticEvent(kind: .saveFailed, message: "Save failed during composition: \(error.localizedDescription)"))
            throw error
        }
        guard Self.isValidClipOutput(destination.clipFile) else {
            let details = Self.outputDiagnostics(for: destination.clipFile)
            cleanupFailedDestination(destination)
            onDiagnosticEvent?(CaptureDiagnosticEvent(kind: .saveFailed, message: "Save failed: invalid output at \(destination.clipFile.path(percentEncoded: false)) (\(details))"))
            throw CaptureCoordinatorError.invalidClipOutput
        }
        onDiagnosticEvent?(CaptureDiagnosticEvent(kind: .outputValidated, message: "Output validated: \(destination.clipFile.path(percentEncoded: false))"))

        var clip = Clip(
            gameID: game.id,
            gameName: game.displayName,
            sourceAppName: sourceAppName,
            capturedAt: capturedAt,
            durationSeconds: Self.clipDurationSeconds(requested: requestedDurationSeconds, selectedSegments: selectedSegments),
            presetName: preset.displayName,
            folderURL: destination.folder,
            clipURL: destination.clipFile,
            metadataURL: destination.metadataFile,
            thumbnailURL: destination.thumbnailFile
        )
        do {
            clip.bookmarks = bookmarks
            if !bookmarks.isEmpty {
                do { try JSONEncoder().encode(bookmarks).write(to: destination.folder.appendingPathComponent("bookmarks.json"), options: .atomic) }
                catch { onDiagnosticEvent?(.init(kind: .companionWarning, message: "Bookmark sidecar could not be saved: \(error.localizedDescription)")) }
            }
            if keepsEditableAudio, selectedSegments.contains(where: { $0.audioGains.count > 1 }) {
                let sourceURL = destination.folder.appendingPathComponent("editable-source.mov")
                do {
                    _ = try await ReplayComposer(preservesAudioTracks: true).compose(
                        segments: selectedSegments, outputURL: sourceURL,
                        targetDurationSeconds: requestedDurationSeconds, audioGain: 1)
                    guard Self.isValidClipOutput(sourceURL) else { throw CaptureCoordinatorError.invalidClipOutput }
                    clip.editableSourceURL = sourceURL
                    clip.audioTracks = (selectedSegments.first?.audioSources ?? []).enumerated().map {
                        ClipAudioTrack(trackIndex: $0.offset, source: $0.element)
                    }
                } catch {
                    try? FileManager.default.removeItem(at: sourceURL)
                    onDiagnosticEvent?(.init(kind: .editableAudioFailed, message: "Mixed video saved; editable audio source failed: \(error.localizedDescription)"))
                }
            }
            do {
                if let sidecars = try await FrameBarPlugin.export(entries: telemetry, folder: destination.folder) {
                    clip.telemetryURL = sidecars.0
                    clip.subtitleURL = sidecars.1
                }
            } catch {
                onDiagnosticEvent?(CaptureDiagnosticEvent(kind: .companionWarning, message: "Telemetry sidecar could not be saved: \(error.localizedDescription)"))
            }
            try await Self.writeMetadata(for: clip, to: destination.metadataFile)
            onDiagnosticEvent?(CaptureDiagnosticEvent(kind: .metadataWritten, message: "Metadata written: \(destination.metadataFile.path(percentEncoded: false))"))

            var clips = try await clipIndexStore.loadAsync()
            clips.insert(clip, at: 0)
            try await clipIndexStore.saveAsync(clips)
        } catch {
            cleanupFailedDestination(destination)
            onDiagnosticEvent?(CaptureDiagnosticEvent(kind: .saveFailed, message: "Save failed during clip indexing: \(error.localizedDescription)"))
            throw error
        }
        onDiagnosticEvent?(CaptureDiagnosticEvent(kind: .clipIndexed, message: "Clip indexed: \(clip.clipURL.path(percentEncoded: false))"))
        scheduleThumbnailGeneration(for: destination)
        return clip
    }

    nonisolated static func isValidClipOutput(_ url: URL, fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize,
              fileSize > 0 else {
            return false
        }
        return true
    }

    private nonisolated static func clipDurationSeconds(requested: TimeInterval, selectedSegments: [ReplaySegment]) -> Int {
        let available = selectedSegments.reduce(0) { $0 + $1.durationSeconds }
        let duration = min(max(requested, 1), max(available, 1))
        return max(1, Int(duration.rounded()))
    }

    private nonisolated static func outputDiagnostics(for url: URL, fileManager: FileManager = .default) -> String {
        guard fileManager.fileExists(atPath: url.path) else {
            return "file missing"
        }

        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return "file exists, size unavailable"
        }

        return "file exists, \(fileSize) bytes"
    }

    private nonisolated static func writeMetadata(for clip: Clip, to url: URL) async throws {
        try await Task.detached(priority: .utility) {
            let metadata = try JSONEncoder.capturely.encode(clip)
            try metadata.write(to: url, options: [.atomic])
        }.value
    }

    private func cleanupFailedDestination(_ destination: ClipDestination) {
        try? FileManager.default.removeItem(at: destination.folder.appendingPathComponent("telemetry.json"))
        try? FileManager.default.removeItem(at: destination.folder.appendingPathComponent("telemetry.csv"))
        try? FileManager.default.removeItem(at: destination.folder.appendingPathComponent("clip.srt"))
        try? FileManager.default.removeItem(at: destination.folder.appendingPathComponent("editable-source.mov"))
        try? FileManager.default.removeItem(at: destination.clipFile)
        try? FileManager.default.removeItem(at: destination.thumbnailFile)
        try? FileManager.default.removeItem(at: destination.metadataFile)
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: destination.folder.path),
           contents.isEmpty {
            try? FileManager.default.removeItem(at: destination.folder)
        }
    }

    private func scheduleThumbnailGeneration(for destination: ClipDestination) {
        let thumbnailGenerator = thumbnailGenerator
        let onDiagnosticEvent = onDiagnosticEvent
        Task.detached(priority: .utility) {
            if (try? await thumbnailGenerator.generateThumbnail(for: destination.clipFile, outputURL: destination.thumbnailFile)) != nil {
                onDiagnosticEvent?(CaptureDiagnosticEvent(kind: .thumbnailGenerated, message: "Thumbnail generated: \(destination.thumbnailFile.path(percentEncoded: false))"))
            }
        }
    }

    private nonisolated static let minimumActiveSegmentFlushDurationSeconds: TimeInterval = 0
}

extension CaptureCoordinator: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if sampleBuffer.isValid {
            nonisolated(unsafe) let sampleBuffer = sampleBuffer
            replaySegmentWriter.append(sampleBuffer: sampleBuffer, type: type)
        }
    }

    nonisolated static func cappedCaptureSize(width: Int, height: Int, maximumHeight: Int) -> (width: Int, height: Int) {
        guard width > 0, height > 0, maximumHeight > 0 else {
            return (max(1, width), max(1, height))
        }

        let maximumWidth = max(1, Int((Double(maximumHeight) * Self.captureAspectWidthRatio).rounded()))
        let scale = min(1, Double(maximumHeight) / Double(height), Double(maximumWidth) / Double(width))
        let cappedWidth = max(2, Int(Double(width) * scale) / 2 * 2)
        let cappedHeight = max(2, Int(Double(height) * scale) / 2 * 2)
        return (cappedWidth, cappedHeight)
    }

    nonisolated static let streamPixelFormatForEncoding = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

    nonisolated static func resolvedAudioSources(
        preset: CapturePreset,
        isolatedAudioSources: [AudioSourceDescriptor],
        microphoneDeviceID: String?
    ) -> [AudioSourceDescriptor] {
        var sources = preset.recordsSystemAudio
            ? Array(isolatedAudioSources.filter { $0.kind == .application }.prefix(4))
            : []
        if preset.recordsSystemAudio, sources.isEmpty,
           let system = preset.audioSources.first(where: { $0.kind == .system }) {
            sources.append(system)
        }
        if preset.recordsMicrophone,
           let microphone = preset.audioSources.first(where: { $0.kind == .microphone }) {
            sources.append(.microphone(deviceID: microphoneDeviceID, gain: microphone.gain))
        }
        return sources
    }

    private nonisolated static let captureAspectWidthRatio = 16.0 / 9.0
}

extension CaptureCoordinator: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        nonisolated(unsafe) let stoppedStream = stream
        Task { @MainActor [weak self] in
            guard let self, self.stream === stoppedStream else { return }
            self.stream = nil
            await self.applicationAudioCapture.stop()
            await self.replaySegmentWriter.stopRecording()
            self.state = .failed(message: error.localizedDescription)
            self.onDiagnosticEvent?(.init(kind: .saveFailed, message: "Capture stopped: \(error.localizedDescription)"))
        }
    }
}

enum CaptureCoordinatorError: Error, Equatable {
    case noReplaySegmentsAvailable
    case invalidClipOutput
}

extension CaptureCoordinatorError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noReplaySegmentsAvailable:
            return "Replay buffer is empty"
        case .invalidClipOutput:
            return "Replay export did not create a valid clip file"
        }
    }
}

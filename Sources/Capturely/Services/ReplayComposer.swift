import AVFoundation
import AppKit
import Foundation

protocol ReplayComposing: Sendable {
    func compose(segments: [ReplaySegment], outputURL: URL, targetDurationSeconds: TimeInterval?, audioGain: Double) async throws -> ReplayCompositionResult
}

protocol ThumbnailGenerating: Sendable {
    func generateThumbnail(for videoURL: URL, outputURL: URL) async throws
}

struct ReplayComposer: ReplayComposing {
    var preservesAudioTracks = false
    func compose(segments: [ReplaySegment], outputURL: URL, targetDurationSeconds: TimeInterval? = nil, audioGain: Double = 1) async throws -> ReplayCompositionResult {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let strategy = try await Task.detached(priority: .utility) {
            try await composeOnWorker(
                segments: preservesAudioTracks ? segments.map { segment in
                    var source = segment
                    source.audioGains = []
                    return source
                } : segments,
                outputURL: outputURL,
                targetDurationSeconds: targetDurationSeconds,
                audioGain: preservesAudioTracks ? 1 : audioGain
            )
        }.value
        return ReplayCompositionResult(
            strategy: strategy,
            elapsedMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        )
    }

    private func composeOnWorker(segments: [ReplaySegment], outputURL: URL, targetDurationSeconds: TimeInterval?, audioGain: Double) async throws -> ReplayCompositionStrategy {
        let usableSegments = segments.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        if Self.canCopySingleSegmentWithoutExport(segments: usableSegments, targetDurationSeconds: targetDurationSeconds, audioGain: audioGain),
           let segment = usableSegments.first {
            try? FileManager.default.removeItem(at: outputURL)
            try FileManager.default.copyItem(at: segment.url, to: outputURL)
            return .directSegmentCopy
        }

        if Self.ffmpegURL() != nil {
            do {
                return try await exportWithFFmpegFallback(
                    segments: usableSegments,
                    outputURL: outputURL,
                    targetDurationSeconds: targetDurationSeconds,
                    audioGain: audioGain,
                    originalError: ReplayComposerError.exportFailed("Video stream copy requested")
                )
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ReplayComposerError.cannotCreateVideoTrack
        }
        var audioTracks: [AVMutableCompositionTrack] = []

        var preparedSegments: [PreparedReplaySegment] = []
        for segment in usableSegments {
            let asset = AVURLAsset(url: segment.url)
            let videoTracks: [AVAssetTrack]
            do {
                videoTracks = try await asset.loadTracks(withMediaType: .video)
            } catch {
                continue
            }

            guard let sourceTrack = videoTracks.first else {
                continue
            }
            let duration: CMTime
            do {
                duration = try await asset.load(.duration)
            } catch {
                continue
            }
            guard duration.seconds.isFinite, duration.seconds > 0 else { continue }
            let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)
            while audioTracks.count < sourceAudioTracks.count {
                guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    throw ReplayComposerError.cannotCreateExporter
                }
                audioTracks.append(track)
            }
            preparedSegments.append(
                PreparedReplaySegment(
                    videoTrack: sourceTrack,
                    audioTracks: sourceAudioTracks,
                    duration: duration,
                    url: segment.url
                )
            )
        }

        let totalDurationSeconds = preparedSegments.reduce(0) { $0 + $1.duration.seconds }
        guard totalDurationSeconds > 0 else {
            throw ReplayComposerError.noUsableSegments
        }

        let requestedDurationSeconds = targetDurationSeconds.map { min(max($0, 0), totalDurationSeconds) } ?? totalDurationSeconds
        var leadingTrimSeconds = max(totalDurationSeconds - requestedDurationSeconds, 0)
        var cursor = CMTime.zero
        var skippedSegmentMessages: [String] = []
        for segment in preparedSegments {
            let segmentDurationSeconds = segment.duration.seconds
            if leadingTrimSeconds >= segmentDurationSeconds {
                leadingTrimSeconds -= segmentDurationSeconds
                continue
            }

            let sourceStartSeconds = leadingTrimSeconds
            let insertionDurationSeconds = segmentDurationSeconds - sourceStartSeconds
            leadingTrimSeconds = 0

            let sourceStart = CMTime(seconds: sourceStartSeconds, preferredTimescale: segment.duration.timescale)
            let insertionDuration = CMTime(seconds: insertionDurationSeconds, preferredTimescale: segment.duration.timescale)
            let sourceRange = CMTimeRange(start: sourceStart, duration: insertionDuration)
            do {
                try videoTrack.insertTimeRange(sourceRange, of: segment.videoTrack, at: cursor)
            } catch {
                skippedSegmentMessages.append("\(segment.url.lastPathComponent): \(Self.describe(error))")
                continue
            }
            for (index, sourceAudioTrack) in segment.audioTracks.enumerated() {
                let availableRange = try await sourceAudioTrack.load(.timeRange)
                let audioRange = CMTimeRangeGetIntersection(sourceRange, otherRange: availableRange)
                if audioRange.duration.seconds > 0 {
                    try audioTracks[index].insertTimeRange(audioRange, of: sourceAudioTrack, at: cursor + audioRange.start - sourceStart)
                }
            }
            cursor = cursor + insertionDuration
        }

        guard cursor.seconds.isFinite, cursor.seconds > 0 else {
            return try await exportWithFFmpegFallback(
                segments: usableSegments,
                outputURL: outputURL,
                targetDurationSeconds: targetDurationSeconds,
                audioGain: audioGain,
                originalError: ReplayComposerError.exportFailed("No segments could be inserted into the AVFoundation composition: \(skippedSegmentMessages.joined(separator: "; "))")
            )
        }

        let strategy: ReplayCompositionStrategy
        do {
            strategy = try await export(composition: composition, outputURL: outputURL, audioGain: audioGain, sourceGains: usableSegments.first?.audioGains ?? [])
        } catch {
            return try await exportWithFFmpegFallback(
                segments: usableSegments,
                outputURL: outputURL,
                targetDurationSeconds: targetDurationSeconds,
                audioGain: audioGain,
                originalError: error
            )
        }

        if !Self.isUsableOutput(outputURL) {
            return try await exportWithFFmpegFallback(
                segments: usableSegments,
                outputURL: outputURL,
                targetDurationSeconds: targetDurationSeconds,
                audioGain: audioGain,
                originalError: ReplayComposerError.exportFailed("AVFoundation export did not create a usable output")
            )
        }

        return strategy
    }

    private func export(composition: AVMutableComposition, outputURL: URL, audioGain: Double, sourceGains: [Double]) async throws -> ReplayCompositionStrategy {
        let needsMix = sourceGains.count > 1 || sourceGains.contains { !Self.canPassthroughAudioGain($0) } || !Self.canPassthroughAudioGain(audioGain)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: needsMix ? AVAssetExportPresetHighestQuality : AVAssetExportPresetPassthrough) else {
            throw ReplayComposerError.cannotCreateExporter
        }
        exporter.audioMix = Self.audioMix(for: composition, gain: audioGain, sourceGains: sourceGains)
        if #available(macOS 14.0, *) {
            exporter.allowsParallelizedExport = false
        }

        do {
            try await exporter.export(to: outputURL, as: .mov)
            return needsMix ? .avFoundationAudioMix : .avFoundationPassthrough
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private func exportWithFFmpegFallback(
        segments: [ReplaySegment],
        outputURL: URL,
        targetDurationSeconds: TimeInterval?,
        audioGain: Double,
        originalError: Error
    ) async throws -> ReplayCompositionStrategy {
        guard let ffmpegURL = Self.ffmpegURL() else {
            throw ReplayComposerError.exportFailed("\(originalError.localizedDescription); ffmpeg fallback unavailable")
        }

        let validSegments = segments.filter { Self.isUsableOutput($0.url) }
        guard !validSegments.isEmpty else {
            throw ReplayComposerError.exportFailed("\(originalError.localizedDescription); no usable ffmpeg input segments")
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Capturely-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let concatFile = temporaryDirectory.appendingPathComponent("segments.txt")
        let concatBody = validSegments
            .map { "file '\(Self.ffmpegEscapedPath($0.url.path))'" }
            .joined(separator: "\n")
        try concatBody.write(to: concatFile, atomically: true, encoding: .utf8)

        let totalDuration = validSegments.reduce(0) { $0 + $1.durationSeconds }
        let requestedDuration = targetDurationSeconds.map { min(max($0, 0), totalDuration) } ?? totalDuration
        let leadingTrim = max(totalDuration - requestedDuration, 0)

        try? FileManager.default.removeItem(at: outputURL)
        var arguments = [
            "-nostdin", "-hide_banner", "-loglevel", "error",
            "-threads", "1", "-filter_threads", "1", "-filter_complex_threads", "1",
            "-y",
            "-f", "concat",
            "-safe", "0",
            "-i", concatFile.path
        ]
        if leadingTrim > 0 {
            arguments += ["-ss", String(format: "%.3f", leadingTrim)]
        }
        if requestedDuration > 0 {
            arguments += ["-t", String(format: "%.3f", requestedDuration)]
        }
        let sourceGains = validSegments.first?.audioGains ?? []
        let needsMix = Self.needsAudioMix(segments: validSegments) || !Self.canPassthroughAudioGain(audioGain)
        if !needsMix {
            arguments += [
                "-map", "0:v:0", "-map", "0:a?", "-c", "copy",
                outputURL.path
            ]
        } else {
            if sourceGains.count > 1 {
                let inputs = sourceGains.enumerated().map { index, gain in
                    "[0:a:\(index)]volume=\(Self.clampedAudioGain(gain * audioGain))[a\(index)]"
                }.joined(separator: ";")
                let labels = sourceGains.indices.map { "[a\($0)]" }.joined()
                arguments += ["-filter_complex", "\(inputs);\(labels)amix=inputs=\(sourceGains.count):normalize=0:duration=longest,alimiter=limit=0.98:level=0[mix]", "-map", "0:v:0", "-map", "[mix]"]
            } else {
                arguments += ["-map", "0:v:0", "-map", "0:a?", "-filter:a", "volume=\(Self.clampedAudioGain((sourceGains.first ?? 1) * audioGain))"]
            }
            arguments += ["-c:v", "copy", "-c:a", "aac", "-threads:a", "1", "-b:a", "192k", outputURL.path]
        }

        let process = Process()
        process.qualityOfService = .utility
        process.executableURL = ffmpegURL
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        // Drain stderr while the process runs; a full pipe must never block clip saving.
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                errorPipe.fileHandleForReading.readabilityHandler = nil
                if process.terminationStatus == 0, Self.isUsableOutput(outputURL) {
                    continuation.resume()
                } else {
                    let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: data, encoding: .utf8)?
                        .split(separator: "\n")
                        .suffix(4)
                        .joined(separator: " ")
                    continuation.resume(throwing: ReplayComposerError.exportFailed(
                        "\(Self.describe(originalError)); ffmpeg: \(message ?? "exit \(process.terminationStatus)")"
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ReplayComposerError.exportFailed(
                    "\(Self.describe(originalError)); ffmpeg launch failed: \(Self.describe(error))"
                ))
            }
        }

        return needsMix ? .ffmpegAudioOnly : .ffmpegStreamCopy
    }

    private nonisolated static func ffmpegURL() -> URL? {
        [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private nonisolated static func ffmpegEscapedPath(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "'\\''")
    }

    private nonisolated static func isUsableOutput(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return false
        }
        return fileSize > 0
    }

    private nonisolated static func clampedAudioGain(_ gain: Double) -> Double {
        min(max(gain, 0), 1.5)
    }

    private static func audioMix(for composition: AVMutableComposition, gain: Double, sourceGains: [Double]) -> AVAudioMix? {
        guard sourceGains.count > 1 || sourceGains.contains(where: { !canPassthroughAudioGain($0) }) || !canPassthroughAudioGain(gain) else { return nil }
        let parameters = composition.tracks(withMediaType: .audio).enumerated().map { index, track in
            let parameter = AVMutableAudioMixInputParameters(track: track)
            let sourceGain = sourceGains.indices.contains(index) ? sourceGains[index] : 1
            parameter.setVolume(Float(clampedAudioGain(gain * sourceGain)), at: .zero)
            return parameter
        }
        guard !parameters.isEmpty else { return nil }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = parameters
        return audioMix
    }

    private nonisolated static func exportPresetName(forAudioGain gain: Double) -> String {
        canPassthroughAudioGain(gain) ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
    }

    nonisolated static func shouldPreferFFmpegAudioOnlyExport(audioGain gain: Double, ffmpegAvailable: Bool) -> Bool {
        ffmpegAvailable && !canPassthroughAudioGain(gain)
    }

    nonisolated static func shouldPreferFFmpegStreamCopy(segments: [ReplaySegment], audioGain: Double, ffmpegAvailable: Bool) -> Bool {
        ffmpegAvailable && !needsAudioMix(segments: segments) && canPassthroughAudioGain(audioGain) && segments.count > 1
    }

    nonisolated static func needsAudioMix(segments: [ReplaySegment]) -> Bool {
        segments.contains { $0.audioGains.count > 1 || $0.audioGains.contains { !canPassthroughAudioGain($0) } }
    }

    nonisolated static func canCopySingleSegmentWithoutExport(
        segments: [ReplaySegment],
        targetDurationSeconds: TimeInterval?,
        audioGain: Double
    ) -> Bool {
        guard !needsAudioMix(segments: segments), canPassthroughAudioGain(audioGain),
              segments.count == 1,
              let segment = segments.first else {
            return false
        }

        guard let targetDurationSeconds else { return true }
        return targetDurationSeconds >= segment.durationSeconds - Self.singleSegmentCopyDurationTolerance
    }

    private nonisolated static func canPassthroughAudioGain(_ gain: Double) -> Bool {
        abs(clampedAudioGain(gain) - 1) < 0.001
    }

    private nonisolated static let singleSegmentCopyDurationTolerance: TimeInterval = 0.05

    private nonisolated static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain != NSCocoaErrorDomain || nsError.code != 0 else {
            return error.localizedDescription
        }

        return "\(error.localizedDescription) (\(nsError.domain) \(nsError.code))"
    }
}

struct ReplayCompositionResult: Equatable, Sendable {
    var strategy: ReplayCompositionStrategy
    var elapsedMilliseconds: Double
}

enum ReplayCompositionStrategy: String, Equatable, Sendable {
    case directSegmentCopy = "Direct segment copy"
    case avFoundationPassthrough = "AVFoundation passthrough"
    case avFoundationAudioMix = "AVFoundation audio mix"
    case ffmpegStreamCopy = "ffmpeg stream copy"
    case ffmpegAudioOnly = "ffmpeg audio-only"
}

enum ReplayComposerError: Error {
    case cannotCreateVideoTrack
    case cannotCreateExporter
    case noUsableSegments
    case exportFailed(String)
}

extension ReplayComposerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .cannotCreateVideoTrack:
            return "Could not create video composition track"
        case .cannotCreateExporter:
            return "Could not create replay exporter"
        case .noUsableSegments:
            return "Replay buffer has no usable video segments"
        case .exportFailed(let message):
            return "Replay export failed: \(message)"
        }
    }
}

private struct PreparedReplaySegment {
    var videoTrack: AVAssetTrack
    var audioTracks: [AVAssetTrack]
    var duration: CMTime
    var url: URL
}

struct VideoThumbnailGenerator: ThumbnailGenerating {
    func generateThumbnail(for videoURL: URL, outputURL: URL) async throws {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)
        let cgImage = try await generator.image(at: .zero).image
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else {
            throw ReplayThumbnailError.cannotEncodeThumbnail
        }
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: outputURL, options: [.atomic])
    }
}

enum ReplayThumbnailError: Error {
    case cannotEncodeThumbnail
}

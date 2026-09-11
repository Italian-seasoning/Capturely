import AVFoundation
import Foundation
import ScreenCaptureKit
import VideoToolbox

struct ReplaySegment: Equatable, Sendable {
    var url: URL
    var startedAt: Date
    var durationSeconds: TimeInterval
    var audioGains: [Double] = []
}

final class ReplaySegmentWriter: @unchecked Sendable {
    private var segments: [ReplaySegment] = []
    private var lastVideoSampleAt: Date?
    private var lastAudioSampleAt: Date?
    private var audioStatus: AudioTrackStatus = .none
    private var audioLevel: Double = 0
    private var audioQualityScore: Double = 0
    private var recentAudioLevels: [Double] = []
    private var audioSampleRate: Double?
    private var audioChannelCount: Int = 0
    var onDiagnosticEvent: (@Sendable (CaptureDiagnosticEvent) -> Void)?
    var onAudioMonitorUpdated: (@Sendable () -> Void)?

    private let directory: URL
    private var maximumDurationSeconds: TimeInterval
    private let segmentDurationSeconds: TimeInterval
    private let fileManager: FileManager
    private let processingQueue: DispatchQueue
    private var activeSegment: ActiveReplaySegment?
    private var finishingSegmentDurations: [URL: TimeInterval] = [:]
    private var segmentFinishWaiters: [@Sendable () -> Void] = []
    private var preset: CapturePreset = .balanced
    private var hasReportedFirstVideoSample = false
    private var hasReportedFirstAudioSample = false
    private var lastVideoTimestampUpdateAt = -Double.greatestFiniteMagnitude
    private var lastAudioTimestampUpdateAt = -Double.greatestFiniteMagnitude
    private var lastAudioMonitorUpdateAt = -Double.greatestFiniteMagnitude
    private var lastAudioMonitorAnalysisAt = -Double.greatestFiniteMagnitude
    private var performance = CapturePerformanceSnapshot.empty
    private var totalVideoAppendMilliseconds: Double = 0
    private var totalAudioAppendMilliseconds: Double = 0
    private var measuredVideoAppendCount = 0
    private var measuredAudioAppendCount = 0

    init(
        directory: URL,
        maximumDurationSeconds: TimeInterval,
        segmentDurationSeconds: TimeInterval = ReplaySegmentWriter.defaultSegmentDurationSeconds,
        fileManager: FileManager = .default,
        processingQueue: DispatchQueue = DispatchQueue(label: "capturely.replay.writer", qos: .utility)
    ) {
        self.directory = directory
        self.maximumDurationSeconds = maximumDurationSeconds
        self.segmentDurationSeconds = segmentDurationSeconds
        self.fileManager = fileManager
        self.processingQueue = processingQueue
    }

    func startRecording(preset: CapturePreset) throws {
        try processingQueue.sync {
            self.preset = preset
            lastVideoSampleAt = nil
            lastAudioSampleAt = nil
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try removeStaleTemporarySegments()
            audioStatus = preset.recordsSystemAudio || preset.recordsMicrophone ? .expectedButMissing : .none
            audioLevel = 0
            audioQualityScore = 0
            recentAudioLevels = []
            audioSampleRate = nil
            audioChannelCount = 0
            lastVideoTimestampUpdateAt = -Double.greatestFiniteMagnitude
            lastAudioTimestampUpdateAt = -Double.greatestFiniteMagnitude
            lastAudioMonitorUpdateAt = -Double.greatestFiniteMagnitude
            lastAudioMonitorAnalysisAt = -Double.greatestFiniteMagnitude
            performance = CapturePerformanceSnapshot(startedAt: Date())
            totalVideoAppendMilliseconds = 0
            totalAudioAppendMilliseconds = 0
            measuredVideoAppendCount = 0
            measuredAudioAppendCount = 0
            hasReportedFirstVideoSample = false
            hasReportedFirstAudioSample = false
        }
    }

    func updateMaximumDurationSeconds(_ seconds: TimeInterval) {
        processingQueue.sync {
            maximumDurationSeconds = max(1, seconds)
            trimSegments(now: Date())
        }
    }

    func stopRecording() async {
        await finishActiveSegmentAndWait()
        await waitForPendingSegmentFinishes()
    }

    func flushActiveSegmentForClip(minimumDurationSeconds: TimeInterval = 0) async {
        await finishActiveSegmentAndWait(minimumDurationSeconds: minimumDurationSeconds)
        await waitForPendingSegmentFinishes()
    }

    func registerCompletedSegment(url: URL, startedAt: Date, durationSeconds: TimeInterval) {
        processingQueue.sync {
            registerCompletedSegmentOnQueue(url: url, startedAt: startedAt, durationSeconds: durationSeconds)
        }
    }

    func recentSegments(forReplayDuration replayDuration: TimeInterval) -> [ReplaySegment] {
        processingQueue.sync {
            recentSegmentsOnQueue(forReplayDuration: replayDuration)
        }
    }

    // Hard links keep an in-flight export alive even as the rolling buffer expires.
    func snapshotSegments(forReplayDuration duration: TimeInterval, to snapshotDirectory: URL) throws -> [ReplaySegment] {
        try processingQueue.sync {
            try fileManager.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
            return try recentSegmentsOnQueue(forReplayDuration: duration).map { segment in
                var snapshot = segment
                snapshot.url = snapshotDirectory.appendingPathComponent(segment.url.lastPathComponent)
                do {
                    try fileManager.linkItem(at: segment.url, to: snapshot.url)
                } catch {
                    try fileManager.copyItem(at: segment.url, to: snapshot.url)
                }
                return snapshot
            }
        }
    }

    private func recentSegmentsOnQueue(forReplayDuration replayDuration: TimeInterval) -> [ReplaySegment] {
            let total = segments.reduce(0) { $0 + $1.durationSeconds }
            var remaining = min(total, replayDuration)
            var selected: [ReplaySegment] = []

            for segment in segments.reversed() {
                guard remaining > 0 else { break }
                selected.append(segment)
                remaining -= segment.durationSeconds
            }

            return selected.reversed()
    }

    var activeSegmentCount: Int {
        processingQueue.sync {
            segments.count + finishingSegmentDurations.count + (activeSegment == nil ? 0 : 1)
        }
    }

    var currentBufferDurationSeconds: TimeInterval {
        processingQueue.sync {
            bufferDurationSecondsOnQueue
        }
    }

    var healthMetrics: (
        activeSegmentCount: Int,
        currentBufferDurationSeconds: TimeInterval,
        lastVideoSampleAt: Date?,
        lastAudioSampleAt: Date?,
        audioStatus: AudioTrackStatus,
        audioLevel: Double,
        audioQualityScore: Double,
        recentAudioLevels: [Double],
        audioSampleRate: Double?,
        audioChannelCount: Int,
        performance: CapturePerformanceSnapshot
    ) {
        processingQueue.sync {
            (
                activeSegmentCount: segments.count + finishingSegmentDurations.count + (activeSegment == nil ? 0 : 1),
                currentBufferDurationSeconds: bufferDurationSecondsOnQueue,
                lastVideoSampleAt: lastVideoSampleAt,
                lastAudioSampleAt: lastAudioSampleAt,
                audioStatus: audioStatus,
                audioLevel: audioLevel,
                audioQualityScore: audioQualityScore,
                recentAudioLevels: recentAudioLevels,
                audioSampleRate: audioSampleRate,
                audioChannelCount: audioChannelCount,
                performance: performance
            )
        }
    }

    func append(sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        nonisolated(unsafe) let sampleBuffer = sampleBuffer

        // ScreenCaptureKit owns the bounded queue. Do not retain unbounded pixel
        // buffers in a second asynchronous queue when the encoder falls behind.
        processingQueue.sync { [weak self] in
            switch type {
            case .screen:
                self?.appendVideo(sampleBuffer)
            case .audio, .microphone:
                self?.appendAudio(sampleBuffer, type: type)
            @unknown default:
                return
            }
        }
    }

    private func finishActiveSegmentAndWait(minimumDurationSeconds: TimeInterval = 0) async {
        await withCheckedContinuation { continuation in
            processingQueue.async {
                if minimumDurationSeconds > 0,
                   !self.segments.isEmpty,
                   let activeSegment = self.activeSegment,
                   activeSegment.estimatedDurationSeconds < minimumDurationSeconds {
                    continuation.resume()
                    return
                }
                self.finishActiveSegment {
                    continuation.resume()
                }
            }
        }
    }

    private func waitForPendingSegmentFinishes() async {
        await withCheckedContinuation { continuation in
            processingQueue.async {
                guard !self.finishingSegmentDurations.isEmpty else {
                    continuation.resume()
                    return
                }
                self.segmentFinishWaiters.append {
                    continuation.resume()
                }
            }
        }
    }

    private var bufferDurationSecondsOnQueue: TimeInterval {
        segments.reduce(0) { $0 + $1.durationSeconds }
            + finishingSegmentDurations.values.reduce(0, +)
            + (activeSegment?.estimatedDurationSeconds ?? 0)
    }

    private func trimSegments(now: Date) {
        var accumulated: TimeInterval = 0
        var kept: [ReplaySegment] = []

        for segment in segments.reversed() {
            if accumulated < maximumDurationSeconds {
                kept.append(segment)
                accumulated += segment.durationSeconds
            } else {
                try? fileManager.removeItem(at: segment.url)
            }
        }

        segments = kept.reversed()
    }

    private func registerCompletedSegmentOnQueue(url: URL, startedAt: Date, durationSeconds: TimeInterval) {
        segments.append(ReplaySegment(url: url, startedAt: startedAt, durationSeconds: durationSeconds, audioGains: preset.audioGains ?? []))
        segments.sort { $0.startedAt < $1.startedAt }
        trimSegments(now: Date())
    }

    private func removeStaleTemporarySegments() throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for url in contents where url.lastPathComponent.hasPrefix("segment-") && url.pathExtension == "mov" {
            try? fileManager.removeItem(at: url)
        }
        segments = segments.filter { fileManager.fileExists(atPath: $0.url.path) }
    }

    private func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        performance.videoSamplesReceived += 1
        updateVideoSampleTimestampIfNeeded()
        guard CMSampleBufferDataIsReady(sampleBuffer), Self.isCompleteScreenFrame(sampleBuffer) else {
            performance.incompleteVideoFramesDropped += 1
            return
        }

        let sourceTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard sourceTime.isValid else { return }
        updateVideoSampleTimestampIfNeeded()
        if !hasReportedFirstVideoSample {
            hasReportedFirstVideoSample = true
            onDiagnosticEvent?(CaptureDiagnosticEvent(kind: .firstVideoSampleReceived, message: "First video sample received"))
        }

        if let activeSegment {
            let elapsed = CMTimeSubtract(sourceTime, activeSegment.sourceStartedAt).seconds
            if elapsed >= segmentDurationSeconds {
                finishActiveSegment()
            }
        }

        if activeSegment == nil {
            do {
                activeSegment = try makeActiveSegment(from: sampleBuffer, sourceStartedAt: sourceTime)
            } catch {
                onDiagnosticEvent?(CaptureDiagnosticEvent(kind: .saveFailed, message: "Encoder could not start: \(error.localizedDescription)"))
                return
            }
        }

        guard var activeSegment else { return }
        guard activeSegment.videoInput.isReadyForMoreMediaData else {
            performance.videoInputBackpressureDrops += 1
            return
        }

        let shouldMeasureAppend = shouldMeasureVideoAppend()
        let appendStartedAt = shouldMeasureAppend ? ProcessInfo.processInfo.systemUptime : 0
        if activeSegment.videoInput.append(sampleBuffer) {
            performance.videoSamplesAppended += 1
            if shouldMeasureAppend {
                measuredVideoAppendCount += 1
                totalVideoAppendMilliseconds += (ProcessInfo.processInfo.systemUptime - appendStartedAt) * 1_000
                performance.averageVideoAppendMilliseconds = totalVideoAppendMilliseconds / Double(max(measuredVideoAppendCount, 1))
            }
            activeSegment.lastSourceTime = sourceTime
            self.activeSegment = activeSegment
        } else {
            onDiagnosticEvent?(CaptureDiagnosticEvent(kind: .saveFailed, message: "Video sample append failed"))
        }
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) {
        performance.audioSamplesReceived += 1
        let now = ProcessInfo.processInfo.systemUptime
        updateAudioSampleTimestampIfNeeded(now: now)
        audioStatus = audioStatus(for: type)
        if now - lastAudioMonitorAnalysisAt >= Self.audioMonitorAnalysisInterval {
            lastAudioMonitorAnalysisAt = now
            let monitor = Self.audioMonitorMetrics(from: sampleBuffer)
            audioLevel = (audioLevel * 0.68) + (monitor.level * 0.32)
            audioQualityScore = monitor.qualityScore
            recentAudioLevels.append(audioLevel)
            if recentAudioLevels.count > 28 {
                recentAudioLevels.removeFirst(recentAudioLevels.count - 28)
            }
            audioSampleRate = monitor.sampleRate
            audioChannelCount = monitor.channelCount
        }
        if !hasReportedFirstAudioSample {
            hasReportedFirstAudioSample = true
            onDiagnosticEvent?(CaptureDiagnosticEvent(kind: .firstAudioSampleReceived, message: "First audio sample received"))
        }
        publishAudioMonitorUpdateIfNeeded()

        guard var activeSegment,
              let audioInput = type == .microphone ? activeSegment.microphoneInput : activeSegment.audioInput,
              audioInput.isReadyForMoreMediaData else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard timestamp.isNumeric, timestamp >= activeSegment.sourceStartedAt else { return }

        let shouldMeasureAppend = shouldMeasureAudioAppend()
        let appendStartedAt = shouldMeasureAppend ? ProcessInfo.processInfo.systemUptime : 0
        if audioInput.append(sampleBuffer) {
            performance.audioSamplesAppended += 1
            if shouldMeasureAppend {
                measuredAudioAppendCount += 1
                totalAudioAppendMilliseconds += (ProcessInfo.processInfo.systemUptime - appendStartedAt) * 1_000
                performance.averageAudioAppendMilliseconds = totalAudioAppendMilliseconds / Double(max(measuredAudioAppendCount, 1))
            }
            let sourceTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if sourceTime.isValid {
                activeSegment.lastSourceTime = max(activeSegment.lastSourceTime, sourceTime)
                self.activeSegment = activeSegment
            }
        }
    }

    private func updateVideoSampleTimestampIfNeeded(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard now - lastVideoTimestampUpdateAt >= Self.sampleTimestampUpdateInterval else { return }
        lastVideoTimestampUpdateAt = now
        lastVideoSampleAt = Date()
    }

    private func updateAudioSampleTimestampIfNeeded(now: TimeInterval) {
        guard now - lastAudioTimestampUpdateAt >= Self.sampleTimestampUpdateInterval else { return }
        lastAudioTimestampUpdateAt = now
        lastAudioSampleAt = Date()
    }

    private func shouldMeasureVideoAppend() -> Bool {
        performance.videoSamplesReceived == 1 || performance.videoSamplesReceived.isMultiple(of: Self.videoAppendTimingSampleInterval)
    }

    private func shouldMeasureAudioAppend() -> Bool {
        performance.audioSamplesReceived == 1 || performance.audioSamplesReceived.isMultiple(of: Self.audioAppendTimingSampleInterval)
    }

    private func audioStatus(for type: SCStreamOutputType) -> AudioTrackStatus {
        switch (preset.recordsSystemAudio, preset.recordsMicrophone, type) {
        case (true, true, _):
            return .gameAndMic
        case (true, false, .audio):
            return .gameOnly
        case (false, true, .microphone):
            return .micOnly
        default:
            return audioStatus
        }
    }

    private func finishActiveSegment(onComplete: (@Sendable () -> Void)? = nil) {
        guard let activeSegment else {
            onComplete?()
            return
        }
        self.activeSegment = nil

        activeSegment.videoInput.markAsFinished()
        activeSegment.audioInput?.markAsFinished()
        activeSegment.microphoneInput?.markAsFinished()

        let flushStartedAt = ProcessInfo.processInfo.systemUptime
        let duration = max(0.1, CMTimeSubtract(activeSegment.lastSourceTime, activeSegment.sourceStartedAt).seconds)
        finishingSegmentDurations[activeSegment.url] = duration

        activeSegment.writer.finishWriting { [weak self] in
            guard let self else {
                onComplete?()
                return
            }

            self.processingQueue.async {
                self.completeFinishedSegment(activeSegment, duration: duration, flushStartedAt: flushStartedAt)
                onComplete?()
            }
        }
    }

    private func completeFinishedSegment(_ activeSegment: ActiveReplaySegment, duration: TimeInterval, flushStartedAt: TimeInterval) {
        defer {
            finishingSegmentDurations[activeSegment.url] = nil
            resumeSegmentFinishWaitersIfIdle()
        }

        performance.segmentFlushCount += 1
        let flushMilliseconds = (ProcessInfo.processInfo.systemUptime - flushStartedAt) * 1_000
        performance.lastSegmentFlushMilliseconds = flushMilliseconds

        if activeSegment.writer.status == .completed {
            registerCompletedSegmentOnQueue(url: activeSegment.url, startedAt: activeSegment.startedAt, durationSeconds: duration)
            onDiagnosticEvent?(CaptureDiagnosticEvent(kind: .activeSegmentFlushed, message: "Active segment flushed: \(String(format: "%.1fs", duration)) in \(String(format: "%.1fms", flushMilliseconds))"))
        } else {
            onDiagnosticEvent?(CaptureDiagnosticEvent(kind: .saveFailed, message: "Segment failed: \(activeSegment.writer.error?.localizedDescription ?? "unknown encoder error")"))
            try? fileManager.removeItem(at: activeSegment.url)
        }
    }

    private func resumeSegmentFinishWaitersIfIdle() {
        guard finishingSegmentDurations.isEmpty else { return }
        let waiters = segmentFinishWaiters
        segmentFinishWaiters = []
        waiters.forEach { $0() }
    }

    private func makeActiveSegment(from sampleBuffer: CMSampleBuffer, sourceStartedAt: CMTime) throws -> ActiveReplaySegment {
        let url = nextSegmentURL()
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings(for: sampleBuffer))
        videoInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(videoInput) else { throw ReplaySegmentWriterError.cannotStartWriter }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        func makeAudioInput() throws -> AVAssetWriterInput {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 48_000,
                AVEncoderBitRateKey: 128_000
            ])
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw ReplaySegmentWriterError.cannotStartWriter }
            writer.add(input)
            return input
        }
        if preset.recordsSystemAudio { audioInput = try makeAudioInput() }
        let microphoneInput = preset.recordsMicrophone ? try makeAudioInput() : nil

        guard writer.startWriting() else {
            throw writer.error ?? ReplaySegmentWriterError.cannotStartWriter
        }
        writer.startSession(atSourceTime: sourceStartedAt)

        return ActiveReplaySegment(
            url: url,
            startedAt: Date(),
            sourceStartedAt: sourceStartedAt,
            lastSourceTime: sourceStartedAt,
            writer: writer,
            videoInput: videoInput,
            audioInput: audioInput,
            microphoneInput: microphoneInput
        )
    }

    private func nextSegmentURL() -> URL {
        let fileName = "segment-\(Date().timeIntervalSince1970)-\(UUID().uuidString).mov"
        return directory.appendingPathComponent(fileName)
    }

    private func videoOutputSettings(for sampleBuffer: CMSampleBuffer) -> [String: Any] {
        let dimensions = Self.videoDimensions(from: sampleBuffer)
        let compressionProperties = Self.videoCompressionProperties(for: preset)

        var settings: [String: Any] = [
            AVVideoCodecKey: preset.codec.avVideoCodecType,
            AVVideoWidthKey: dimensions.width,
            AVVideoHeightKey: dimensions.height
        ]
        settings[AVVideoEncoderSpecificationKey] = [
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true
        ]
        settings[AVVideoColorPropertiesKey] = [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
        ]

        if !compressionProperties.isEmpty {
            settings[AVVideoCompressionPropertiesKey] = compressionProperties
        }

        return settings
    }

    nonisolated static func videoCompressionProperties(for preset: CapturePreset) -> [String: Any] {
        var properties: [String: Any] = [
            AVVideoExpectedSourceFrameRateKey: preset.maximumFramesPerSecond,
            AVVideoMaxKeyFrameIntervalKey: max(preset.maximumFramesPerSecond * 2, 1),
            AVVideoAllowFrameReorderingKey: false
        ]

        if let videoBitrate = preset.videoBitrate {
            properties[AVVideoAverageBitRateKey] = videoBitrate
        }

        return properties
    }

    private nonisolated static func videoDimensions(from sampleBuffer: CMSampleBuffer) -> (width: Int, height: Int) {
        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            return (CVPixelBufferGetWidth(imageBuffer), CVPixelBufferGetHeight(imageBuffer))
        }

        if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
            return (Int(dimensions.width), Int(dimensions.height))
        }

        return (1280, 720)
    }

    private nonisolated static func isCompleteScreenFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
              let statusRawValue = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRawValue) else {
            return true
        }

        return status == .complete
    }

    private func publishAudioMonitorUpdateIfNeeded(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard now - lastAudioMonitorUpdateAt >= Self.audioMonitorPublishInterval else { return }
        lastAudioMonitorUpdateAt = now
        onAudioMonitorUpdated?()
    }

    private nonisolated static func audioMonitorMetrics(from sampleBuffer: CMSampleBuffer) -> (level: Double, qualityScore: Double, sampleRate: Double?, channelCount: Int) {
        let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        let streamDescription = formatDescription.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        let sampleRate = streamDescription?.mSampleRate
        let channelCount = Int(streamDescription?.mChannelsPerFrame ?? 0)
        let level = audioLevel(from: sampleBuffer, streamDescription: streamDescription)
        let sampleRateScore: Double
        if let sampleRate {
            sampleRateScore = min(max(sampleRate / 48_000, 0), 1)
        } else {
            sampleRateScore = 0.55
        }
        let channelScore = channelCount >= 2 ? 1.0 : (channelCount == 1 ? 0.72 : 0.35)
        let signalScore = max(0.35, min(level * Self.audioQualitySignalCompensation, 1))
        let qualityScore = min(max((sampleRateScore * 0.45) + (channelScore * 0.35) + (signalScore * 0.20), 0), 1)

        return (
            level: level,
            qualityScore: qualityScore,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
    }

    private nonisolated static func audioLevel(from sampleBuffer: CMSampleBuffer, streamDescription: AudioStreamBasicDescription?) -> Double {
        guard let streamDescription,
              streamDescription.mFormatID == kAudioFormatLinearPCM else {
            return 0
        }

        var bufferListSize = 0
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: nil
        )
        guard status == noErr, bufferListSize > 0 else { return 0 }

        let rawBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBufferList.deallocate() }

        let audioBufferList = rawBufferList.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuffer: CMBlockBuffer?
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: bufferListSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return 0 }

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let isFloat = (streamDescription.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInteger = (streamDescription.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0
        var sumSquares = 0.0
        var sampleCount = 0

        for buffer in buffers {
            guard let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }

            if isFloat && streamDescription.mBitsPerChannel == 32 {
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.stride
                let samples = data.assumingMemoryBound(to: Float.self)
                let stride = Self.audioMonitorSampleStride(for: count)
                for index in Swift.stride(from: 0, to: count, by: stride) {
                    let value = min(max(Double(samples[index]), -1), 1)
                    sumSquares += value * value
                    sampleCount += 1
                }
            } else if isSignedInteger && streamDescription.mBitsPerChannel == 16 {
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.stride
                let samples = data.assumingMemoryBound(to: Int16.self)
                let stride = Self.audioMonitorSampleStride(for: count)
                for index in Swift.stride(from: 0, to: count, by: stride) {
                    let value = Double(samples[index]) / Double(Int16.max)
                    sumSquares += value * value
                    sampleCount += 1
                }
            }
        }

        guard sampleCount > 0 else { return 0 }
        return min(max(sqrt(sumSquares / Double(sampleCount)) * Self.audioVisualizerGain, 0), 1)
    }

    nonisolated static func audioMonitorSampleStride(for sampleCount: Int) -> Int {
        max(1, (sampleCount + maxAudioMonitorSamples - 1) / maxAudioMonitorSamples)
    }

    private nonisolated static let audioVisualizerGain = 1.70
    private nonisolated static let audioQualitySignalCompensation = 2.34
    nonisolated static let audioMonitorAnalysisInterval: TimeInterval = 0.50
    nonisolated static let audioMonitorPublishInterval: TimeInterval = 1.00
    private nonisolated static let sampleTimestampUpdateInterval: TimeInterval = 0.25
    nonisolated static let maxAudioMonitorSamples = 2_048
    nonisolated static let videoAppendTimingSampleInterval = 30
    nonisolated static let audioAppendTimingSampleInterval = 20
    nonisolated static let defaultSegmentDurationSeconds: TimeInterval = 20
}

private struct ActiveReplaySegment: @unchecked Sendable {
    var url: URL
    var startedAt: Date
    var sourceStartedAt: CMTime
    var lastSourceTime: CMTime
    var writer: AVAssetWriter
    var videoInput: AVAssetWriterInput
    var audioInput: AVAssetWriterInput?
    var microphoneInput: AVAssetWriterInput?

    var estimatedDurationSeconds: TimeInterval {
        max(0, CMTimeSubtract(lastSourceTime, sourceStartedAt).seconds)
    }
}

private enum ReplaySegmentWriterError: Error {
    case cannotStartWriter
}

private extension CapturePreset.Codec {
    var avVideoCodecType: AVVideoCodecType {
        switch self {
        case .hevc:
            return .hevc
        case .h264:
            return .h264
        }
    }
}

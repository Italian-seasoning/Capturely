import Foundation
import AVFoundation
import Testing
@testable import Capturely

@Test func replaySegmentKeepsStableAudioSourceOrderAndGains() {
    let sources = [
        AudioSourceDescriptor.application(displayName: "Roblox", bundleIdentifier: "com.roblox.RobloxPlayer", gain: 0.8),
        AudioSourceDescriptor.application(displayName: "Chrome", bundleIdentifier: "com.google.Chrome", gain: 0.6),
        AudioSourceDescriptor.microphone(deviceID: "mic-1", gain: 0.4)
    ]
    let segment = ReplaySegment(
        url: URL(fileURLWithPath: "/tmp/segment.mov"),
        startedAt: Date(),
        durationSeconds: 20,
        audioSources: sources
    )

    #expect(segment.audioSources.map(\.id) == sources.map(\.id))
    #expect(segment.audioGains == [0.8, 0.6, 0.4])
}

@Test func capturePresetMapsCurrentSystemAndMicrophoneAudioInOrder() {
    var preset = CapturePreset.balanced
    preset.recordsSystemAudio = true
    preset.recordsMicrophone = true
    preset.audioGains = [0.75, 0.5]

    #expect(preset.audioSources.map(\.kind) == [.system, .microphone])
    #expect(preset.audioSources.map(\.gain) == [0.75, 0.5])
}

@Test func captureCoordinatorUsesFourIsolatedAppsAndMicrophoneInStableOrder() {
    var preset = CapturePreset.balanced
    preset.recordsMicrophone = true
    preset.audioGains = [0.75, 0.5]
    let applications = (1...5).map {
        AudioSourceDescriptor.application(displayName: "App \($0)", bundleIdentifier: "com.example.app\($0)")
    }

    let sources = CaptureCoordinator.resolvedAudioSources(
        preset: preset,
        isolatedAudioSources: applications,
        microphoneDeviceID: "mic-1"
    )

    #expect(sources.map(\.id) == applications.prefix(4).map(\.id) + ["microphone:mic-1"])
    #expect(sources.last?.gain == 0.5)
}

@Test func captureCoordinatorDoesNotCaptureAppsWhenSystemAudioIsOff() {
    var preset = CapturePreset.balanced
    preset.recordsSystemAudio = false
    preset.recordsMicrophone = true

    let sources = CaptureCoordinator.resolvedAudioSources(
        preset: preset,
        isolatedAudioSources: [.application(displayName: "Chrome", bundleIdentifier: "com.google.Chrome")],
        microphoneDeviceID: nil
    )

    #expect(sources.map(\.kind) == [.microphone])
}

@MainActor
@Test func replaySegmentWriterDeletesExpiredSegmentFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let writer = ReplaySegmentWriter(directory: directory, maximumDurationSeconds: 4)
    let oldSegment = directory.appendingPathComponent("old.mov")
    let middleSegment = directory.appendingPathComponent("middle.mov")
    let newestSegment = directory.appendingPathComponent("newest.mov")
    try Data("old".utf8).write(to: oldSegment)
    try Data("middle".utf8).write(to: middleSegment)
    try Data("newest".utf8).write(to: newestSegment)

    writer.registerCompletedSegment(url: oldSegment, startedAt: Date(timeIntervalSince1970: 0), durationSeconds: 2)
    writer.registerCompletedSegment(url: middleSegment, startedAt: Date(timeIntervalSince1970: 2), durationSeconds: 2)
    writer.registerCompletedSegment(url: newestSegment, startedAt: Date(timeIntervalSince1970: 4), durationSeconds: 2)

    #expect(writer.recentSegments(forReplayDuration: 4).map(\.url) == [middleSegment, newestSegment])
    #expect(FileManager.default.fileExists(atPath: oldSegment.path) == false)
    #expect(FileManager.default.fileExists(atPath: middleSegment.path))
    #expect(FileManager.default.fileExists(atPath: newestSegment.path))
}

@MainActor
@Test func saveClipRequiresReplaySegments() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let writer = ReplaySegmentWriter(directory: directory.appendingPathComponent("segments", isDirectory: true), maximumDurationSeconds: 60)
    let coordinator = CaptureCoordinator(replaySegmentWriter: writer)
    let game = Game(displayName: "Roblox", bundleIdentifier: "com.roblox.Roblox")
    let destination = ClipPathBuilder(
        root: directory.appendingPathComponent("clips", isDirectory: true),
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(secondsFromGMT: 0)!
    ).destination(forGameName: game.displayName, capturedAt: Date(timeIntervalSince1970: 0))
    let index = ClipIndexStore(fileURL: directory.appendingPathComponent("clips.json"))

    await #expect(throws: CaptureCoordinatorError.noReplaySegmentsAvailable) {
        _ = try await coordinator.saveClip(
            game: game,
            preset: .balanced,
            destination: destination,
            clipIndexStore: index
        )
    }
}

@MainActor
@Test func replaySegmentWriterReportsBufferHealth() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let writer = ReplaySegmentWriter(directory: directory, maximumDurationSeconds: 60)
    let first = directory.appendingPathComponent("first.mov")
    let second = directory.appendingPathComponent("second.mov")
    try Data("first".utf8).write(to: first)
    try Data("second".utf8).write(to: second)

    writer.registerCompletedSegment(url: first, startedAt: Date(timeIntervalSince1970: 0), durationSeconds: 4)
    writer.registerCompletedSegment(url: second, startedAt: Date(timeIntervalSince1970: 4), durationSeconds: 6)

    #expect(writer.currentBufferDurationSeconds == 10)
    #expect(writer.activeSegmentCount == 2)
}

@MainActor
@Test func replaySegmentWriterUpdatesRetentionAfterSettingsChange() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let writer = ReplaySegmentWriter(directory: directory, maximumDurationSeconds: 60)
    let first = directory.appendingPathComponent("first.mov")
    let second = directory.appendingPathComponent("second.mov")
    let third = directory.appendingPathComponent("third.mov")
    try Data("first".utf8).write(to: first)
    try Data("second".utf8).write(to: second)
    try Data("third".utf8).write(to: third)

    writer.registerCompletedSegment(url: first, startedAt: Date(timeIntervalSince1970: 0), durationSeconds: 10)
    writer.registerCompletedSegment(url: second, startedAt: Date(timeIntervalSince1970: 10), durationSeconds: 10)
    writer.registerCompletedSegment(url: third, startedAt: Date(timeIntervalSince1970: 20), durationSeconds: 10)
    writer.updateMaximumDurationSeconds(12)

    #expect(writer.recentSegments(forReplayDuration: 60).map(\.url) == [second, third])
    #expect(FileManager.default.fileExists(atPath: first.path) == false)
}

@MainActor
@Test func replaySegmentWriterRemovesStaleTemporarySegmentsOnStart() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let stale = directory.appendingPathComponent("segment-stale.mov")
    let unrelated = directory.appendingPathComponent("notes.txt")
    try Data("stale".utf8).write(to: stale)
    try Data("notes".utf8).write(to: unrelated)

    let writer = ReplaySegmentWriter(directory: directory, maximumDurationSeconds: 60)
    try writer.startRecording(preset: .balanced)

    #expect(FileManager.default.fileExists(atPath: stale.path) == false)
    #expect(FileManager.default.fileExists(atPath: unrelated.path))
}

@Test func replaySegmentWriterUsesLowLatencyEncoderProperties() {
    let properties = ReplaySegmentWriter.videoCompressionProperties(for: .balanced)

    #expect(properties[AVVideoExpectedSourceFrameRateKey] as? Int == CapturePreset.balanced.maximumFramesPerSecond)
    #expect(properties[AVVideoMaxKeyFrameIntervalKey] as? Int == CapturePreset.balanced.maximumFramesPerSecond * 2)
    #expect(properties[AVVideoAllowFrameReorderingKey] as? Bool == false)
    #expect(properties[AVVideoAverageBitRateKey] as? Int == CapturePreset.balanced.videoBitrate)
}

@Test func replaySegmentWriterSamplesAppendTimingInsteadOfEveryBuffer() {
    #expect(ReplaySegmentWriter.videoAppendTimingSampleInterval == 30)
    #expect(ReplaySegmentWriter.audioAppendTimingSampleInterval == 20)
}

@Test func replaySegmentWriterUsesLongerBackgroundSegmentsToAvoidRolloverSpikes() {
    #expect(ReplaySegmentWriter.defaultSegmentDurationSeconds == 20)
}

@Test func replaySegmentWriterCapsAudioMonitorSampleWork() {
    #expect(ReplaySegmentWriter.maxAudioMonitorSamples == 2_048)
    #expect(ReplaySegmentWriter.audioMonitorAnalysisInterval == 0.50)
    #expect(ReplaySegmentWriter.audioMonitorPublishInterval == 1.00)
    #expect(ReplaySegmentWriter.audioMonitorSampleStride(for: 512) == 1)
    #expect(ReplaySegmentWriter.audioMonitorSampleStride(for: 2_048) == 1)
    #expect(ReplaySegmentWriter.audioMonitorSampleStride(for: 4_096) == 2)
    #expect(ReplaySegmentWriter.audioMonitorSampleStride(for: 96_000) == 47)
}

@Test func replaySegmentWriterJoinsSegmentsWithoutGapsWhenAudioArrivesLate() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let writer = ReplaySegmentWriter(directory: directory, maximumDurationSeconds: 60, segmentDurationSeconds: 1)
    try writer.startRecording(preset: .balanced)

    let audioFrames = 1_024
    var nextAudioFrame = 0
    for frame in 0..<180 {
        let seconds = Double(frame) / 60
        // Real-time pacing: the realtime encoder drops frames that arrive faster than it can take them.
        try await Task.sleep(for: .milliseconds(16))
        writer.append(sampleBuffer: syntheticVideoSample(at: CMTime(value: Int64(frame * 10), timescale: 600)), type: .screen)
        // ScreenCaptureKit audio regularly lands after the video frame with the same timestamp.
        while Double(nextAudioFrame + audioFrames) / 48_000 <= seconds - 0.1 {
            writer.append(sampleBuffer: syntheticAudioSample(startFrame: nextAudioFrame, frames: audioFrames), type: .audio)
            nextAudioFrame += audioFrames
        }
    }
    await writer.stopRecording()

    let segments = writer.recentSegments(forReplayDuration: 60)
    #expect(segments.count == 3)
    for segment in segments.prefix(2) {
        #expect(abs(segment.durationSeconds - 1) < 0.001)
        let asset = AVURLAsset(url: segment.url)
        let videoTrack = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let videoRange = try await videoTrack.load(.timeRange)
        let audioTrack = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let audioRange = try await audioTrack.load(.timeRange)
        #expect(abs(videoRange.end.seconds - 1) < 0.02, "video ends at \(videoRange.end.seconds)")
        #expect(audioRange.start.seconds < 0.025)
        #expect(abs(audioRange.end.seconds - 1) < 0.025)
    }
}

@Test func clipEditorSavesTrimmedCopiesWithPassthroughAndFades() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let writer = ReplaySegmentWriter(directory: directory, maximumDurationSeconds: 60)
    try writer.startRecording(preset: .balanced)
    var nextAudioFrame = 0
    for frame in 0..<90 {
        try await Task.sleep(for: .milliseconds(16))
        writer.append(sampleBuffer: syntheticVideoSample(at: CMTime(value: Int64(frame * 10), timescale: 600)), type: .screen)
        while Double(nextAudioFrame + 1_024) / 48_000 <= Double(frame) / 60 {
            writer.append(sampleBuffer: syntheticAudioSample(startFrame: nextAudioFrame, frames: 1_024), type: .audio)
            nextAudioFrame += 1_024
        }
    }
    await writer.stopRecording()
    let source = try #require(writer.recentSegments(forReplayDuration: 60).first).url

    for (name, fade) in [("copy.mov", 0.0), ("fade.mov", 0.2)] {
        let output = directory.appendingPathComponent(name)
        try await ClipEditor.export(source: source, output: output, start: 0.25, end: 1.25, gains: [1], fadeIn: fade, fadeOut: fade)
        let asset = AVURLAsset(url: output)
        #expect(abs(try await asset.load(.duration).seconds - 1) < 0.05, "\(name)")
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1, "\(name)")
    }
}

private func syntheticVideoSample(at time: CMTime) -> CMSampleBuffer {
    var pixelBuffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, 320, 180, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer)
    var format: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer!, formatDescriptionOut: &format)
    var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixelBuffer!, formatDescription: format!,
                                             sampleTiming: &timing, sampleBufferOut: &sample)
    return sample!
}

private func syntheticAudioSample(startFrame: Int, frames: Int) -> CMSampleBuffer {
    var description = AudioStreamBasicDescription(
        mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
    var format: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                   magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
    let length = frames * 8
    var block: CMBlockBuffer?
    CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil,
                                       customBlockSource: nil, offsetToData: 0, dataLength: length,
                                       flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
    CMBlockBufferFillDataBytes(with: 0, blockBuffer: block!, offsetIntoDestination: 0, dataLength: length)
    var sample: CMSampleBuffer?
    CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block!, formatDescription: format!,
        sampleCount: frames, presentationTimeStamp: CMTime(value: Int64(startFrame), timescale: 48_000),
        packetDescriptions: nil, sampleBufferOut: &sample)
    return sample!
}

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

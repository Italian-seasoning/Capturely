import Testing
import Foundation
@testable import Capturely

@Test func replayComposerKeepsDefaultGainOnPassthroughPath() {
    #expect(!ReplayComposer.shouldPreferFFmpegAudioOnlyExport(audioGain: 1.0, ffmpegAvailable: true))
    #expect(!ReplayComposer.shouldPreferFFmpegAudioOnlyExport(audioGain: 1.0004, ffmpegAvailable: true))
}

@Test func replayComposerPrefersAudioOnlyFFmpegWhenGainChanges() {
    #expect(ReplayComposer.shouldPreferFFmpegAudioOnlyExport(audioGain: 0.8, ffmpegAvailable: true))
    #expect(ReplayComposer.shouldPreferFFmpegAudioOnlyExport(audioGain: 1.2, ffmpegAvailable: true))
    #expect(!ReplayComposer.shouldPreferFFmpegAudioOnlyExport(audioGain: 0.8, ffmpegAvailable: false))
}

@Test func replayComposerPrefersFFmpegStreamCopyForMultiSegmentDefaultGain() {
    let first = ReplaySegment(
        url: URL(fileURLWithPath: "/tmp/segment-1.mov"),
        startedAt: Date(timeIntervalSince1970: 0),
        durationSeconds: 10
    )
    let second = ReplaySegment(
        url: URL(fileURLWithPath: "/tmp/segment-2.mov"),
        startedAt: Date(timeIntervalSince1970: 10),
        durationSeconds: 10
    )

    #expect(ReplayComposer.shouldPreferFFmpegStreamCopy(segments: [first, second], audioGain: 1, ffmpegAvailable: true))
    #expect(!ReplayComposer.shouldPreferFFmpegStreamCopy(segments: [first], audioGain: 1, ffmpegAvailable: true))
    #expect(!ReplayComposer.shouldPreferFFmpegStreamCopy(segments: [first, second], audioGain: 0.8, ffmpegAvailable: true))
    #expect(!ReplayComposer.shouldPreferFFmpegStreamCopy(segments: [first, second], audioGain: 1, ffmpegAvailable: false))
}

@Test func replayComposerCanCopySingleUntrimmedSegmentWithoutExport() {
    let segment = ReplaySegment(
        url: URL(fileURLWithPath: "/tmp/segment.mov"),
        startedAt: Date(timeIntervalSince1970: 0),
        durationSeconds: 10
    )

    #expect(ReplayComposer.canCopySingleSegmentWithoutExport(segments: [segment], targetDurationSeconds: nil, audioGain: 1))
    #expect(ReplayComposer.canCopySingleSegmentWithoutExport(segments: [segment], targetDurationSeconds: 10, audioGain: 1))
    #expect(ReplayComposer.canCopySingleSegmentWithoutExport(segments: [segment], targetDurationSeconds: 30, audioGain: 1))
}

@Test func replayComposerDoesNotCopyWhenTrimOrAudioProcessingIsNeeded() {
    let segment = ReplaySegment(
        url: URL(fileURLWithPath: "/tmp/segment.mov"),
        startedAt: Date(timeIntervalSince1970: 0),
        durationSeconds: 10
    )
    let secondSegment = ReplaySegment(
        url: URL(fileURLWithPath: "/tmp/segment-2.mov"),
        startedAt: Date(timeIntervalSince1970: 10),
        durationSeconds: 10
    )

    #expect(!ReplayComposer.canCopySingleSegmentWithoutExport(segments: [segment], targetDurationSeconds: 5, audioGain: 1))
    #expect(!ReplayComposer.canCopySingleSegmentWithoutExport(segments: [segment], targetDurationSeconds: nil, audioGain: 0.8))
    #expect(!ReplayComposer.canCopySingleSegmentWithoutExport(segments: [segment, secondSegment], targetDurationSeconds: nil, audioGain: 1))
}

@Test func replayComposerCopiesSingleUntrimmedSegmentDirectly() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let source = directory.appendingPathComponent("segment.mov")
    let output = directory.appendingPathComponent("clip.mov")
    try Data("already-encoded-segment".utf8).write(to: source)
    let segment = ReplaySegment(url: source, startedAt: Date(timeIntervalSince1970: 0), durationSeconds: 10)

    let result = try await ReplayComposer().compose(
        segments: [segment],
        outputURL: output,
        targetDurationSeconds: 30,
        audioGain: 1
    )

    #expect(try Data(contentsOf: output) == Data("already-encoded-segment".utf8))
    #expect(result.strategy == .directSegmentCopy)
    #expect(result.elapsedMilliseconds >= 0)
}

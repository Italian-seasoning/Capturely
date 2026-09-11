import Testing
import Foundation
import CoreVideo
@testable import Capturely

@Test func cappedCaptureSizePreservesAspectRatio() {
    let size = CaptureCoordinator.cappedCaptureSize(width: 2560, height: 1440, maximumHeight: 720)

    #expect(size.width == 1280)
    #expect(size.height == 720)
}

@Test func cappedCaptureSizeConstrainsUltrawidePixelLoad() {
    let size = CaptureCoordinator.cappedCaptureSize(width: 2560, height: 1080, maximumHeight: 1080)

    #expect(size.width == 1920)
    #expect(size.height == 810)
}

@Test func cappedCaptureSizeKeepsSmallWindowSize() {
    let size = CaptureCoordinator.cappedCaptureSize(width: 960, height: 540, maximumHeight: 720)

    #expect(size.width == 960)
    #expect(size.height == 540)
}

@Test func captureStreamUsesEncoderNativePixelFormat() {
    #expect(CaptureCoordinator.streamPixelFormatForEncoding == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
}

@Test func selectedDisplayFallbackUsesGlobalDisplayBounds() {
    let displayID = GameWindowResolver.displayIDContainingLargestWindow(
        displayBounds: [
            CaptureDisplayBounds(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
            CaptureDisplayBounds(displayID: 2, frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080))
        ],
        windowFrames: [
            CGRect(x: 1700, y: 120, width: 1200, height: 760)
        ]
    )

    #expect(displayID == 2)
}

@Test func selectedDisplayFallbackUsesLargestGameWindow() {
    let displayID = GameWindowResolver.displayIDContainingLargestWindow(
        displayBounds: [
            CaptureDisplayBounds(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
            CaptureDisplayBounds(displayID: 2, frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080))
        ],
        windowFrames: [
            CGRect(x: 1500, y: 80, width: 320, height: 240),
            CGRect(x: 80, y: 60, width: 1000, height: 700)
        ]
    )

    #expect(displayID == 1)
}

@Test func selectedDisplayFallbackUsesLargestDisplayOverlap() {
    let displayID = GameWindowResolver.displayIDContainingLargestWindow(
        displayBounds: [
            CaptureDisplayBounds(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
            CaptureDisplayBounds(displayID: 2, frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080))
        ],
        windowFrames: [
            CGRect(x: 1300, y: 80, width: 900, height: 700)
        ]
    )

    #expect(displayID == 2)
}

@MainActor
@Test func saveClipIndexesOnlyAfterOutputIsValid() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let segment = directory.appendingPathComponent("segment.mov")
    try Data("segment".utf8).write(to: segment)
    let writer = ReplaySegmentWriter(directory: directory.appendingPathComponent("segments", isDirectory: true), maximumDurationSeconds: 60)
    writer.registerCompletedSegment(url: segment, startedAt: Date(timeIntervalSince1970: 0), durationSeconds: 30)

    let coordinator = CaptureCoordinator(
        replaySegmentWriter: writer,
        replayComposer: StubReplayComposer { _, outputURL, targetDurationSeconds, audioGain in
            #expect(targetDurationSeconds == 20)
            #expect(audioGain == 0.7)
            try Data("movie".utf8).write(to: outputURL)
        },
        thumbnailGenerator: StubThumbnailGenerator { _, thumbnailURL in
            try Data("thumb".utf8).write(to: thumbnailURL)
        }
    )
    let eventRecorder = DiagnosticEventRecorder()
    coordinator.onDiagnosticEvent = { event in
        eventRecorder.append(event)
    }
    let game = Game(displayName: "Roblox", bundleIdentifier: "com.roblox.Roblox")
    let destination = ClipPathBuilder(
        root: directory.appendingPathComponent("clips", isDirectory: true),
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(secondsFromGMT: 0)!
    ).destination(forGameName: game.displayName, capturedAt: Date(timeIntervalSince1970: 0))
    let index = ClipIndexStore(fileURL: directory.appendingPathComponent("clips.json"))

    let clip = try await coordinator.saveClip(
        game: game,
        preset: .balanced,
        destination: destination,
        clipIndexStore: index,
        capturedAt: Date(timeIntervalSince1970: 0),
        replayDurationSeconds: 20,
        audioGain: 0.7
    )

    #expect(FileManager.default.fileExists(atPath: clip.clipURL.path))
    #expect(try index.load() == [clip])
    #expect(clip.durationSeconds == 20)
    #expect(eventRecorder.events.contains { $0.kind == .compositionFinished && $0.message.contains("AVFoundation passthrough") })
    try await waitForFile(at: clip.thumbnailURL)
    #expect(FileManager.default.fileExists(atPath: clip.thumbnailURL.path))
}

@MainActor
@Test func saveClipDoesNotIndexInvalidOutput() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let segment = directory.appendingPathComponent("segment.mov")
    try Data("segment".utf8).write(to: segment)
    let writer = ReplaySegmentWriter(directory: directory.appendingPathComponent("segments", isDirectory: true), maximumDurationSeconds: 60)
    writer.registerCompletedSegment(url: segment, startedAt: Date(timeIntervalSince1970: 0), durationSeconds: 3)
    let coordinator = CaptureCoordinator(
        replaySegmentWriter: writer,
        replayComposer: StubReplayComposer { _, _, _, _ in }
    )
    let game = Game(displayName: "Roblox", bundleIdentifier: "com.roblox.Roblox")
    let destination = ClipPathBuilder(
        root: directory.appendingPathComponent("clips", isDirectory: true),
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(secondsFromGMT: 0)!
    ).destination(forGameName: game.displayName, capturedAt: Date(timeIntervalSince1970: 0))
    let index = ClipIndexStore(fileURL: directory.appendingPathComponent("clips.json"))

    await #expect(throws: CaptureCoordinatorError.invalidClipOutput) {
        _ = try await coordinator.saveClip(
            game: game,
            preset: .balanced,
            destination: destination,
            clipIndexStore: index,
            capturedAt: Date(timeIntervalSince1970: 0)
        )
    }
    #expect(try index.load().isEmpty)
}

@MainActor
@Test func saveClipRemovesOrphanedFilesWhenIndexingFails() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let segment = directory.appendingPathComponent("segment.mov")
    try Data("segment".utf8).write(to: segment)
    let writer = ReplaySegmentWriter(directory: directory.appendingPathComponent("segments", isDirectory: true), maximumDurationSeconds: 60)
    writer.registerCompletedSegment(url: segment, startedAt: Date(timeIntervalSince1970: 0), durationSeconds: 3)
    let coordinator = CaptureCoordinator(
        replaySegmentWriter: writer,
        replayComposer: StubReplayComposer { _, outputURL, _, _ in
            try Data("movie".utf8).write(to: outputURL)
        }
    )
    let game = Game(displayName: "Roblox", bundleIdentifier: "com.roblox.Roblox")
    let destination = ClipPathBuilder(
        root: directory.appendingPathComponent("clips", isDirectory: true),
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(secondsFromGMT: 0)!
    ).destination(forGameName: game.displayName, capturedAt: Date(timeIntervalSince1970: 0))
    let invalidIndex = ClipIndexStore(fileURL: directory)

    await #expect(throws: (any Error).self) {
        _ = try await coordinator.saveClip(
            game: game,
            preset: .balanced,
            destination: destination,
            clipIndexStore: invalidIndex,
            capturedAt: Date(timeIntervalSince1970: 0)
        )
    }
    #expect(!FileManager.default.fileExists(atPath: destination.folder.path))
}

private struct StubReplayComposer: ReplayComposing {
    var composeHandler: @Sendable ([ReplaySegment], URL, TimeInterval?, Double) async throws -> Void

    init(composeHandler: @escaping @Sendable ([ReplaySegment], URL, TimeInterval?, Double) async throws -> Void) {
        self.composeHandler = composeHandler
    }

    func compose(segments: [ReplaySegment], outputURL: URL, targetDurationSeconds: TimeInterval?, audioGain: Double) async throws -> ReplayCompositionResult {
        try await composeHandler(segments, outputURL, targetDurationSeconds, audioGain)
        return ReplayCompositionResult(strategy: .avFoundationPassthrough, elapsedMilliseconds: 1)
    }
}

private struct StubThumbnailGenerator: ThumbnailGenerating {
    var generateHandler: @Sendable (URL, URL) async throws -> Void

    init(generateHandler: @escaping @Sendable (URL, URL) async throws -> Void) {
        self.generateHandler = generateHandler
    }

    func generateThumbnail(for videoURL: URL, outputURL: URL) async throws {
        try await generateHandler(videoURL, outputURL)
    }
}

private final class DiagnosticEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [CaptureDiagnosticEvent] = []

    var events: [CaptureDiagnosticEvent] {
        lock.withLock {
            recordedEvents
        }
    }

    func append(_ event: CaptureDiagnosticEvent) {
        lock.withLock {
            recordedEvents.append(event)
        }
    }
}

private func waitForFile(at url: URL, timeout: Duration = .seconds(1)) async throws {
    let start = ContinuousClock.now
    while !FileManager.default.fileExists(atPath: url.path) {
        if start.duration(to: .now) > timeout {
            Issue.record("Timed out waiting for \(url.path)")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

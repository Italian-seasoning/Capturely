import Foundation
import Testing
@testable import Capturely

@Test func bookmarksMapGapsTrimAndDebounce() {
    var buffer = ReplayBookmarks()
    for time in [101.0, 101.2, 103, 107, 111] { buffer.add(now: Date(timeIntervalSince1970: time)) }
    let segments = [ReplaySegment(url: URL(fileURLWithPath: "/a"), startedAt: Date(timeIntervalSince1970: 100), durationSeconds: 4),
                    ReplaySegment(url: URL(fileURLWithPath: "/b"), startedAt: Date(timeIntervalSince1970: 110), durationSeconds: 4)]
    let marks = buffer.snapshot(segments: segments, duration: 6)
    #expect(marks.map(\.seconds) == [1, 3]) // first 2s trimmed; the wall-clock gap is omitted
    #expect(ReplayBookmarks.trimmed(marks, start: 1, end: 3).map(\.seconds) == [0])
    let saving = buffer
    buffer.reset()
    #expect(buffer.snapshot(segments: segments, duration: 6).isEmpty)
    #expect(saving.snapshot(segments: segments, duration: 6).map(\.seconds) == [1, 3])
}

@Test func telemetrySummaryWeightsTimeAndDoesNotBridgeMissingFPS() {
    let a = FrameBarReading(schemaVersion: 1, gamePID: 1, timestamp: 100, gameFPS: 120)
    let b = FrameBarReading(schemaVersion: 1, gamePID: 1, timestamp: 101, gameFPS: 60)
    let missing = FrameBarReading(schemaVersion: 1, gamePID: 1, timestamp: 102)
    let entries = [TimedTelemetry(seconds: 0, duration: 1, reading: a),
                   TimedTelemetry(seconds: 1, duration: 3, reading: b),
                   TimedTelemetry(seconds: 4, duration: 1, reading: missing),
                   TimedTelemetry(seconds: 5, duration: 1, reading: a)]
    let summary = ClipTelemetry.summary(entries, metric: .fps, duration: 6)
    #expect(summary?.average == 84)
    #expect(summary?.coveredSeconds == 5)
    #expect(Set(ClipTelemetry.points(entries, metric: .fps, duration: 6).map(\.segment)).count == 2)
    let overlap = [entries[0], TimedTelemetry(seconds: 0.5, duration: 1.5, reading: b)]
    #expect(ClipTelemetry.summary(overlap, metric: .fps, duration: 2)?.average == 90)
}

@Test func telemetryClampsSpansAndIgnoresNonFiniteData() {
    var reading = FrameBarReading(schemaVersion: 1, gamePID: 1, timestamp: 100, gameFPS: .infinity)
    let malformed = [TimedTelemetry(seconds: .nan, duration: 2, reading: reading), TimedTelemetry(seconds: -1, duration: 4, reading: reading)]
    #expect(ClipTelemetry.normalized(malformed, duration: 2).map(\.duration) == [2])
    #expect(ClipTelemetry.summary(malformed, metric: .fps, duration: 2) == nil)
    reading.gameFPS = 0
    #expect(TelemetryMetric.fps.value(reading) == nil)
}

@Test func clipBookmarksRemainCompatibleWithOlderMetadata() throws {
    var clip = Clip(gameID: UUID(), gameName: "Test", capturedAt: Date(), durationSeconds: 4,
                    presetName: "Test", folderURL: URL(fileURLWithPath: "/test"),
                    clipURL: URL(fileURLWithPath: "/test/clip.mov"),
                    metadataURL: URL(fileURLWithPath: "/test/metadata.json"),
                    thumbnailURL: URL(fileURLWithPath: "/test/thumbnail.jpg"))
    clip.bookmarks = [ClipBookmark(seconds: 2)]
    let data = try JSONEncoder().encode(clip)
    #expect(try JSONDecoder().decode(Clip.self, from: data).bookmarks == clip.bookmarks)
    var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    legacy.removeValue(forKey: "bookmarks")
    #expect(try JSONDecoder().decode(Clip.self, from: JSONSerialization.data(withJSONObject: legacy)).bookmarks.isEmpty)
}

@Test func bookmarkSidecarsAreExportedAndCheckedForConflicts() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    var clip = Clip(gameID: UUID(), gameName: "Test", capturedAt: Date(), durationSeconds: 4,
                    presetName: "Test", folderURL: folder, clipURL: folder.appendingPathComponent("clip.mov"),
                    metadataURL: folder.appendingPathComponent("metadata.json"), thumbnailURL: folder.appendingPathComponent("thumbnail.jpg"))
    clip.bookmarks = [ClipBookmark(seconds: 2)]
    try JSONEncoder().encode(clip.bookmarks).write(to: folder.appendingPathComponent("bookmarks.json"))
    let destination = folder.appendingPathComponent("export.mov")
    try await FrameBarPlugin.exportSidecars(clip: clip, destination: destination)
    let sidecar = folder.appendingPathComponent("export.bookmarks.json")
    #expect(try JSONDecoder().decode([ClipBookmark].self, from: Data(contentsOf: sidecar)) == clip.bookmarks)
    try Data("old bookmarks".utf8).write(to: sidecar)
    await #expect(throws: TelemetryExportError.self) { try await FrameBarPlugin.validateExportSidecars(clip: clip, destination: destination) }
}

import Foundation
import Testing
@testable import Capturely

private func reading(_ time: Double, fps: Double = 120) -> FrameBarReading {
    FrameBarReading(schemaVersion: 1, gamePID: 42, timestamp: time, gameFPS: fps, gameStatsTimestamp: time)
}

@Test func telemetrySkipsWallClockGapsAndTrimsReplayStart() {
    let segments = [ReplaySegment(url: URL(fileURLWithPath: "/a"), startedAt: Date(timeIntervalSince1970: 100), durationSeconds: 4),
                    ReplaySegment(url: URL(fileURLWithPath: "/b"), startedAt: Date(timeIntervalSince1970: 110), durationSeconds: 4)]
    let result = FrameBarPlugin.timeline(samples: [reading(100), reading(102), reading(106), reading(110), reading(112)], segments: segments, duration: 6)
    #expect(result.map(\.seconds) == [0, 2, 4])
    #expect(result.map(\.duration) == [2, 2, 2])
    #expect(result.allSatisfy { $0.seconds + $0.duration <= 6 })
}

@Test func telemetryExpiresRatherThanInventingFPSDuringMissingSamples() {
    let segment = ReplaySegment(url: URL(fileURLWithPath: "/a"), startedAt: Date(timeIntervalSince1970: 100), durationSeconds: 10)
    let result = FrameBarPlugin.timeline(samples: [reading(100)], segments: [segment], duration: 10)
    #expect(result.count == 1)
    #expect(result.first?.duration == 3)
}

@Test func subtitleTrimRebasesTimesAndPreservesOriginal() {
    let original = [TimedTelemetry(seconds: 1, duration: 3, reading: reading(100))]
    let trimmed = FrameBarPlugin.trimmed(original, start: 2, end: 3.5)
    #expect(trimmed.first?.seconds == 0)
    #expect(trimmed.first?.duration == 1.5)
    #expect(FrameBarPlugin.subtitles(trimmed).contains("00:00:00,000 --> 00:00:01,500"))
    #expect(original.first?.seconds == 1)
}

@Test func unsafeGameFolderNamesStayInsideLibrary() {
    #expect(ClipPathBuilder.sanitizedFolderName("..") == "Game")
    #expect(ClipPathBuilder.sanitizedFolderName("/") == "Game")
}

@MainActor @Test func companionRejectsStaleOrWrongPIDAndExportsSnapshotAfterStop() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("snapshot.json")
    let plugin = FrameBarPlugin(snapshotURL: url)
    let segment = ReplaySegment(url: folder.appendingPathComponent("unused.mov"), startedAt: Date(timeIntervalSince1970: 100), durationSeconds: 4)
    try JSONEncoder().encode(reading(100)).write(to: url)
    plugin.sample(pid: 999, now: Date(timeIntervalSince1970: 101))
    #expect(plugin.snapshot(segments: [segment], duration: 4).isEmpty)
    plugin.sample(pid: 42, now: Date(timeIntervalSince1970: 120))
    #expect(plugin.snapshot(segments: [segment], duration: 4).isEmpty)
    plugin.sample(pid: 42, now: Date(timeIntervalSince1970: 101))
    plugin.sample(pid: 42, now: Date(timeIntervalSince1970: 102)) // duplicate snapshot
    let snapshot = plugin.snapshot(segments: [segment], duration: 4)
    let savingSamples = plugin.samples
    #expect(snapshot.count == 1)
    plugin.sample(pid: nil)
    #expect(plugin.snapshot(segments: [segment], duration: 4).isEmpty)
    #expect(FrameBarPlugin.timeline(samples: savingSamples, segments: [segment], duration: 4) == snapshot)
    let files = try await FrameBarPlugin.export(entries: snapshot, folder: folder)
    #expect(files != nil)
    #expect(try JSONDecoder().decode([TimedTelemetry].self, from: Data(contentsOf: files!.0)) == snapshot)
    #expect(try String(contentsOf: files!.1, encoding: .utf8).contains("120.0 fps"))
    #expect(try String(contentsOf: folder.appendingPathComponent("telemetry.csv"), encoding: .utf8).contains("120.000"))
}

@MainActor @Test func companionRejectsOutOfOrderSnapshotsAndExpiresUnstampedStats() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("snapshot.json")
    let plugin = FrameBarPlugin(snapshotURL: url)
    var fresh = reading(100)
    fresh.cpu = 42
    try JSONEncoder().encode(fresh).write(to: url)
    plugin.sample(pid: 42, now: Date(timeIntervalSince1970: 101))
    try JSONEncoder().encode(reading(99, fps: 30)).write(to: url)
    plugin.sample(pid: 42, now: Date(timeIntervalSince1970: 102))
    let segment = ReplaySegment(url: folder, startedAt: Date(timeIntervalSince1970: 100), durationSeconds: 3)
    #expect(plugin.snapshot(segments: [segment], duration: 3).map(\.reading.gameFPS) == [120])

    fresh.timestamp = 110; fresh.gameStatsTimestamp = nil
    try JSONEncoder().encode(fresh).write(to: url)
    plugin.sample(pid: 42, now: Date(timeIntervalSince1970: 111))
    let later = ReplaySegment(url: folder, startedAt: Date(timeIntervalSince1970: 110), durationSeconds: 3)
    let result = plugin.snapshot(segments: [later], duration: 3)
    #expect(result.first?.reading.gameFPS == nil)
    #expect(result.first?.reading.cpu == 42)
}

@Test func sidecarConflictsBlockVideoReplacementAndIdenticalSidecarsAreAllowed() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("source.mov")
    let destination = folder.appendingPathComponent("export.mov")
    let subtitle = folder.appendingPathComponent("clip.srt")
    let exportedSubtitle = folder.appendingPathComponent("export.srt")
    try Data("new movie".utf8).write(to: source)
    try Data("old movie".utf8).write(to: destination)
    try Data("new subtitles".utf8).write(to: subtitle)
    try Data("old subtitles".utf8).write(to: exportedSubtitle)
    var clip = Clip(gameID: UUID(), gameName: "Roblox", capturedAt: Date(), durationSeconds: 3,
                    presetName: "Test", folderURL: folder, clipURL: source,
                    metadataURL: folder.appendingPathComponent("metadata.json"), thumbnailURL: folder.appendingPathComponent("thumbnail.jpg"))
    clip.subtitleURL = subtitle
    await #expect(throws: TelemetryExportError.self) {
        try await FrameBarPlugin.validateExportSidecars(clip: clip, destination: destination)
        try await ClipExporter().export(source: source, destination: destination, preset: .original)
    }
    #expect(try Data(contentsOf: destination) == Data("old movie".utf8))
    #expect(try Data(contentsOf: exportedSubtitle) == Data("old subtitles".utf8))
    try Data("new subtitles".utf8).write(to: exportedSubtitle)
    try await FrameBarPlugin.validateExportSidecars(clip: clip, destination: destination)
}

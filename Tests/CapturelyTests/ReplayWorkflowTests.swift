import AppKit
import Foundation
import Testing
@testable import Capturely

@Test func workflowSettingsAndOldClipsDecodeSafely() throws {
    let settings = try JSONDecoder.capturely.decode(AppSettings.self, from: Data("{}".utf8))
    #expect(settings.automaticGameSessions)
    #expect(settings.keepsEditableAudio)
    #expect(settings.logsGameProcess)
    #expect(settings.libraryLimitGB == 0)
    #expect(try JSONDecoder.capturely.decode(AppSettings.self, from: Data("{\"libraryLimitGB\":-1}".utf8)).libraryLimitGB == 0)
    let clip = testClip()
    var json = try JSONSerialization.jsonObject(with: JSONEncoder.capturely.encode(clip)) as! [String: Any]
    json.removeValue(forKey: "isStarred")
    json.removeValue(forKey: "editableSourceURL")
    json.removeValue(forKey: "processLogURL")
    let old = try JSONDecoder.capturely.decode(Clip.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(old.isStarred != true && old.editableSourceURL == nil && old.processLogURL == nil)
}

@Test func cleanupPreservesStarsOpenClipsAndUnknownFiles() {
    var old = testClip(); old.capturedAt = Date(timeIntervalSince1970: 1)
    var star = testClip(); star.isStarred = true; star.capturedAt = Date(timeIntervalSince1970: 0)
    let open = testClip(), unknown = testClip()
    let entries = [LibraryStorage.Entry(clip: old, bytes: 100, safeToRemove: true),
                   .init(clip: star, bytes: 100, safeToRemove: true),
                   .init(clip: open, bytes: 100, safeToRemove: true),
                   .init(clip: unknown, bytes: 100, safeToRemove: false)]
    #expect(LibraryStorage.removals(entries: entries, limitBytes: 100, protectedIDs: [open.id]).map(\.id) == [old.id])
    #expect(LibraryStorage.removals(entries: entries, limitBytes: 0).isEmpty)
}

@Test func cleanupInventoryRejectsUnexpectedAndLinkedContent() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    var clip = testClip(root: root)
    clip.processLogURL = root.appendingPathComponent("process-log.csv")
    try JSONEncoder.capturely.encode(clip).write(to: clip.metadataURL)
    try Data([1]).write(to: clip.clipURL)
    try Data("test".utf8).write(to: clip.processLogURL!)
    #expect(LibraryStorage.inventory([clip])[0].safeToRemove)
    let extra = root.appendingPathComponent("personal.txt")
    try Data([1]).write(to: extra)
    #expect(!LibraryStorage.inventory([clip])[0].safeToRemove)
    try FileManager.default.removeItem(at: extra)
    try FileManager.default.createSymbolicLink(at: clip.thumbnailURL, withDestinationURL: clip.clipURL)
    #expect(!LibraryStorage.inventory([clip])[0].safeToRemove)
}

@Test func durationsAndNetworkParsingRejectBadInput() {
    #expect([3, 4, 5].map { HotkeyService.replaySeconds(forHotkeyID: UInt32($0)) } == [15, 30, 60])
    #expect(HotkeyService.replaySeconds(forHotkeyID: 9) == nil)
    #expect(ClipEditor.validRange(start: 0.2, end: 1, duration: 2))
    #expect(!ClipEditor.validRange(start: -.infinity, end: 1, duration: 2))
    #expect(!ClipEditor.validRange(start: 1, end: 0, duration: 2))
    #expect(!ClipEditor.validRange(start: 0, end: 3, duration: 2))
    #expect(GameProcessLogger.parseNetworkRow("Roblox.123,4000,8000,", pid: 123)?.sent == 8000)
    #expect(GameProcessLogger.parseNetworkRow("Roblox.1234,4000,8000,", pid: 123) == nil)
    #expect(GameProcessLogger.parseNetworkRow(",bytes_in,bytes_out,", pid: 123) == nil)
    #expect(GameProcessLogger.parseNetworkRow("Roblox.123,-1,NaN,", pid: 123) == nil)
    #expect(ResourceUsage.cpuPercent(cpuDelta: 2, elapsed: 1) == 200)
    #expect(ResourceUsage.cpuPercent(cpuDelta: -1, elapsed: 1) == nil)
    #expect(ResourceUsage.cpuPercent(cpuDelta: 1, elapsed: 0) == nil)
}

@Test @MainActor func processLoggerReadsCountersAndWritesClipWindow() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let logger = GameProcessLogger(logsDirectory: root)
    defer { logger.stop(); try? FileManager.default.removeItem(at: root) }
    var sampler = ResourceSampler()
    let resource = sampler.sample(performance: .empty, recording: false)
    #expect((resource.memoryBytes ?? 0) > 0)
    let first = logger.sample(pid: getpid(), appUsage: resource, performance: .empty)
    #expect((first.memoryBytes ?? 0) > 0)
    #expect(first.cpuPercent == nil)
    try await Task.sleep(for: .milliseconds(20))
    let second = logger.sample(pid: getpid(), appUsage: resource, performance: .empty)
    #expect(second.cpuPercent != nil)
    let csv = root.appendingPathComponent("clip.csv")
    #expect(try logger.saveWindow(pid: getpid(), endingAt: Date(), duration: 15, to: csv))
    let content = try String(contentsOf: csv, encoding: .utf8)
    #expect(content.contains("game_memory_bytes"))
    #expect(content.split(separator: "\n").count == 3)
    #expect(!logger.sample(pid: nil, appUsage: resource, performance: .empty).status.contains("Logging"))
}

private func testClip(root: URL = URL(fileURLWithPath: "/tmp/test-clip")) -> Clip {
    Clip(id: UUID(), gameID: UUID(), gameName: "Roblox", sourceAppName: "Roblox", capturedAt: Date(),
         durationSeconds: 60, presetName: "Rivals", folderURL: root, clipURL: root.appendingPathComponent("clip.mov"),
         metadataURL: root.appendingPathComponent("metadata.json"), thumbnailURL: root.appendingPathComponent("thumbnail.jpg"))
}

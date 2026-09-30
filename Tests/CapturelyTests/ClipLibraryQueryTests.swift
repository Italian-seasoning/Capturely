import Foundation
import Testing
@testable import Capturely

@Test func clipLibraryQuerySearchesAllManagedMetadata() {
    let clips = [
        makeQueryClip(title: "Final Round", game: "Roblox", source: "Roblox Player", tags: ["ranked", "win"], date: 300),
        makeQueryClip(title: nil, game: "Minecraft", source: "Java", tags: ["build"], date: 200)
    ]

    #expect(ClipLibraryQuery.filter(clips, search: "final", filter: .all).count == 1)
    #expect(ClipLibraryQuery.filter(clips, search: "RÓBLOX", filter: .all).count == 1)
    #expect(ClipLibraryQuery.filter(clips, search: "player", filter: .all).count == 1)
    #expect(ClipLibraryQuery.filter(clips, search: "WIN", filter: .all).count == 1)
    #expect(ClipLibraryQuery.filter(clips, search: "", filter: .all) == clips)
}

@Test func clipLibraryQueryCombinesFiltersWithoutReordering() {
    var first = makeQueryClip(title: "One", game: "Roblox", source: nil, tags: [], date: 300)
    first.isStarred = true
    var second = makeQueryClip(title: "Two", game: "Roblox", source: nil, tags: [], date: 200)
    second.isStarred = true
    let third = makeQueryClip(title: "Three", game: "Minecraft", source: nil, tags: [], date: 100)
    let filter = ClipLibraryFilter(
        gameName: "roblox",
        starredOnly: true,
        dateInterval: DateInterval(start: Date(timeIntervalSince1970: 150), end: Date(timeIntervalSince1970: 350))
    )

    #expect(ClipLibraryQuery.filter([first, second, third], search: "", filter: filter) == [first, second])
}

@Test func clipLibraryMetadataNormalizationIsStable() {
    #expect(ClipLibraryQuery.normalizedTitle("  Final round  ") == "Final round")
    #expect(ClipLibraryQuery.normalizedTitle("   ") == nil)
    #expect(ClipLibraryQuery.normalizedTags([" Win ", "win", "Ranked", ""]) == ["Win", "Ranked"])
}

@Test func clipIndexStoreUpdatesMetadataAndIndexTogether() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let clip = makeQueryClip(title: nil, game: "Roblox", source: nil, tags: [], date: 100)
    var storedClip = clip
    storedClip.metadataURL = directory.appendingPathComponent("metadata.json")
    let store = ClipIndexStore(fileURL: directory.appendingPathComponent("clips.json"))
    try JSONEncoder.capturely.encode(storedClip).write(to: storedClip.metadataURL)
    try store.save([storedClip])

    let updated = try store.updateMetadata(for: storedClip, in: [storedClip], title: "Final", tags: ["win"])
    let metadata = try JSONDecoder.capturely.decode(Clip.self, from: Data(contentsOf: storedClip.metadataURL))
    let indexed = try store.load()

    #expect(updated.first?.title == "Final")
    #expect(indexed.first?.tags == ["win"])
    #expect(metadata.title == "Final")
}

@Test func clipIndexStoreRestoresMetadataWhenIndexSaveFails() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var clip = makeQueryClip(title: "Original", game: "Roblox", source: nil, tags: [], date: 100)
    clip.metadataURL = directory.appendingPathComponent("metadata.json")
    let original = try JSONEncoder.capturely.encode(clip)
    try original.write(to: clip.metadataURL)
    let invalidIndexURL = directory.appendingPathComponent("index-directory", isDirectory: true)
    try FileManager.default.createDirectory(at: invalidIndexURL, withIntermediateDirectories: true)
    let store = ClipIndexStore(fileURL: invalidIndexURL)

    #expect(throws: (any Error).self) {
        try store.updateMetadata(for: clip, in: [clip], title: "Changed", tags: ["new"])
    }
    #expect(try Data(contentsOf: clip.metadataURL) == original)
}

private func makeQueryClip(
    title: String?,
    game: String,
    source: String?,
    tags: [String],
    date: TimeInterval
) -> Clip {
    let directory = URL(fileURLWithPath: "/tmp/Capturely", isDirectory: true)
    var clip = Clip(
        gameID: UUID(),
        gameName: game,
        sourceAppName: source,
        capturedAt: Date(timeIntervalSince1970: date),
        durationSeconds: 30,
        presetName: "Studio",
        folderURL: directory,
        clipURL: directory.appendingPathComponent("clip.mov"),
        metadataURL: directory.appendingPathComponent("metadata.json"),
        thumbnailURL: directory.appendingPathComponent("thumbnail.jpg")
    )
    clip.title = title
    clip.tags = tags
    return clip
}

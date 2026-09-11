import Foundation
import Testing
@testable import Capturely

@Test func clipPathBuilderUsesGameDateTimeFolders() throws {
    let root = URL(fileURLWithPath: "/tmp/CapturelyTests")
    let date = Date(timeIntervalSince1970: 1_780_697_648)
    let builder = ClipPathBuilder(root: root, calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0)!)

    let destination = builder.destination(forGameName: "Valorant: Ranked/Swift", capturedAt: date)

    #expect(destination.folder.path == "/tmp/CapturelyTests/Valorant Ranked Swift/2026-06-05/22-14-08")
    #expect(destination.clipFile.lastPathComponent == "clip.mov")
    #expect(destination.metadataFile.lastPathComponent == "metadata.json")
    #expect(destination.thumbnailFile.lastPathComponent == "thumbnail.jpg")
}

@Test func clipPathBuilderAvoidsDuplicateTimestampFolders() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let date = Date(timeIntervalSince1970: 1_780_697_648)
    let builder = ClipPathBuilder(root: root, calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0)!)

    let first = builder.uniqueDestination(forGameName: "Roblox", capturedAt: date)
    try FileManager.default.createDirectory(at: first.folder, withIntermediateDirectories: true)
    let second = builder.uniqueDestination(forGameName: "Roblox", capturedAt: date)

    #expect(first.folder.lastPathComponent == "22-14-08")
    #expect(second.folder.lastPathComponent == "22-14-08-2")
}

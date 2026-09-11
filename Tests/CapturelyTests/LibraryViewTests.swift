import Foundation
import Testing
@testable import Capturely

@MainActor
@Test func libraryClipRowActionsCallConfiguredHandlers() {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let clip = Clip(
        gameID: UUID(),
        gameName: "Screen Capture",
        sourceAppName: "Roblox",
        capturedAt: Date(timeIntervalSince1970: 100),
        durationSeconds: 20,
        presetName: "Balanced",
        folderURL: directory,
        clipURL: directory.appendingPathComponent("clip.mov"),
        metadataURL: directory.appendingPathComponent("clip.json"),
        thumbnailURL: directory.appendingPathComponent("thumb.jpg")
    )
    var played: Clip?
    var revealed: Clip?
    var exported: Clip?
    var shared: Clip?
    var deleted: Clip?

    let row = LibraryClipRow(
        clip: clip,
        reveal: { revealed = $0 },
        play: { played = $0 },
        export: { exported = $0 },
        share: { shared = $0 },
        delete: { deleted = $0 }
    )

    row.performPlay()
    row.performReveal()
    row.performExport()
    row.performShare()
    row.performDelete()

    #expect(played == clip)
    #expect(revealed == clip)
    #expect(exported == clip)
    #expect(shared == clip)
    #expect(deleted == clip)
}

@Test func clipDecodesLegacyMetadataWithoutSourceAppName() throws {
    let json = """
    {
      "id" : "EFB3DDF2-A7F4-4BFC-97B7-058E75113098",
      "gameID" : "2666AC20-42C1-410F-A7C8-09E9864F4A9D",
      "gameName" : "Screen Capture",
      "capturedAt" : "2026-06-11T23:26:31Z",
      "durationSeconds" : 12,
      "presetName" : "Balanced",
      "folderURL" : "file:///tmp/Capturely/",
      "clipURL" : "file:///tmp/Capturely/clip.mov",
      "metadataURL" : "file:///tmp/Capturely/metadata.json",
      "thumbnailURL" : "file:///tmp/Capturely/thumbnail.jpg"
    }
    """

    let clip = try JSONDecoder.capturely.decode(Clip.self, from: Data(json.utf8))

    #expect(clip.gameName == "Screen Capture")
    #expect(clip.sourceAppName == nil)
    #expect(clip.durationSeconds == 12)
}

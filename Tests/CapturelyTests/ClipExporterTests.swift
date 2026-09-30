import Foundation
import Testing
@testable import Capturely

@Test func originalExportCopiesWithoutChangingSource() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("source.mov")
    let destination = directory.appendingPathComponent("shared.mov")
    let bytes = Data("movie-data".utf8)
    try bytes.write(to: source)

    try await ClipExporter().export(source: source, destination: destination, preset: .original)

    #expect(try Data(contentsOf: source) == bytes)
    #expect(try Data(contentsOf: destination) == bytes)
}

@Test func exportRejectsSourceAsDestination() async throws {
    let source = URL(fileURLWithPath: "/tmp/source.mov")

    await #expect(throws: ClipExporterError.self) {
        try await ClipExporter().export(source: source, destination: source, preset: .original)
    }
}

@Test func exportPresetNamesAreStable() {
    #expect(ClipExportPreset.allCases.map(\.displayName) == ["Original", "1080p", "720p"])
    #expect(ClipExportPreset.hd1080.filenameSuffix == "1080p")
}

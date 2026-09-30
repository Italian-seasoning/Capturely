import AVFoundation
import Foundation

enum ClipExporterError: LocalizedError {
    case sourceAndDestinationMatch
    case cannotCreateExporter
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .sourceAndDestinationMatch: "Choose a different location from the original clip."
        case .cannotCreateExporter: "This clip cannot be exported with the selected preset."
        case .invalidOutput: "The exported clip is empty or unreadable."
        }
    }
}

struct ClipExporter: Sendable {
    func export(source: URL, destination: URL, preset: ClipExportPreset) async throws {
        guard source.standardizedFileURL != destination.standardizedFileURL else {
            throw ClipExporterError.sourceAndDestinationMatch
        }

        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".capturely-export-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: temporary) }

        if let assetPreset = preset.assetExportPreset {
            let asset = AVURLAsset(url: source)
            guard let exporter = AVAssetExportSession(asset: asset, presetName: assetPreset) else {
                throw ClipExporterError.cannotCreateExporter
            }
            try await exporter.export(to: temporary, as: .mov)
        } else {
            try FileManager.default.copyItem(at: source, to: temporary)
        }

        guard CaptureCoordinator.isValidClipOutput(temporary) else {
            throw ClipExporterError.invalidOutput
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }
}

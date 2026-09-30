import Foundation

struct ClipIndexStore: Sendable {
    var fileURL: URL

    func load() throws -> [Clip] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.capturely.decode([Clip].self, from: data)
    }

    func save(_ clips: [Clip]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.capturely.encode(clips)
        try data.write(to: fileURL, options: [.atomic])
    }

    func updateMetadata(
        for clip: Clip,
        in clips: [Clip],
        title: String?,
        tags: [String]
    ) throws -> [Clip] {
        guard let index = clips.firstIndex(where: { $0.id == clip.id }) else { return clips }
        let oldMetadata = try? Data(contentsOf: clip.metadataURL)
        var updated = clips
        updated[index].title = title
        updated[index].tags = tags

        do {
            try JSONEncoder.capturely.encode(updated[index]).write(to: clip.metadataURL, options: [.atomic])
            try save(updated)
            return updated
        } catch {
            if let oldMetadata {
                try? oldMetadata.write(to: clip.metadataURL, options: [.atomic])
            } else {
                try? FileManager.default.removeItem(at: clip.metadataURL)
            }
            throw error
        }
    }

    func loadAsync() async throws -> [Clip] {
        try await Task.detached(priority: .utility) {
            try load()
        }.value
    }

    func saveAsync(_ clips: [Clip]) async throws {
        try await Task.detached(priority: .utility) {
            try save(clips)
        }.value
    }
}

extension JSONEncoder {
    static var capturely: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var capturely: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

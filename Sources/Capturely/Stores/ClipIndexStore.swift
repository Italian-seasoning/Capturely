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

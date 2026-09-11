import Foundation

struct GameRegistryStore: Sendable {
    var fileURL: URL

    func load() throws -> [Game] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.capturely.decode([Game].self, from: data)
    }

    func save(_ games: [Game]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.capturely.encode(games)
        try data.write(to: fileURL, options: [.atomic])
    }
}

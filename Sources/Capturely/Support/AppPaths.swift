import Foundation

struct AppPaths {
    var fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var applicationSupportDirectory: URL {
        get throws {
            let base = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = base.appendingPathComponent("Capturely", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    var defaultClipLibraryDirectory: URL {
        get throws {
            let movies = try fileManager.url(
                for: .moviesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return movies.appendingPathComponent("Capturely/Clips", isDirectory: true)
        }
    }
}

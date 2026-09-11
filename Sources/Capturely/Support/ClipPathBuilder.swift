import Foundation

struct ClipDestination: Equatable, Sendable {
    var folder: URL
    var clipFile: URL
    var metadataFile: URL
    var thumbnailFile: URL
}

struct ClipPathBuilder: Sendable {
    var root: URL
    var calendar: Calendar
    var timeZone: TimeZone

    func destination(forGameName gameName: String, capturedAt date: Date) -> ClipDestination {
        destination(forGameName: gameName, capturedAt: date, folderSuffix: nil)
    }

    func uniqueDestination(forGameName gameName: String, capturedAt date: Date, fileManager: FileManager = .default) -> ClipDestination {
        let base = destination(forGameName: gameName, capturedAt: date)
        guard fileManager.fileExists(atPath: base.folder.path) else {
            return base
        }

        for index in 2...999 {
            let candidate = destination(forGameName: gameName, capturedAt: date, folderSuffix: "\(index)")
            if !fileManager.fileExists(atPath: candidate.folder.path) {
                return candidate
            }
        }

        return destination(forGameName: gameName, capturedAt: Date())
    }

    private func destination(forGameName gameName: String, capturedAt date: Date, folderSuffix: String?) -> ClipDestination {
        var calendar = calendar
        calendar.timeZone = timeZone

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let dateFolder = String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
        let timeStem = String(format: "%02d-%02d-%02d", components.hour!, components.minute!, components.second!)
        let timeFolder = folderSuffix.map { "\(timeStem)-\($0)" } ?? timeStem
        let folder = root
            .appendingPathComponent(Self.sanitizedFolderName(gameName), isDirectory: true)
            .appendingPathComponent(dateFolder, isDirectory: true)
            .appendingPathComponent(timeFolder, isDirectory: true)

        return ClipDestination(
            folder: folder,
            clipFile: folder.appendingPathComponent("clip.mov"),
            metadataFile: folder.appendingPathComponent("metadata.json"),
            thumbnailFile: folder.appendingPathComponent("thumbnail.jpg")
        )
    }

    static func sanitizedFolderName(_ value: String) -> String {
        let disallowed = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let scalars = value.unicodeScalars.map { disallowed.contains($0) ? " " : String($0) }.joined()
        return scalars
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

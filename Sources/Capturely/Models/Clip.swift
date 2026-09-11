import Foundation

struct Clip: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var gameID: Game.ID
    var gameName: String
    var sourceAppName: String?
    var capturedAt: Date
    var durationSeconds: Int
    var presetName: String
    var folderURL: URL
    var clipURL: URL
    var metadataURL: URL
    var thumbnailURL: URL
    var isStarred: Bool? = nil
    var editableSourceURL: URL? = nil
    var processLogURL: URL? = nil

    init(
        id: UUID = UUID(),
        gameID: Game.ID,
        gameName: String,
        sourceAppName: String? = nil,
        capturedAt: Date,
        durationSeconds: Int,
        presetName: String,
        folderURL: URL,
        clipURL: URL,
        metadataURL: URL,
        thumbnailURL: URL
    ) {
        self.id = id
        self.gameID = gameID
        self.gameName = gameName
        self.sourceAppName = sourceAppName
        self.capturedAt = capturedAt
        self.durationSeconds = durationSeconds
        self.presetName = presetName
        self.folderURL = folderURL
        self.clipURL = clipURL
        self.metadataURL = metadataURL
        self.thumbnailURL = thumbnailURL
    }
}

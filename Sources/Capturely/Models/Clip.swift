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
    var title: String? = nil
    var tags: [String] = []
    var audioTracks: [ClipAudioTrack] = []

    enum CodingKeys: String, CodingKey {
        case id, gameID, gameName, sourceAppName, capturedAt, durationSeconds, presetName
        case folderURL, clipURL, metadataURL, thumbnailURL
        case isStarred, editableSourceURL, processLogURL, title, tags, audioTracks
    }

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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        gameID = try container.decode(Game.ID.self, forKey: .gameID)
        gameName = try container.decode(String.self, forKey: .gameName)
        sourceAppName = try container.decodeIfPresent(String.self, forKey: .sourceAppName)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        durationSeconds = try container.decode(Int.self, forKey: .durationSeconds)
        presetName = try container.decode(String.self, forKey: .presetName)
        folderURL = try container.decode(URL.self, forKey: .folderURL)
        clipURL = try container.decode(URL.self, forKey: .clipURL)
        metadataURL = try container.decode(URL.self, forKey: .metadataURL)
        thumbnailURL = try container.decode(URL.self, forKey: .thumbnailURL)
        isStarred = try container.decodeIfPresent(Bool.self, forKey: .isStarred)
        editableSourceURL = try container.decodeIfPresent(URL.self, forKey: .editableSourceURL)
        processLogURL = try container.decodeIfPresent(URL.self, forKey: .processLogURL)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        audioTracks = try container.decodeIfPresent([ClipAudioTrack].self, forKey: .audioTracks) ?? []
    }
}

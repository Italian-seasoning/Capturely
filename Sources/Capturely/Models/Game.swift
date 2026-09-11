import Foundation

struct Game: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var displayName: String
    var bundleIdentifier: String?
    var appURL: URL?
    var executableURL: URL?
    var preferredWindowTitle: String?
    var presetID: CapturePreset.ID?

    init(
        id: UUID = UUID(),
        displayName: String,
        bundleIdentifier: String? = nil,
        appURL: URL? = nil,
        executableURL: URL? = nil,
        preferredWindowTitle: String? = nil,
        presetID: CapturePreset.ID? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.appURL = appURL
        self.executableURL = executableURL
        self.preferredWindowTitle = preferredWindowTitle
        self.presetID = presetID
    }
}

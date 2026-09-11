import Foundation

enum CaptureState: Equatable, Sendable {
    case idle
    case waitingForWindow(game: Game)
    case permissionRequired(reason: String)
    case recording(game: Game, preset: CapturePreset)
    case savingClip(game: Game)
    case failed(message: String)
}

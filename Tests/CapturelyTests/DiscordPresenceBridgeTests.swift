import Foundation
import Testing
@testable import Capturely

@MainActor
@Test func discordPresenceBridgeUsesLoopbackOnlyEndpoint() {
    #expect(DiscordPresenceBridge.listenerHost == "127.0.0.1")
    #expect(DiscordPresenceBridge.listenerPort.rawValue == 48731)
}

@MainActor
@Test func discordPresenceBridgeActivityOmitsPrivateGameMetadata() throws {
    let bridge = DiscordPresenceBridge()
    bridge.update(.recording(game: privateGameFixture(), preset: .balanced))

    let payload = bridge.payloadForTesting
    let message = try presenceMessage(from: payload)
    let activity = message["activity"] as? [String: Any] ?? [:]
    let timestamps = activity["timestamps"] as? [String: Any] ?? [:]
    let encoded = String(decoding: payload, as: UTF8.self)

    #expect(Set(message.keys) == Set(["version", "type", "activity"]))
    #expect(message["version"] as? Int == 1)
    #expect(message["type"] as? String == "activity")
    #expect(Set(activity.keys) == Set([
        "appId", "appName", "details", "state", "activityType", "timestamps", "source", "confidence"
    ]))
    #expect(activity["appId"] as? String == "com.capturely.app")
    #expect(activity["appName"] as? String == "Capturely")
    #expect(activity["details"] as? String == "Buffering gameplay")
    #expect(activity["state"] as? String == "Instant replay")
    #expect(activity["activityType"] as? String == "PLAYING")
    #expect(activity["source"] as? String == "capturely")
    #expect(activity["confidence"] as? Double == 1.0)
    #expect(Set(timestamps.keys) == Set(["start"]))
    #expect((timestamps["start"] as? Int ?? 0) > 0)
    #expect(!encoded.contains("SYNTHETIC_PRIVATE_GAME_NAME"))
    #expect(!encoded.contains("SYNTHETIC_PRIVATE_WINDOW_TITLE"))
    #expect(!encoded.contains("SYNTHETIC_PRIVATE_PATH"))
}

@MainActor
@Test func discordPresenceBridgeSavingActivityKeepsCaptureStartTime() throws {
    let bridge = DiscordPresenceBridge()
    let game = privateGameFixture()
    bridge.update(.recording(game: game, preset: .balanced))
    let recording = try presenceMessage(from: bridge.payloadForTesting)
    let recordingActivity = recording["activity"] as? [String: Any] ?? [:]
    let recordingTimestamps = recordingActivity["timestamps"] as? [String: Any] ?? [:]
    let originalStart = recordingTimestamps["start"] as? Int

    bridge.update(.savingClip(game: game))
    let saving = try presenceMessage(from: bridge.payloadForTesting)
    let savingActivity = saving["activity"] as? [String: Any] ?? [:]
    let savingTimestamps = savingActivity["timestamps"] as? [String: Any] ?? [:]
    let savingStart = savingTimestamps["start"] as? Int

    #expect(saving["type"] as? String == "activity")
    #expect(savingActivity["details"] as? String == "Saving a replay")
    #expect((originalStart ?? 0) > 0)
    #expect(savingStart == originalStart)
}

@MainActor
@Test func discordPresenceBridgeClearsActivityWhenCaptureStops() throws {
    let bridge = DiscordPresenceBridge()
    bridge.update(.recording(game: privateGameFixture(), preset: .balanced))

    bridge.update(.idle)

    let message = try presenceMessage(from: bridge.payloadForTesting)
    #expect(Set(message.keys) == Set(["version", "type"]))
    #expect(message["version"] as? Int == 1)
    #expect(message["type"] as? String == "clear")
}

private func presenceMessage(from payload: Data) throws -> [String: Any] {
    (try JSONSerialization.jsonObject(with: payload)) as? [String: Any] ?? [:]
}

private func privateGameFixture() -> Game {
    Game(
        displayName: "SYNTHETIC_PRIVATE_GAME_NAME",
        bundleIdentifier: "com.capturely.test",
        appURL: URL(fileURLWithPath: "/tmp/SYNTHETIC_PRIVATE_PATH/clip.mov"),
        executableURL: URL(fileURLWithPath: "/tmp/SYNTHETIC_PRIVATE_EXECUTABLE_PATH"),
        preferredWindowTitle: "SYNTHETIC_PRIVATE_WINDOW_TITLE"
    )
}

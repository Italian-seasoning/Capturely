import Foundation
import Testing
@testable import Capturely

@Test func scannerBuildsGameFromAppBundle() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let app = root.appendingPathComponent("Example Game.app", isDirectory: true)
    let contents = app.appendingPathComponent("Contents", isDirectory: true)
    let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
    try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)

    let plist = contents.appendingPathComponent("Info.plist")
    let plistBody = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleIdentifier</key>
      <string>com.example.game</string>
      <key>CFBundleName</key>
      <string>Example Game</string>
      <key>CFBundleExecutable</key>
      <string>ExampleGame</string>
    </dict>
    </plist>
    """
    try plistBody.data(using: .utf8)!.write(to: plist)

    let game = try ApplicationScanner.game(fromApplicationURL: app)

    #expect(game.displayName == "Example Game")
    #expect(game.bundleIdentifier == "com.example.game")
    #expect(game.appURL == app)
    #expect(game.executableURL == macOS.appendingPathComponent("ExampleGame"))
}

@Test func scannerBuildsGameFromRunningAppSnapshot() throws {
    let executableURL = URL(fileURLWithPath: "/Applications/Roblox.app/Contents/MacOS/RobloxPlayer")
    let snapshot = RunningAppSnapshot(
        processIdentifier: 99,
        bundleIdentifier: "com.roblox.RobloxPlayer",
        executableURL: executableURL,
        localizedName: "RobloxPlayer"
    )

    let game = try #require(ApplicationScanner.game(fromRunningAppSnapshot: snapshot))

    #expect(game.displayName == "Roblox")
    #expect(game.bundleIdentifier == "com.roblox.RobloxPlayer")
    #expect(game.appURL?.path == "/Applications/Roblox.app")
    #expect(game.executableURL == executableURL)
}

@Test func scannerMergesGamesWithoutDuplicateBundleIDs() {
    let existing = [
        Game(displayName: "Roblox", bundleIdentifier: "com.roblox.RobloxPlayer")
    ]
    let incoming = [
        Game(displayName: "Roblox", bundleIdentifier: "com.roblox.RobloxPlayer"),
        Game(displayName: "Example", bundleIdentifier: "com.example.game")
    ]

    let merged = ApplicationScanner.merge(existing: existing, incoming: incoming)

    #expect(merged.map(\.bundleIdentifier) == ["com.roblox.RobloxPlayer", "com.example.game"])
}

@Test func scannerMergesMissingPresetFromBuiltInGame() {
    let existing = [
        Game(displayName: "Roblox", bundleIdentifier: "com.roblox.RobloxPlayer")
    ]
    let incoming = [
        Game(displayName: "Roblox", bundleIdentifier: "com.roblox.RobloxPlayer", presetID: CapturePreset.storageSaver.id)
    ]

    let merged = ApplicationScanner.merge(existing: existing, incoming: incoming)

    #expect(merged.count == 1)
    #expect(merged.first?.presetID == CapturePreset.storageSaver.id)
}

@Test func scannerMergeKeepsExistingPresetChoice() {
    let existing = [
        Game(displayName: "Roblox", bundleIdentifier: "com.roblox.RobloxPlayer", presetID: CapturePreset.editing.id)
    ]
    let incoming = [
        Game(displayName: "Roblox", bundleIdentifier: "com.roblox.RobloxPlayer", presetID: CapturePreset.storageSaver.id)
    ]

    let merged = ApplicationScanner.merge(existing: existing, incoming: incoming)

    #expect(merged.count == 1)
    #expect(merged.first?.presetID == CapturePreset.editing.id)
}

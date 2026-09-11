import Foundation
import Testing
@testable import Capturely

@Test func processMatcherFindsGameByBundleIdentifier() {
    let game = Game(displayName: "Example", bundleIdentifier: "com.example.game")
    let app = RunningAppSnapshot(processIdentifier: 42, bundleIdentifier: "com.example.game", executableURL: nil, localizedName: "Example")

    let match = ProcessMonitor.match(games: [game], runningApps: [app])

    #expect(match?.game == game)
    #expect(match?.processIdentifier == 42)
    #expect(match?.detectedAppName == "Example")
}

@Test func processMatcherFindsRobloxPlayerVariant() {
    let game = Game(displayName: "Roblox", bundleIdentifier: "com.roblox.Roblox")
    let app = RunningAppSnapshot(
        processIdentifier: 42,
        bundleIdentifier: "com.roblox.RobloxPlayer",
        executableURL: URL(fileURLWithPath: "/Applications/Roblox.app/Contents/MacOS/RobloxPlayer"),
        localizedName: "RobloxPlayer"
    )

    let match = ProcessMonitor.match(games: [game], runningApps: [app])

    #expect(match?.game.displayName == "Roblox")
    #expect(match?.detectedAppName == "RobloxPlayer")
}

@Test func processMatcherIgnoresRobloxUpdateHelper() {
    let game = Game(displayName: "Roblox", bundleIdentifier: "com.roblox.Roblox")
    let helper = RunningAppSnapshot(
        processIdentifier: 42,
        bundleIdentifier: "com.lincolnmuller.RobloxUpdateHelper.Helper",
        executableURL: URL(fileURLWithPath: "/Applications/Roblox Update Helper.app/Contents/MacOS/Roblox Update Helper Helper"),
        localizedName: "Roblox Update Helper Helper"
    )

    #expect(ProcessMonitor.match(games: [game], runningApps: [helper]) == nil)
}

@Test func processMatcherFindsGameByLocalizedNameWhenBundleWasMissing() {
    let game = Game(displayName: "Roblox")
    let app = RunningAppSnapshot(
        processIdentifier: 42,
        bundleIdentifier: nil,
        executableURL: nil,
        localizedName: "RobloxPlayer"
    )

    let match = ProcessMonitor.match(games: [game], runningApps: [app])

    #expect(match?.game.displayName == "Roblox")
}

@MainActor
@Test func processMonitorStartIsIdempotent() {
    let monitor = ProcessMonitor()

    monitor.start(games: [])
    monitor.start(games: [])

    #expect(monitor.observerCountForTesting == 2)
    #expect(monitor.isPeriodicRefreshActiveForTesting)
    monitor.stop()
    #expect(monitor.observerCountForTesting == 0)
    #expect(!monitor.isPeriodicRefreshActiveForTesting)
}

@MainActor
@Test func processMonitorNotifiesWhenMatchChanges() {
    let monitor = ProcessMonitor()
    let game = Game(displayName: "Roblox", bundleIdentifier: "com.roblox.Roblox")
    let app = RunningAppSnapshot(processIdentifier: 99, bundleIdentifier: "com.roblox.Roblox", executableURL: nil, localizedName: "Roblox")
    var observed: [RunningGameMatch?] = []

    monitor.onMatchChanged = { match in
        observed.append(match)
    }

    monitor.refresh(games: [game], runningApps: [app])
    monitor.refresh(games: [game], runningApps: [])

    #expect(observed == [
        RunningGameMatch(game: game, processIdentifier: 99, detectedAppName: "Roblox"),
        nil
    ])
}

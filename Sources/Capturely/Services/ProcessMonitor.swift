import AppKit
import Foundation

struct RunningAppSnapshot: Equatable, Sendable {
    var processIdentifier: pid_t
    var bundleIdentifier: String?
    var executableURL: URL?
    var localizedName: String?
}

struct RunningGameMatch: Equatable, Sendable {
    var game: Game
    var processIdentifier: pid_t
    var detectedAppName: String?
}

@MainActor
final class ProcessMonitor: ObservableObject {
    @Published private(set) var currentMatch: RunningGameMatch?
    var onMatchChanged: ((RunningGameMatch?) -> Void)?

    private var games: [Game] = []
    private var observers: [NSObjectProtocol] = []
    private var refreshTask: Task<Void, Never>?

    var observerCountForTesting: Int { observers.count }
    var isPeriodicRefreshActiveForTesting: Bool { refreshTask != nil }

    func start(games: [Game]) {
        stop()
        self.games = games
        refresh()

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        })
        startPeriodicRefresh()
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers = []
        currentMatch = nil
    }

    private func startPeriodicRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.refresh()
                }
            }
        }
    }

    func refresh() {
        let snapshots = NSWorkspace.shared.runningApplications.map {
            RunningAppSnapshot(
                processIdentifier: $0.processIdentifier,
                bundleIdentifier: $0.bundleIdentifier,
                executableURL: $0.executableURL,
                localizedName: $0.localizedName
            )
        }
        refresh(games: games, runningApps: snapshots)
    }

    func refresh(games: [Game], runningApps: [RunningAppSnapshot]) {
        let nextMatch = Self.match(games: games, runningApps: runningApps)
        guard nextMatch != currentMatch else { return }
        currentMatch = nextMatch
        onMatchChanged?(nextMatch)
    }

    nonisolated static func match(games: [Game], runningApps: [RunningAppSnapshot]) -> RunningGameMatch? {
        for app in runningApps {
            if let match = games.first(where: { game in
                Self.matches(game: game, app: app)
            }) {
                return RunningGameMatch(
                    game: match,
                    processIdentifier: app.processIdentifier,
                    detectedAppName: app.localizedName
                )
            }
        }
        return nil
    }

    private nonisolated static func matches(game: Game, app: RunningAppSnapshot) -> Bool {
        if let bundleIdentifier = game.bundleIdentifier, bundleIdentifier == app.bundleIdentifier {
            return true
        }
        if let executableURL = game.executableURL, executableURL == app.executableURL {
            return true
        }

        let gameTokens = [
            game.displayName,
            game.bundleIdentifier,
            game.executableURL?.lastPathComponent
        ].compactMap { $0?.lowercased() }
        let appTokens = [
            app.localizedName,
            app.bundleIdentifier,
            app.executableURL?.lastPathComponent
        ].compactMap { $0?.lowercased() }

        let isRobloxGame = gameTokens.contains { $0.contains("roblox") }
        let isRobloxApp = appTokens.contains { $0.contains("roblox") }
        let isRobloxUpdateHelper = appTokens.contains {
            $0.contains("robloxupdatehelper") || $0.contains("roblox update helper")
        }

        if isRobloxGame && isRobloxUpdateHelper {
            return false
        }

        if isRobloxGame && isRobloxApp {
            return true
        }

        return gameTokens.contains { gameToken in
            appTokens.contains { appToken in
                appToken == gameToken || appToken.contains(gameToken)
            }
        }
    }
}

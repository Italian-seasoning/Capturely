import Foundation

struct ApplicationScanner: Sendable {
    static func game(fromApplicationURL appURL: URL) throws -> Game {
        let infoPlist = appURL.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: infoPlist)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dictionary = plist as? [String: Any] else {
            throw ApplicationScannerError.invalidInfoPlist(appURL)
        }

        let bundleName = dictionary["CFBundleName"] as? String
        let displayName = bundleName ?? appURL.deletingPathExtension().lastPathComponent
        let bundleIdentifier = dictionary["CFBundleIdentifier"] as? String
        let executableName = dictionary["CFBundleExecutable"] as? String
        let executableURL = executableName.map {
            appURL.appendingPathComponent("Contents/MacOS").appendingPathComponent($0)
        }

        return Game(
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            appURL: appURL,
            executableURL: executableURL
        )
    }

    static func game(fromRunningAppSnapshot snapshot: RunningAppSnapshot) -> Game? {
        guard snapshot.bundleIdentifier != nil || snapshot.executableURL != nil || snapshot.localizedName != nil else {
            return nil
        }

        let displayName = normalizedDisplayName(snapshot.localizedName ?? snapshot.executableURL?.deletingPathExtension().lastPathComponent ?? "Unknown App")
        let appURL = snapshot.executableURL.flatMap(appURLFromExecutableURL)

        return Game(
            displayName: displayName,
            bundleIdentifier: snapshot.bundleIdentifier,
            appURL: appURL,
            executableURL: snapshot.executableURL
        )
    }

    static func merge(existing: [Game], incoming: [Game]) -> [Game] {
        var merged = existing
        for game in incoming {
            if let index = merged.firstIndex(where: { $0.matchesIdentity(of: game) }) {
                if merged[index].presetID == nil, let presetID = game.presetID {
                    merged[index].presetID = presetID
                }
            } else {
                merged.append(game)
            }
        }
        return merged
    }

    func scanApplicationDirectories() -> [Game] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        return roots.flatMap { root -> [Game] in
            guard let urls = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
                return []
            }
            return urls
                .filter { $0.pathExtension == "app" }
                .compactMap { try? Self.game(fromApplicationURL: $0) }
        }
    }

    private static func normalizedDisplayName(_ value: String) -> String {
        if value.localizedCaseInsensitiveContains("roblox") {
            return "Roblox"
        }
        return value
    }

    private static func appURLFromExecutableURL(_ executableURL: URL) -> URL? {
        var current = executableURL
        while current.path != "/" {
            if current.pathExtension == "app" {
                return current
            }
            current.deleteLastPathComponent()
        }
        return nil
    }
}

enum ApplicationScannerError: Error, Equatable {
    case invalidInfoPlist(URL)
}

extension Game {
    func matchesIdentity(of other: Game) -> Bool {
        if let bundleIdentifier, let otherBundleIdentifier = other.bundleIdentifier,
           bundleIdentifier == otherBundleIdentifier {
            return true
        }
        if let executableURL, let otherExecutableURL = other.executableURL,
           executableURL == otherExecutableURL {
            return true
        }
        if let appURL, let otherAppURL = other.appURL,
           appURL == otherAppURL {
            return true
        }
        return displayName.localizedCaseInsensitiveCompare(other.displayName) == .orderedSame
    }
}

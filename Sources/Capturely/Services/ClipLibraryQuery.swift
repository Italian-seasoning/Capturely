import Foundation

struct ClipLibraryFilter: Equatable, Sendable {
    var gameName: String?
    var starredOnly: Bool
    var dateInterval: DateInterval?

    static let all = Self(gameName: nil, starredOnly: false, dateInterval: nil)

    init(gameName: String? = nil, starredOnly: Bool = false, dateInterval: DateInterval? = nil) {
        self.gameName = gameName
        self.starredOnly = starredOnly
        self.dateInterval = dateInterval
    }
}

enum ClipLibraryQuery {
    static func filter(_ clips: [Clip], search: String, filter: ClipLibraryFilter) -> [Clip] {
        let query = normalized(search.trimmingCharacters(in: .whitespacesAndNewlines))
        let game = filter.gameName.map(normalized)

        return clips.filter { clip in
            if filter.starredOnly, clip.isStarred != true { return false }
            if let game, normalized(clip.gameName) != game { return false }
            if let dateInterval = filter.dateInterval, !dateInterval.contains(clip.capturedAt) { return false }
            guard !query.isEmpty else { return true }

            return [clip.title, clip.gameName, clip.sourceAppName]
                .compactMap { $0 }
                .map(normalized)
                .contains { $0.contains(query) }
                || clip.tags.map(normalized).contains { $0.contains(query) }
        }
    }

    static func normalizedTitle(_ title: String) -> String? {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            let value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(normalized(value)).inserted else { return nil }
            return value
        }.prefix(12).map { $0 }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

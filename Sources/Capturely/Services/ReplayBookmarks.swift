import Foundation

struct ClipBookmark: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var seconds: Double
    var label: String = "Bookmark"
}

struct ReplayBookmarks {
    private var moments: [Date] = []

    @discardableResult mutating func add(now: Date = Date()) -> Bool {
        moments.removeAll { now.timeIntervalSince($0) > 620 }
        // Debounce repeated key presses without a timer; retain a bounded replay history.
        guard moments.last.map({ now.timeIntervalSince($0) >= 0.5 }) ?? true else { return false }
        moments.append(now)
        if moments.count > 512 { moments.removeFirst(moments.count - 512) }
        return true
    }

    mutating func reset() { moments.removeAll(keepingCapacity: true) }

    func snapshot(segments: [ReplaySegment], duration: Double) -> [ClipBookmark] {
        var skip = max(0, segments.reduce(0) { $0 + $1.durationSeconds } - duration)
        var cursor = 0.0
        var result: [ClipBookmark] = []
        for segment in segments {
            let leading = min(skip, segment.durationSeconds)
            skip -= leading
            let length = segment.durationSeconds - leading
            guard length > 0 else { continue }
            let start = segment.startedAt.addingTimeInterval(leading)
            let end = start.addingTimeInterval(length)
            result += moments.filter { $0 >= start && $0 < end }.map {
                ClipBookmark(seconds: cursor + $0.timeIntervalSince(start))
            }
            cursor += length
        }
        return result.sorted { $0.seconds < $1.seconds }
    }

    static func trimmed(_ bookmarks: [ClipBookmark], start: Double, end: Double) -> [ClipBookmark] {
        bookmarks.filter { $0.seconds.isFinite && $0.seconds >= start && $0.seconds < end }.map {
            var marker = $0; marker.seconds -= start; return marker
        }
    }
}

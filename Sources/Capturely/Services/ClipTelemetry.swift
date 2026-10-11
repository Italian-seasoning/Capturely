import Foundation

enum TelemetryMetric: String, CaseIterable, Identifiable {
    case fps = "Sampled FPS", ping = "Ping", cpu = "CPU", gpu = "GPU"
    var id: String { rawValue }
    var unit: String { self == .fps ? "fps" : self == .ping ? "ms" : "%" }
    func value(_ reading: FrameBarReading) -> Double? {
        let value: Double?
        switch self { case .fps: value = reading.gameFPS; case .ping: value = reading.pingMS; case .cpu: value = reading.cpu; case .gpu: value = reading.gpu }
        guard let value, value.isFinite, value >= 0, self != .fps || value > 0 else { return nil }
        return value
    }
}

struct TelemetryPoint: Identifiable {
    let id: Int
    let seconds: Double
    let value: Double
    let segment: Int
}

struct TelemetrySummary: Equatable {
    var average: Double
    var minimum: Double
    var maximum: Double
    var coveredSeconds: Double
    var samples: Int
}

enum ClipTelemetryError: LocalizedError {
    case oversized
    var errorDescription: String? { "Telemetry exceeds the supported size. Limit: 4 MB or 5,000 entries." }
}

enum ClipTelemetry {
    static func load(_ url: URL) async throws -> [TimedTelemetry] {
        try await Task.detached(priority: .utility) {
            guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= 4 * 1024 * 1024 else { throw ClipTelemetryError.oversized }
            let entries = try JSONDecoder().decode([TimedTelemetry].self, from: Data(contentsOf: url))
            guard entries.count <= 5_000 else { throw ClipTelemetryError.oversized }
            return entries
        }.value
    }

    /// Clamp to the movie, exclude malformed spans, and avoid double-counting overlaps.
    static func normalized(_ entries: [TimedTelemetry], duration: Double) -> [TimedTelemetry] {
        guard duration.isFinite, duration > 0 else { return [] }
        var cursor = 0.0
        return entries.filter { $0.seconds.isFinite && $0.duration.isFinite && $0.duration > 0 }
            .sorted { $0.seconds < $1.seconds }.compactMap { entry in
                let lower = max(0, cursor, entry.seconds)
                let upper = min(duration, entry.seconds + entry.duration)
                guard upper.isFinite, upper > lower else { return nil }
                cursor = upper
                return TimedTelemetry(seconds: lower, duration: upper - lower, reading: entry.reading)
            }
    }

    static func summary(_ entries: [TimedTelemetry], metric: TelemetryMetric, duration: Double) -> TelemetrySummary? {
        let values = normalized(entries, duration: duration).compactMap { entry -> (Double, Double)? in
            metric.value(entry.reading).map { ($0, entry.duration) }
        }
        let coverage = values.reduce(0) { $0 + $1.1 }
        guard coverage > 0 else { return nil }
        return TelemetrySummary(average: values.reduce(0) { $0 + $1.0 * $1.1 } / coverage,
            minimum: values.map(\.0).min()!, maximum: values.map(\.0).max()!,
            coveredSeconds: coverage, samples: values.count)
    }

    static func points(_ entries: [TimedTelemetry], metric: TelemetryMetric, duration: Double) -> [TelemetryPoint] {
        var result: [TelemetryPoint] = []
        var segment = 0
        var previousEnd = -Double.infinity
        for entry in normalized(entries, duration: duration) {
            guard let value = metric.value(entry.reading) else { previousEnd = -.infinity; continue }
            if entry.seconds - previousEnd > 0.001 { segment += 1 }
            result.append(TelemetryPoint(id: result.count, seconds: entry.seconds, value: value, segment: segment))
            previousEnd = entry.seconds + entry.duration
            result.append(TelemetryPoint(id: result.count, seconds: previousEnd, value: value, segment: segment))
        }
        return result
    }
}

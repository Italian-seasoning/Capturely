import Foundation

struct FrameBarReading: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var gamePID: Int32
    var timestamp: Double
    var gameFPS: Double?
    var cpu: Double?
    var memoryUsed: Double?
    var gpu: Double?
    var robloxCPU: Double?
    var robloxMemory: Double?
    var pingMS: Double?
    var gameCPUMS: Double?
    var gameGPUMS: Double?
    var thermalState: String?
    var gameStatsTimestamp: Double?
    var captureFPS: Double?
    var encoderDrops: Int?

    var subtitle: String {
        func number(_ value: Double?, _ unit: String) -> String {
            guard let value, value.isFinite else { return "—" }
            return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value) + unit
        }
        return "Game \(number(gameFPS, " fps"))  •  CPU \(number(cpu, "%"))  RAM \(number(memoryUsed, " GB"))  GPU \(number(gpu, "%"))\nPing \(number(pingMS, " ms"))  CPU/GPU \(number(gameCPUMS, ""))/\(number(gameGPUMS, " ms"))  Capture \(number(captureFPS, " fps"))"
    }
}

struct TimedTelemetry: Codable, Equatable, Sendable {
    var seconds: Double
    var duration: Double
    var reading: FrameBarReading
}

enum TelemetryExportError: LocalizedError {
    case conflictingSidecar(String)
    var errorDescription: String? {
        switch self {
        case .conflictingSidecar(let name): "Existing \(name) has different clip data. Choose a new export filename."
        }
    }
}

@MainActor final class FrameBarPlugin {
    private(set) var samples: [FrameBarReading] = []
    private var pid: Int32?
    private var requestActive = false
    private let snapshotURL: URL?

    init(snapshotURL: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("FrameBar/capturely-telemetry.json")) {
        self.snapshotURL = snapshotURL
    }

    func sample(pid: Int32?, now: Date = Date(), performance: CapturePerformanceSnapshot = .empty) {
        samples.removeAll { now.timeIntervalSince1970 - $0.timestamp > 620 }
        if self.pid != pid { samples.removeAll(); self.pid = pid }
        if let snapshotURL {
            let request = snapshotURL.deletingLastPathComponent().appendingPathComponent("capturely-request.json")
            if let pid {
                try? FileManager.default.createDirectory(at: request.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let data = try? JSONSerialization.data(withJSONObject: ["gamePID": Double(pid), "timestamp": now.timeIntervalSince1970]) {
                    try? data.write(to: request, options: .atomic)
                    requestActive = true
                }
            } else if requestActive {
                try? FileManager.default.removeItem(at: request)
                requestActive = false
            }
        }
        guard let pid, let snapshotURL,
              let size = try? snapshotURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 32_768,
              let data = try? Data(contentsOf: snapshotURL),
              var value = try? JSONDecoder().decode(FrameBarReading.self, from: data),
              value.schemaVersion == 1, value.gamePID == pid,
              now.timeIntervalSince1970 - value.timestamp >= 0,
              now.timeIntervalSince1970 - value.timestamp <= 10,
              value.timestamp > (samples.last?.timestamp ?? -.infinity) else { return }
        let statsAge = value.gameStatsTimestamp.map { now.timeIntervalSince1970 - $0 } ?? .infinity
        if statsAge < 0 || statsAge > 10 {
            value.gameFPS = nil; value.pingMS = nil; value.gameCPUMS = nil; value.gameGPUMS = nil
        }
        value.captureFPS = performance.startedAt == nil ? nil : performance.videoSamplesPerSecond
        value.encoderDrops = performance.videoInputBackpressureDrops
        samples.append(value)
        samples.removeAll { now.timeIntervalSince1970 - $0.timestamp > 620 }
    }

    func snapshot(segments: [ReplaySegment], duration: Double) -> [TimedTelemetry] {
        Self.timeline(samples: samples, segments: segments, duration: duration)
    }

    nonisolated static func export(entries: [TimedTelemetry], folder: URL) async throws -> (URL, URL)? {
        guard !entries.isEmpty else { return nil }
        return try await Task.detached(priority: .utility) {
            let json = folder.appendingPathComponent("telemetry.json")
            let srt = folder.appendingPathComponent("clip.srt")
            try JSONEncoder().encode(entries).write(to: json, options: .atomic)
            try Self.csv(entries).write(to: folder.appendingPathComponent("telemetry.csv"), atomically: true, encoding: .utf8)
            try Self.subtitles(entries).write(to: srt, atomically: true, encoding: .utf8)
            return (json, srt)
        }.value
    }

    nonisolated static func timeline(samples: [FrameBarReading], segments: [ReplaySegment], duration: Double) -> [TimedTelemetry] {
        var skip = max(0, segments.reduce(0) { $0 + $1.durationSeconds } - duration)
        var cursor = 0.0
        var result: [TimedTelemetry] = []
        for segment in segments {
            let leading = min(skip, segment.durationSeconds)
            skip -= leading
            let length = segment.durationSeconds - leading
            guard length > 0 else { continue }
            let start = segment.startedAt.timeIntervalSince1970 + leading
            let end = start + length
            for (index, value) in samples.enumerated() {
                let next = index + 1 < samples.count ? samples[index + 1].timestamp : value.timestamp + 3
                let upper = min(end, next, value.timestamp + 3)
                let lower = max(start, value.timestamp)
                if upper > lower {
                    result.append(TimedTelemetry(seconds: cursor + lower - start, duration: upper - lower, reading: value))
                }
            }
            cursor += length
        }
        return result
    }

    nonisolated static func subtitles(_ entries: [TimedTelemetry]) -> String {
        func stamp(_ seconds: Double) -> String {
            let ms = max(0, Int((seconds * 1000).rounded()))
            return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
        }
        return entries.enumerated().map { index, entry in
            "\(index + 1)\n\(stamp(entry.seconds)) --> \(stamp(entry.seconds + entry.duration))\n\(entry.reading.subtitle)\n"
        }.joined(separator: "\n")
    }

    nonisolated static func trimmed(_ entries: [TimedTelemetry], start: Double, end: Double) -> [TimedTelemetry] {
        entries.compactMap { entry in
            let lower = max(start, entry.seconds)
            let upper = min(end, entry.seconds + entry.duration)
            guard upper > lower else { return nil }
            return TimedTelemetry(seconds: lower - start, duration: upper - lower, reading: entry.reading)
        }
    }

    nonisolated static func csv(_ entries: [TimedTelemetry]) -> String {
        func number(_ value: Double?) -> String {
            guard let value, value.isFinite else { return "" }
            return String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
        }
        let header = "clip_seconds,duration_seconds,sampled_game_fps,system_cpu_percent,memory_gib,gpu_percent,game_cpu_percent_one_core,game_memory_gib,ping_ms,cpu_ms,gpu_ms,capture_fps_session_average,encoder_drops\n"
        return header + entries.map { e in
            [number(e.seconds), number(e.duration), number(e.reading.gameFPS), number(e.reading.cpu), number(e.reading.memoryUsed), number(e.reading.gpu), number(e.reading.robloxCPU), number(e.reading.robloxMemory), number(e.reading.pingMS), number(e.reading.gameCPUMS), number(e.reading.gameGPUMS), number(e.reading.captureFPS), e.reading.encoderDrops.map(String.init) ?? ""].joined(separator: ",")
        }.joined(separator: "\n") + "\n"
    }

    nonisolated static func trimSidecars(source: URL?, folder: URL, start: Double, end: Double) async throws -> (URL, URL)? {
        guard let source else { return nil }
        return try await Task.detached(priority: .utility) {
            let entries = trimmed(try JSONDecoder().decode([TimedTelemetry].self, from: Data(contentsOf: source)), start: start, end: end)
            guard !entries.isEmpty else { return nil }
            let json = folder.appendingPathComponent("telemetry.json")
            let srt = folder.appendingPathComponent("clip.srt")
            try JSONEncoder().encode(entries).write(to: json, options: .atomic)
            try csv(entries).write(to: folder.appendingPathComponent("telemetry.csv"), atomically: true, encoding: .utf8)
            try subtitles(entries).write(to: srt, atomically: true, encoding: .utf8)
            return (json, srt)
        }.value
    }

    nonisolated static func exportSidecars(clip: Clip, destination: URL) async throws {
        try await validateExportSidecars(clip: clip, destination: destination)
        try await Task.detached(priority: .utility) {
            for (source, target) in sidecars(clip: clip, destination: destination) {
                guard !FileManager.default.fileExists(atPath: target.path) else { continue }
                try FileManager.default.copyItem(at: source, to: target)
            }
        }.value
    }

    nonisolated private static func sidecars(clip: Clip, destination: URL) -> [(URL, URL)] {
        let stem = destination.deletingPathExtension()
        let csvURL = clip.telemetryURL?.deletingLastPathComponent().appendingPathComponent("telemetry.csv")
        let bookmarksURL = clip.bookmarks.isEmpty ? nil : clip.folderURL.appendingPathComponent("bookmarks.json")
        return [(clip.subtitleURL, "srt"), (clip.telemetryURL, "telemetry.json"), (csvURL, "telemetry.csv"), (bookmarksURL, "bookmarks.json")].compactMap { source, suffix in
            guard let source, FileManager.default.fileExists(atPath: source.path) else { return nil }
            return (source, stem.appendingPathExtension(suffix))
        }
    }

    nonisolated static func validateExportSidecars(clip: Clip, destination: URL) async throws {
        try await Task.detached(priority: .utility) {
            for (source, target) in sidecars(clip: clip, destination: destination) where FileManager.default.fileExists(atPath: target.path) {
                let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize
                guard let size, size <= 32 * 1024 * 1024,
                      size == (try target.resourceValues(forKeys: [.fileSizeKey]).fileSize),
                      try Data(contentsOf: source) == Data(contentsOf: target) else {
                    throw TelemetryExportError.conflictingSidecar(target.lastPathComponent)
                }
            }
        }.value
    }
}

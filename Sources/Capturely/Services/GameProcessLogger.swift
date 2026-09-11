import Foundation
import Darwin

struct GameProcessSample: Sendable {
    var timestamp = Date()
    var pid: Int32?
    var cpuPercent: Double?
    var memoryBytes: UInt64?
    var receivedBytesPerSecond: Double?
    var sentBytesPerSecond: Double?
    var captureFPS: Double = 0
    var encoderDrops = 0
    var status = "Starts with game capture"
    var logURL: URL?

    static let header = "timestamp_utc,pid,game_cpu_percent,game_memory_bytes,receive_bytes_per_second,send_bytes_per_second,capture_fps,encoder_drops,status\n"
    var csv: String {
        let fields = [ISO8601DateFormatter().string(from: timestamp), pid.map(String.init) ?? "",
                      cpuPercent.map { String(format: "%.2f", $0) } ?? "", memoryBytes.map(String.init) ?? "",
                      receivedBytesPerSecond.map { String(format: "%.1f", $0) } ?? "",
                      sentBytesPerSecond.map { String(format: "%.1f", $0) } ?? "",
                      String(format: "%.1f", captureFPS), String(encoderDrops), status]
        return fields.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") + "\n"
    }
}

@MainActor final class GameProcessLogger {
    private var pid: Int32?
    private var process: Process?
    private var output: Pipe?
    private var pending = ""
    private var latestNetwork: (received: UInt64, sent: UInt64, time: Double)?
    private var networkRates: (received: Double, sent: Double, time: Double)?
    private var lastCPU: (seconds: Double, time: Double, start: UInt64)?
    private var samples: [GameProcessSample] = []
    private var file: FileHandle?
    private var logURL: URL?
    private var logBytes = 0
    private var loggerError: String?
    private let logsDirectory: URL?

    init(logsDirectory: URL? = nil) { self.logsDirectory = logsDirectory }

    func sample(pid requestedPID: Int32?, appUsage: ResourceUsage, performance: CapturePerformanceSnapshot) -> GameProcessSample {
        if requestedPID != pid {
            stop()
            if let requestedPID { start(pid: requestedPID) }
        }
        guard let pid else { return GameProcessSample(logURL: logURL) }
        let now = ProcessInfo.processInfo.systemUptime
        var result = GameProcessSample(pid: pid, captureFPS: appUsage.captureFPS,
            encoderDrops: performance.videoInputBackpressureDrops, status: "Network unavailable / no process sockets", logURL: logURL)
        var usage = rusage_info_v0()
        let status = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V0, $0) }
        }
        if status == 0 {
            let cpu = Double(usage.ri_user_time + usage.ri_system_time) / 1_000_000_000
            result.memoryBytes = usage.ri_phys_footprint
            if let previous = lastCPU, previous.start == usage.ri_proc_start_abstime {
                result.cpuPercent = ResourceUsage.cpuPercent(cpuDelta: cpu - previous.seconds, elapsed: now - previous.time)
            }
            lastCPU = (cpu, now, usage.ri_proc_start_abstime)
        } else {
            lastCPU = nil
            result.status = "Process counters unavailable (\(errno))"
        }
        if let rates = networkRates, now - rates.time < 6 {
            result.receivedBytesPerSecond = rates.received
            result.sentBytesPerSecond = rates.sent
            if status == 0 { result.status = "Logging process traffic; not game ping" }
        }
        if let loggerError { result.status += "; " + loggerError }
        samples.append(result)
        samples.removeAll { $0.timestamp < result.timestamp.addingTimeInterval(-620) }
        append(result.csv)
        return result
    }

    func saveWindow(pid: Int32?, endingAt end: Date, duration: Double, to url: URL) throws -> Bool {
        let selected = samples.filter { $0.pid == pid && $0.timestamp >= end.addingTimeInterval(-duration - 2) && $0.timestamp <= end.addingTimeInterval(2) }
        guard !selected.isEmpty else { return false }
        try (GameProcessSample.header + selected.map(\.csv).joined()).write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    func stop() {
        output?.fileHandleForReading.readabilityHandler = nil
        if let process, process.isRunning { process.terminate() }
        try? output?.fileHandleForReading.close()
        process = nil
        output = nil
        try? file?.close()
        file = nil
        pid = nil
        lastCPU = nil
        latestNetwork = nil
        networkRates = nil
        pending = ""
        loggerError = nil
    }

    private func start(pid: Int32) {
        self.pid = pid
        samples.removeAll(keepingCapacity: true)
        do {
            let directory = logsDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Capturely/ProcessLogs", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("session-\(UUID().uuidString).csv")
            try Data(GameProcessSample.header.utf8).write(to: url, options: .atomic)
            file = try FileHandle(forWritingTo: url)
            try file?.seekToEnd()
            logURL = url
            logBytes = GameProcessSample.header.utf8.count
        } catch { loggerError = "Log file: \(error.localizedDescription)" }
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        task.arguments = ["-L", "0", "-P", "-n", "-x", "-s", "2", "-p", String(pid), "-J", "bytes_in,bytes_out"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            Task { @MainActor in self?.consume(data, pid: pid) }
        }
        do { try task.run(); process = task; output = pipe }
        catch { pipe.fileHandleForReading.readabilityHandler = nil; loggerError = "Network monitor: \(error.localizedDescription)" }
    }

    private func append(_ text: String) {
        // ponytail: cap each session at 10 MB; per-clip rolling samples continue after the cap.
        guard logBytes < 10_000_000 else { loggerError = "Session log reached 10 MB; restart logging for a new file"; return }
        do { try file?.write(contentsOf: Data(text.utf8)); logBytes += text.utf8.count }
        catch { loggerError = "Log write: \(error.localizedDescription)" }
    }

    private func consume(_ data: Data, pid sourcePID: Int32) {
        guard sourcePID == pid else { return }
        pending += String(decoding: data, as: UTF8.self)
        while let newline = pending.firstIndex(of: "\n") {
            let line = String(pending[..<newline])
            pending.removeSubrange(...newline)
            guard let counters = Self.parseNetworkRow(line, pid: sourcePID) else { continue }
            let now = ProcessInfo.processInfo.systemUptime
            if let previous = latestNetwork, now > previous.time,
               counters.received >= previous.received, counters.sent >= previous.sent {
                networkRates = (Double(counters.received - previous.received) / (now - previous.time),
                                Double(counters.sent - previous.sent) / (now - previous.time), now)
            } else { networkRates = nil }
            latestNetwork = (counters.received, counters.sent, now)
        }
        if pending.utf8.count > 16384 { pending = "" }
    }

    nonisolated static func parseNetworkRow(_ line: String, pid: Int32) -> (received: UInt64, sent: UInt64)? {
        let columns = line.split(separator: ",", omittingEmptySubsequences: false)
        guard columns.count >= 3, columns[0].hasSuffix(".\(pid)"),
              let received = UInt64(columns[1]), let sent = UInt64(columns[2]) else { return nil }
        return (received, sent)
    }
}

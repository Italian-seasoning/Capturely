import AppKit
import Darwin
import SwiftUI

struct ResourceUsage: Equatable, Sendable {
    var cpuPercent: Double?
    var memoryBytes: UInt64?
    var captureFPS: Double = 0
    static let empty = ResourceUsage()

    static func cpuPercent(cpuDelta: Double, elapsed: Double) -> Double? {
        guard elapsed > 0, cpuDelta >= 0, cpuDelta.isFinite else { return nil }
        return cpuDelta / elapsed * 100
    }
}

struct ResourceSampler {
    private var lastCPU: Double?
    private var lastTime: Double?
    private var lastFrames = 0
    private var lastSession: Date?

    mutating func sample(performance: CapturePerformanceSnapshot, recording: Bool) -> ResourceUsage {
        let now = ProcessInfo.processInfo.systemUptime
        var usage = rusage()
        let success = getrusage(RUSAGE_SELF, &usage) == 0
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        var result = ResourceUsage.empty
        if success, let lastCPU, let lastTime {
            result.cpuPercent = ResourceUsage.cpuPercent(cpuDelta: cpu - lastCPU, elapsed: now - lastTime)
        }
        if recording, performance.startedAt == lastSession, let lastTime, now > lastTime {
            result.captureFPS = Double(max(0, performance.videoSamplesAppended - lastFrames)) / (now - lastTime)
        }
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if status == KERN_SUCCESS { result.memoryBytes = info.phys_footprint }
        lastCPU = success ? cpu : nil
        lastTime = now
        lastFrames = performance.videoSamplesAppended
        lastSession = recording ? performance.startedAt : nil
        return result
    }
}

struct PerformancePanel: View {
    @ObservedObject var backend: CaptureBackend
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            HStack(spacing: 24) {
                Text(String(format: "CAPTURE %.1f fps", backend.resourceUsage.captureFPS))
                Text("ENCODER DROPS \(backend.health.performance.videoInputBackpressureDrops)")
                Text(String(format: "BUFFER %.1fs", backend.health.currentBufferDurationSeconds))
                Spacer(minLength: 0)
            }.padding(.top, 8)
            Text("CPU: 100% = one core. Memory: current app footprint. Helper processes are excluded. Updates every 2s; capture FPS may fall on static screens.")
                .font(.caption2).foregroundStyle(CyberTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
            HStack(spacing: 16) {
                Text(backend.gameProcessSample.cpuPercent.map { String(format: "GAME CPU %.1f%%", $0) } ?? "GAME CPU —")
                Text(backend.gameProcessSample.memoryBytes.map { String(format: "MEM %.0f MB", Double($0) / 1_000_000) } ?? "MEM —")
                Text(backend.gameProcessSample.receivedBytesPerSecond.map { String(format: "↓ %.1f KB/s", $0 / 1000) } ?? "↓ —")
                Text(backend.gameProcessSample.sentBytesPerSecond.map { String(format: "↑ %.1f KB/s", $0 / 1000) } ?? "↑ —")
                Spacer(minLength: 0)
            }.padding(.top, 8)
            HStack {
                Text(backend.gameProcessSample.status).font(.caption2)
                Spacer()
                Button("Reveal session log", action: backend.revealProcessLog).disabled(backend.gameProcessSample.logURL == nil)
            }.padding(.top, 4)
        } label: {
            HStack {
                Label("PERFORMANCE", systemImage: "gauge.with.dots.needle.67percent")
                Spacer()
                Text(backend.resourceUsage.cpuPercent.map { String(format: "CPU %.1f%%", $0) } ?? "CPU —")
                Text(backend.resourceUsage.memoryBytes.map { String(format: "MEM %.0f MB", Double($0) / 1_000_000) } ?? "MEM —")
            }
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .tint(CyberTheme.red).foregroundStyle(CyberTheme.muted)
        .padding(12).background(CyberTheme.panel)
    }
}

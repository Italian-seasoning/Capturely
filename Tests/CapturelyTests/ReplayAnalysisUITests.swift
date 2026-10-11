import AppKit
import SwiftUI
import Testing
@testable import Capturely

/// Optional native render check; never captures the desktop or changes the user's library.
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["CAPTURELY_RENDER_REPLAY_ANALYSIS"] != nil))
func replayAnalysisRendersInANativeWindow() async throws {
    let output = try #require(ProcessInfo.processInfo.environment["CAPTURELY_RENDER_REPLAY_ANALYSIS"])
    _ = NSApplication.shared
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var clip = Clip(gameID: UUID(), gameName: "Synthetic verification", capturedAt: Date(),
                    durationSeconds: 20, presetName: "Test", folderURL: folder,
                    clipURL: folder.appendingPathComponent("clip.mov"),
                    metadataURL: folder.appendingPathComponent("metadata.json"),
                    thumbnailURL: folder.appendingPathComponent("thumbnail.jpg"))
    clip.telemetryURL = folder.appendingPathComponent("telemetry.json")
    var comparison = clip
    comparison.id = UUID()
    comparison.title = "Comparison fixture"
    let entries = [0.0, 5, 15].enumerated().map { index, second in
        TimedTelemetry(seconds: second, duration: 5,
            reading: FrameBarReading(schemaVersion: 1, gamePID: 1, timestamp: 100 + second,
                gameFPS: [120.0, 80, 100][index], cpu: 40, gpu: 70, pingMS: 31))
    }
    let host = NSHostingView(rootView:
        VStack(alignment: .leading, spacing: 16) {
            Text("Synthetic replay · native UI verification").font(.headline)
            ClipPerformanceView(clip: clip, entries: entries, duration: 20,
                playbackSeconds: 7, comparisonClips: [comparison], seek: { _ in })
        }.padding(24).frame(width: 600, height: 420)
            .background(CyberTheme.void).foregroundStyle(CyberTheme.text).preferredColorScheme(.dark))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 420),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.title = "Replay analysis verification"
    window.contentView = host
    window.orderFront(nil)
    defer { window.close() }
    // Allow SwiftUI's task and Charts layout to complete on the main run loop.
    try await Task.sleep(for: .milliseconds(600))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    #expect(png.count > 1_000)
    try png.write(to: URL(fileURLWithPath: output), options: .atomic)
}

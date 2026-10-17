import AppKit
import Combine
import SwiftUI
import Testing
@testable import Capturely

@Suite(.serialized)
@MainActor
struct CapturelyAppObservationTests {
    @Test func menuLabelPublishesOnlyRecordingTransitions() {
        let source = CurrentValueSubject<RecordingDisplayStatus, Never>(status(recording: false))
        let label = CapturelyMenuLabel(status: source.eraseToAnyPublisher())
        var changes: [Bool] = []
        let subscription = label.recordingChanges.sink { changes.append($0) }
        defer { subscription.cancel() }

        source.send(status(recording: false))
        source.send(status(recording: true, buffered: 1))
        source.send(status(recording: true, buffered: 20))
        source.send(status(recording: true, buffered: 60))
        source.send(status(recording: false))

        #expect(changes == [false, true, false])
    }

    @Test func unrelatedBackendPublicationsDoNotReachMenuLabel() {
        let backend = CaptureBackend()
        let label = CapturelyMenuLabel(backend: backend)
        var changes: [Bool] = []
        let subscription = label.recordingChanges.sink { changes.append($0) }
        defer { subscription.cancel() }

        // The same notification emitted before health/resource Published assignments.
        for _ in 0..<12 { backend.objectWillChange.send() }
        backend.toggleDebugVisibility()

        #expect(changes == [false])
    }

    @Test func hostedMenuLabelUpdatesWhenRecordingStartsAndStops() async throws {
        _ = NSApplication.shared
        let source = CurrentValueSubject<RecordingDisplayStatus, Never>(status(recording: false))
        let host = NSHostingView(rootView: CapturelyMenuLabel(status: source.eraseToAnyPublisher()))
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 40)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }

        _ = try pixels(host)
        try await Task.sleep(for: .milliseconds(80))
        let idle = try pixels(host)
        source.send(status(recording: true))
        try await Task.sleep(for: .milliseconds(80))
        let recording = try pixels(host)
        #expect(recording != idle)

        source.send(status(recording: true, buffered: 30))
        try await Task.sleep(for: .milliseconds(30))
        #expect(try pixels(host) == recording)
        source.send(status(recording: false))
        try await Task.sleep(for: .milliseconds(80))
        #expect(try pixels(host) == idle)
    }

    private func status(recording: Bool, buffered: Double = 0) -> RecordingDisplayStatus {
        RecordingDisplayStatus(
            captureState: recording ? .recording(game: Game(displayName: "Fixture"), preset: .balanced) : .idle,
            windowTitle: nil,
            isWindowLocked: recording,
            bufferDurationSeconds: buffered
        )
    }

    private func pixels<Content: View>(_ host: NSHostingView<Content>) throws -> [UInt8] {
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try #require(bitmap.bitmapData)
        return Array(UnsafeBufferPointer(start: data, count: bitmap.bytesPerRow * bitmap.pixelsHigh))
    }
}

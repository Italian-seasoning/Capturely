import AppKit
import SwiftUI
import Testing
@testable import Capturely

@MainActor
private final class VisibilityTestWindow: NSWindow {
    var isTestOccluded = false
    var isTestMiniaturized = false

    // Supply occlusion independently of WindowServer focus and the test host's event loop.
    override var occlusionState: NSWindow.OcclusionState {
        isVisible && !isTestOccluded ? [.visible] : []
    }

    override var isMiniaturized: Bool { isTestMiniaturized }
}

@MainActor
@Test func recordingVisibilityTracksOnlyItsAttachedWindowAndDeduplicatesChanges() async throws {
    _ = NSApplication.shared
    let first = VisibilityTestWindow(contentRect: NSRect(x: 40, y: 40, width: 120, height: 90),
                         styleMask: [.borderless], backing: .buffered, defer: false)
    let second = VisibilityTestWindow(contentRect: NSRect(x: 190, y: 40, width: 120, height: 90),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    for window in [first, second] {
        window.isReleasedWhenClosed = false
        window.level = .floating
    }
    defer { first.close(); second.close() }
    let observer = RecordingWindowVisibilityView()
    var changes: [Bool] = []
    observer.onVisibilityChanged = { changes.append($0) }
    first.contentView = observer
    #expect(changes.isEmpty)
    try await Task.sleep(for: .milliseconds(80))
    #expect(changes == [false])

    first.orderFrontRegardless()
    NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: first)
    try await Task.sleep(for: .milliseconds(120))
    #expect(first.occlusionState.contains(.visible))
    #expect(changes.last == true)
    let visibleCount = changes.count
    NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: first)
    try await Task.sleep(for: .milliseconds(30))
    #expect(changes.count == visibleCount)

    for condition in [\VisibilityTestWindow.isTestOccluded, \.isTestMiniaturized] {
        first[keyPath: condition] = true
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: first)
        try await Task.sleep(for: .milliseconds(30))
        #expect(changes.last == false)
        first[keyPath: condition] = false
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: first)
        try await Task.sleep(for: .milliseconds(30))
        #expect(changes.last == true)
    }

    first.orderOut(nil)
    NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: first)
    try await Task.sleep(for: .milliseconds(80))
    #expect(changes.last == false)
    let hiddenCount = changes.count
    second.contentView = observer
    first.orderFrontRegardless()
    NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: first)
    try await Task.sleep(for: .milliseconds(80))
    #expect(changes.count == hiddenCount)

    second.orderFrontRegardless()
    NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: second)
    try await Task.sleep(for: .milliseconds(120))
    #expect(second.occlusionState.contains(.visible))
    #expect(changes.last == true)
    #expect(changes == [false, true, false, true, false, true, false, true])
}

@MainActor
@Test func configuredWindowKeepsMinimizeCapabilityWithoutNativeChrome() async throws {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let host = NSHostingView(rootView: FixedWindowConfigurator().frame(width: 820, height: 560))
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    // A hidden host needs an offscreen draw to materialize the configurator.
    if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
        host.cacheDisplay(in: host.bounds, to: bitmap)
    }
    try await Task.sleep(for: .milliseconds(100))

    #expect(window.styleMask == [.borderless, .resizable, .miniaturizable])
    #expect(window.isMiniaturizable)
    #expect(window.minSize == NSSize(width: CapturelyWindowMetrics.minimumContentWidth,
                                    height: CapturelyWindowMetrics.minimumContentHeight))
    #expect(!window.isVisible)
}

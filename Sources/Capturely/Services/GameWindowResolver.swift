import Foundation
import ScreenCaptureKit

struct CaptureDisplayBounds: Equatable, Sendable {
    var displayID: UInt32
    var frame: CGRect
}

struct ResolvedGameWindow {
    var window: SCWindow
    var title: String
    var owningProcessID: pid_t
}

struct ResolvedCaptureSource {
    var filter: SCContentFilter
    var title: String
    var width: Int
    var height: Int
    var isWindowLocked: Bool
}

struct GameWindowResolver {
    func resolveSource(
        for match: RunningGameMatch,
        mode: CaptureSourceMode,
        selectedDisplayID: UInt32?
    ) async throws -> ResolvedCaptureSource? {
        switch mode {
        case .selectedDisplay:
            return try await resolveDisplay(for: match, selectedDisplayID: selectedDisplayID)
        case .gameWindow:
            guard let window = try await resolveWindow(for: match) else { return nil }
            let filter = SCContentFilter(desktopIndependentWindow: window.window)
            return ResolvedCaptureSource(
                filter: filter,
                title: window.title,
                width: Int(filter.contentRect.width * CGFloat(filter.pointPixelScale)),
                height: Int(filter.contentRect.height * CGFloat(filter.pointPixelScale)),
                isWindowLocked: true
            )
        }
    }

    func resolveWindow(for match: RunningGameMatch) async throws -> ResolvedGameWindow? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let candidates = content.windows.filter { window in
            window.owningApplication?.processID == match.processIdentifier
        }

        guard let selected = candidates.sorted(by: { lhs, rhs in
            lhs.frame.width * lhs.frame.height > rhs.frame.width * rhs.frame.height
        }).first else {
            return nil
        }

        return ResolvedGameWindow(
            window: selected,
            title: selected.title ?? match.game.displayName,
            owningProcessID: match.processIdentifier
        )
    }

    private func resolveDisplay(for match: RunningGameMatch, selectedDisplayID: UInt32?) async throws -> ResolvedCaptureSource? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let matchingWindows = content.windows.filter { window in
            window.owningApplication?.processID == match.processIdentifier
        }
        let selectedDisplay = selectedDisplayID.flatMap { displayID in
            content.displays.first { $0.displayID == displayID }
        }

        let display = selectedDisplay ?? displayContainingLargestGameWindow(
            displays: content.displays,
            windows: matchingWindows
        ) ?? content.displays.first

        guard let display else { return nil }

        let excludedApplications = content.applications.filter { application in
            application.processID == ProcessInfo.processInfo.processIdentifier
        }

        return ResolvedCaptureSource(
            filter: SCContentFilter(display: display, excludingApplications: excludedApplications, exceptingWindows: []),
            title: displayTitle(for: display, fallback: match.game.displayName),
            width: display.width,
            height: display.height,
            isWindowLocked: !matchingWindows.isEmpty
        )
    }

    private func displayContainingLargestGameWindow(displays: [SCDisplay], windows: [SCWindow]) -> SCDisplay? {
        guard let largestWindow = windows.max(by: { lhs, rhs in
            lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
        }) else {
            return nil
        }

        let bounds = displays.map { display in
            CaptureDisplayBounds(displayID: display.displayID, frame: Self.displayFrame(for: display))
        }
        guard let displayID = Self.displayIDContainingLargestWindow(
            displayBounds: bounds,
            windowFrames: [largestWindow.frame]
        ) else {
            return nil
        }
        return displays.first { $0.displayID == displayID }
    }

    private func displayTitle(for display: SCDisplay, fallback: String) -> String {
        "\(fallback) screen · \(display.width)x\(display.height)"
    }

    nonisolated static func displayIDContainingLargestWindow(
        displayBounds: [CaptureDisplayBounds],
        windowFrames: [CGRect]
    ) -> UInt32? {
        guard let largestWindow = windowFrames.max(by: { lhs, rhs in
            lhs.width * lhs.height < rhs.width * rhs.height
        }) else {
            return nil
        }

        return displayBounds.max { lhs, rhs in
            lhs.frame.intersectionArea(with: largestWindow) < rhs.frame.intersectionArea(with: largestWindow)
        }.flatMap { display in
            display.frame.intersectionArea(with: largestWindow) > 0 ? display.displayID : nil
        }
    }

    private static func displayFrame(for display: SCDisplay) -> CGRect {
        let frame = CGDisplayBounds(CGDirectDisplayID(display.displayID))
        guard !frame.isEmpty else {
            return CGRect(x: 0, y: 0, width: display.width, height: display.height)
        }
        return frame
    }
}

private extension CGRect {
    func intersectionArea(with other: CGRect) -> CGFloat {
        let intersection = intersection(other)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        return intersection.width * intersection.height
    }
}

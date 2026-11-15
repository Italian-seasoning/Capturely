import AppKit
import Combine
import SwiftUI

struct RecordingWindowVisibility: NSViewRepresentable {
    var onVisibilityChanged: (Bool) -> Void

    func makeNSView(context: Context) -> RecordingWindowVisibilityView {
        let view = RecordingWindowVisibilityView()
        view.onVisibilityChanged = onVisibilityChanged
        return view
    }

    func updateNSView(_ view: RecordingWindowVisibilityView, context: Context) {
        view.onVisibilityChanged = onVisibilityChanged
    }
}

final class RecordingWindowVisibilityView: NSView {
    var onVisibilityChanged: (Bool) -> Void = { _ in }
    private var observation: AnyCancellable?
    private var wasVisible = true

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observation = nil
        guard let window else { return }
        observation = NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification, object: window)
            .sink { [weak self] _ in self?.reportVisibility() }
        reportVisibility()
    }

    private func reportVisibility() {
        Task { @MainActor [weak self] in
            guard let self, let window = self.window else { return }
            let visible = window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
            guard visible != self.wasVisible else { return }
            self.wasVisible = visible
            self.onVisibilityChanged(visible)
        }
    }
}

import AppKit
import SwiftUI

struct FixedWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        let minimumSize = NSSize(
            width: CapturelyWindowMetrics.minimumContentWidth,
            height: CapturelyWindowMetrics.minimumContentHeight
        )
        let currentSize = window.contentView?.frame.size ?? .zero
        if currentSize.width < minimumSize.width || currentSize.height < minimumSize.height {
            window.setContentSize(minimumSize)
        }
        window.minSize = minimumSize
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let cyberWindowMask: NSWindow.StyleMask = [.borderless, .resizable]
        if window.styleMask != cyberWindowMask {
            window.styleMask = cyberWindowMask
        }
        window.title = "Capturely"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.backgroundColor = .black
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
    }
}

import AppKit

enum CapturelyWindowPresenter {
    @MainActor
    static func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        guard let window = mainWindow else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor
    static func hideMainWindow() {
        mainWindow?.orderOut(nil)
    }

    @MainActor
    private static var mainWindow: NSWindow? {
        NSApp.windows.first { window in
            window.contentView != nil && window.title == "Capturely"
        } ?? NSApp.windows.first { window in
            window.contentView != nil && !(window is NSPanel)
        }
    }
}

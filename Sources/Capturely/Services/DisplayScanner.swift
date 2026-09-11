import Foundation
import ScreenCaptureKit

struct DisplayScanner {
    func scanDisplays() async -> [CaptureDisplayOption] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            return []
        }

        return content.displays.enumerated().map { index, display in
            CaptureDisplayOption(
                displayID: display.displayID,
                name: "Display \(index + 1)",
                width: display.width,
                height: display.height
            )
        }
    }
}

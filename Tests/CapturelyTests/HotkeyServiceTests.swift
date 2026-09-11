import AppKit
import Testing
@testable import Capturely

@Test @MainActor func overlayKeepsGameFocusAndJoinsFullscreen() {
    let panel = GameOverlayPanel()
    #expect(!panel.canBecomeKey)
    #expect(!panel.canBecomeMain)
    #expect(panel.styleMask.contains(.nonactivatingPanel))
    #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    #expect(panel.collectionBehavior.contains(.canJoinAllApplications))
    #expect(!panel.hidesOnDeactivate)
    #expect(panel.frame.size == NSSize(width: 300, height: 132))
}

@Test func saveClipHotkeyMatchesOptionCommandC() {
    let flags: NSEvent.ModifierFlags = [.option, .command]

    #expect(HotkeyService.isSaveClipHotkey(characters: "c", modifierFlags: flags))
    #expect(HotkeyService.isSaveClipHotkey(characters: "C", modifierFlags: flags))
    #expect(!HotkeyService.isSaveClipHotkey(characters: "v", modifierFlags: flags))
    #expect(!HotkeyService.isSaveClipHotkey(characters: "c", modifierFlags: [.command]))
}

@Test func saveClipHotkeyUsesConfiguredShortcut() {
    let hotkey = SaveClipHotkey.shiftCommandC

    #expect(HotkeyService.isSaveClipHotkey(characters: "c", modifierFlags: [.shift, .command], hotkey: hotkey))
    #expect(!HotkeyService.isSaveClipHotkey(characters: "c", modifierFlags: [.option, .command], hotkey: hotkey))
}

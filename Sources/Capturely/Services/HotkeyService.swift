import AppKit
import Carbon
import Foundation

@MainActor
final class HotkeyService: ObservableObject {
    @Published private(set) var registrationError: String?
    private var eventHandler: EventHandlerRef?
    private var hotkeyRefs: [EventHotKeyRef] = []
    private var saveClipHandler: (() -> Void)?

    func start(hotkey: SaveClipHotkey = .optionCommandC, onSaveClip: @escaping () -> Void) {
        stop()
        saveClipHandler = onSaveClip

        registrationError = nil
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            MainActor.assumeIsolated {
                let service = Unmanaged<HotkeyService>.fromOpaque(context).takeUnretainedValue()
                if id.id == 1 { service.saveClipHandler?() }
                if id.id == 2 { NotificationCenter.default.post(name: .capturelyToggleOverlayRequested, object: nil) }
                if let seconds = HotkeyService.replaySeconds(forHotkeyID: id.id) {
                    NotificationCenter.default.post(name: .capturelySaveDurationRequested, object: seconds)
                }
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        guard result == noErr else {
            registrationError = "Keyboard shortcuts unavailable (\(result))."
            return
        }
        let modifiers = hotkey.modifiers.reduce(UInt32(0)) { value, modifier in
            value | modifier.carbonFlag
        }
        register(key: UInt32(hotkey.key.lowercased() == "r" ? kVK_ANSI_R : kVK_ANSI_C), modifiers: modifiers, id: 1)
        register(key: UInt32(kVK_ANSI_O), modifiers: UInt32(optionKey | cmdKey), id: 2)
        for (index, key) in [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3].enumerated() {
            register(key: UInt32(key), modifiers: UInt32(optionKey | cmdKey), id: UInt32(index + 3))
        }
    }

    func stop() {
        hotkeyRefs.forEach { UnregisterEventHotKey($0) }
        hotkeyRefs.removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
        saveClipHandler = nil
    }

    private func register(key: UInt32, modifiers: UInt32, id: UInt32) {
        var reference: EventHotKeyRef?
        let result = RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: 0x43505452, id: id), GetApplicationEventTarget(), 0, &reference)
        if result == noErr, let reference { hotkeyRefs.append(reference) }
        else {
            let label = Self.replaySeconds(forHotkeyID: id).map { "\($0)s replay" } ?? (id == 1 ? "Save replay" : "Overlay")
            registrationError = [registrationError, "\(label) shortcut unavailable (\(result)); check for conflicts."].compactMap { $0 }.joined(separator: " ")
        }
    }

    nonisolated static func replaySeconds(forHotkeyID id: UInt32) -> Int? {
        switch id { case 3: 15; case 4: 30; case 5: 60; default: nil }
    }

    nonisolated static func isSaveClipHotkey(
        characters: String?,
        modifierFlags: NSEvent.ModifierFlags,
        hotkey: SaveClipHotkey = .optionCommandC
    ) -> Bool {
        let normalized = characters?.lowercased() == hotkey.key.lowercased()
        let required = hotkey.modifiers.reduce(NSEvent.ModifierFlags()) { partialResult, modifier in
            partialResult.union(modifier.eventModifierFlag)
        }
        let hasRequired = modifierFlags.intersection(required) == required
        return normalized && hasRequired
    }
}

private extension HotkeyModifier {
    var carbonFlag: UInt32 {
        switch self {
        case .option: UInt32(optionKey)
        case .command: UInt32(cmdKey)
        case .shift: UInt32(shiftKey)
        case .control: UInt32(controlKey)
        }
    }
    var eventModifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .option:
            return .option
        case .command:
            return .command
        case .shift:
            return .shift
        case .control:
            return .control
        }
    }
}

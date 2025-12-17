import AppKit
import Carbon

final class HotkeyManager {
    var onToggleOverlay: (() -> Void)?
    var onToggleMode: (() -> Void)?
    var onExitInkMode: (() -> Void)?
    var onUndo: (() -> Void)?
    var onClear: (() -> Void)?
    var onToggleToolbox: (() -> Void)?

    private var hotKeys: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?

    func start() {
        installCarbonHotkeys()
        installLocalEscapeMonitor()
    }

    private func installCarbonHotkeys() {
        // Carbon hotkeys: system-wide without Accessibility permissions.
        // Defaults (can be changed later):
        //  - Toggle overlay: Ctrl+Shift+O
        //  - Toggle mode:   Ctrl+Shift+I
        //  - Undo:          Ctrl+Shift+Z
        //  - Clear:         Ctrl+Shift+X
        //  - Toolbox:       Ctrl+Shift+T
        let signature = OSType(fourCharCode("OSCR"))

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef else { return noErr }
                var hkId = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkId
                )
                guard status == noErr else { return status }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData!).takeUnretainedValue()
                manager.handleHotkey(id: hkId.id)
                return noErr
            },
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &handlerRef
        )

        let defaultModifiers = UInt32(controlKey | shiftKey)
        hotKeys.append(registerHotKey(signature: signature, id: 1, keyCode: UInt32(kVK_ANSI_O), modifiers: defaultModifiers))
        hotKeys.append(registerHotKey(signature: signature, id: 2, keyCode: UInt32(kVK_ANSI_I), modifiers: defaultModifiers))
        hotKeys.append(registerHotKey(signature: signature, id: 3, keyCode: UInt32(kVK_ANSI_Z), modifiers: defaultModifiers))
        hotKeys.append(registerHotKey(signature: signature, id: 4, keyCode: UInt32(kVK_ANSI_X), modifiers: defaultModifiers))
        hotKeys.append(registerHotKey(signature: signature, id: 5, keyCode: UInt32(kVK_ANSI_T), modifiers: defaultModifiers))
    }

    private func registerHotKey(signature: OSType, id: UInt32, keyCode: UInt32, modifiers: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let hkId = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hkId, GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            return nil
        }
        return ref
    }

    private func handleHotkey(id: UInt32) {
        switch id {
        case 1:
            onToggleOverlay?()
        case 2:
            onToggleMode?()
        case 3:
            onUndo?()
        case 4:
            onClear?()
        case 5:
            onToggleToolbox?()
        default:
            break
        }
    }

    private func installLocalEscapeMonitor() {
        // Escape to exit ink mode.
        _ = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.onExitInkMode?()
                return nil
            }
            return event
        }
    }
}

private func fourCharCode(_ s: String) -> UInt32 {
    var result: UInt32 = 0
    for u in s.utf8.prefix(4) {
        result = (result << 8) + UInt32(u)
    }
    return result
}

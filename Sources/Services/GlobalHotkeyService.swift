import Carbon.HIToolbox
import Foundation

/// System-wide shortcut through Carbon, which needs no Accessibility permission.
@MainActor
public final class GlobalHotkeyService {
    public static let shared = GlobalHotkeyService()

    public var onPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    /// Returns false when macOS refuses the combination, usually because another app holds it.
    @discardableResult
    public func register(_ shortcut: HotkeyShortcut) -> Bool {
        unregister()
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyId = EventHotKeyID(signature: OSType(0x434F_4341), id: 1) // "COCA"
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyId,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr else {
            print("[GlobalHotkeyService] RegisterEventHotKey failed:", status)
            return false
        }
        hotKeyRef = ref
        return true
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                Task { @MainActor in
                    GlobalHotkeyService.shared.onPressed?()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )
    }
}

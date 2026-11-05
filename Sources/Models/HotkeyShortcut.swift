import AppKit
import Carbon.HIToolbox

public struct HotkeyShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    public var keyLabel: String

    public static let defaultQuickCapture = HotkeyShortcut(
        keyCode: UInt32(kVK_ANSI_N),
        carbonModifiers: UInt32(controlKey | optionKey),
        keyLabel: "N"
    )

    public init(keyCode: UInt32, carbonModifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyLabel = keyLabel
    }

    /// Returns nil unless Command, Control, or Option is held, because a global shortcut
    /// without one would swallow normal typing in every other app.
    public init?(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, characters: String?) {
        guard !modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return nil }

        var modifiers = 0
        if modifierFlags.contains(.control) { modifiers |= controlKey }
        if modifierFlags.contains(.option) { modifiers |= optionKey }
        if modifierFlags.contains(.shift) { modifiers |= shiftKey }
        if modifierFlags.contains(.command) { modifiers |= cmdKey }

        self.keyCode = UInt32(keyCode)
        self.carbonModifiers = UInt32(modifiers)
        self.keyLabel = Self.specialKeyLabels[Int(keyCode)]
            ?? characters?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "Key \(keyCode)"
    }

    public var displayString: String {
        var symbols = ""
        if carbonModifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols + keyLabel
    }

    private static let specialKeyLabels: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_F1: "F1", kVK_F2: "F2",
        kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
    ]
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

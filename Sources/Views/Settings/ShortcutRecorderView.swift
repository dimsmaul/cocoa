import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, then press the new combination. Esc cancels.
struct ShortcutRecorderView: View {
    let shortcut: HotkeyShortcut
    let onRecord: (HotkeyShortcut) -> Void
    /// The live hotkey must be off while recording, or pressing it would open Quick Capture instead.
    let onRecordingChanged: (Bool) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(action: toggleRecording) {
                Text(isRecording ? "Press shortcut…" : shortcut.displayString)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(minWidth: 120)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .orange : nil)
            .accessibilityLabel(isRecording ? "Recording shortcut. Press a key combination, or Escape to cancel." : "Quick Capture shortcut: \(shortcut.displayString). Click to change.")

            if let hint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        hint = nil
        isRecording = true
        onRecordingChanged(true)

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if event.keyCode == UInt16(kVK_Escape), flags.isDisjoint(with: [.command, .control, .option, .shift]) {
                stopRecording()
            } else if let recorded = HotkeyShortcut(
                keyCode: event.keyCode,
                modifierFlags: flags,
                characters: event.charactersIgnoringModifiers
            ) {
                stopRecording()
                onRecord(recorded)
            } else {
                hint = "Include ⌘, ⌃, or ⌥ in the shortcut."
            }
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        onRecordingChanged(false)
    }
}
